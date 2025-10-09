#!/usr/bin/env python3
"""
PlateBridge Complete Pod Agent
Handles: Plate detection, streaming, recording uploads, heartbeats
"""

import json
import time
import asyncio
import logging
import os
import sys
import subprocess
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any
import yaml
import requests
import paho.mqtt.client as mqtt
from flask import Flask, Response, request, jsonify, send_file
import hashlib

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('platebridge-pod')

app = Flask(__name__)

# Global agent instance
agent = None


class CompletePodAgent:
    def __init__(self, config_path: str = "config.yaml"):
        self.config_path = config_path
        self.config = self.load_config()
        self.whitelist_cache = {}
        self.cache_path = Path("whitelist_cache.json")
        self.last_whitelist_refresh = None
        self.mqtt_client = None
        self.ffmpeg_process = None
        self.hls_output_dir = '/tmp/hls_output'

        os.makedirs(self.hls_output_dir, exist_ok=True)
        os.makedirs(self.config.get('recordings_dir', '/tmp/recordings'), exist_ok=True)

        self.load_whitelist_cache()

    def load_config(self) -> Dict[str, Any]:
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            required_fields = ['portal_url', 'pod_api_key', 'pod_id', 'camera_id']
            missing = [f for f in required_fields if f not in config]
            if missing:
                raise ValueError(f"Missing required config fields: {', '.join(missing)}")

            return config
        except FileNotFoundError:
            logger.error(f"Config file not found: {self.config_path}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            sys.exit(1)

    def load_whitelist_cache(self):
        if self.cache_path.exists():
            try:
                with open(self.cache_path, 'r') as f:
                    cache_data = json.load(f)
                    self.whitelist_cache = {
                        item['plate']: item
                        for item in cache_data.get('entries', [])
                    }
                logger.info(f"Loaded {len(self.whitelist_cache)} plates from cache")
            except Exception as e:
                logger.error(f"Error loading whitelist cache: {e}")

    def save_whitelist_cache(self, data):
        try:
            with open(self.cache_path, 'w') as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving whitelist cache: {e}")

    async def refresh_whitelist(self) -> bool:
        try:
            site_name = self.config.get('site_name', 'main-gate')
            company_id = self.config.get('company_id', '')

            url = f"{self.config['portal_url']}/api/plates"
            params = {
                'site': site_name,
                'company_id': company_id
            }

            logger.info("Fetching whitelist from portal...")
            response = requests.get(url, params=params, timeout=10)

            if response.status_code == 200:
                data = response.json()
                entries = data.get('entries', [])

                self.whitelist_cache = {
                    entry['plate']: entry
                    for entry in entries
                    if entry.get('enabled', True)
                }

                self.save_whitelist_cache(data)
                logger.info(f"Whitelist refreshed: {len(self.whitelist_cache)} plates")
                return True
            else:
                logger.error(f"Failed to fetch whitelist: HTTP {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Error refreshing whitelist: {e}")
            return False

    def is_plate_whitelisted(self, plate: str) -> bool:
        plate_normalized = plate.upper().replace(' ', '').replace('-', '')

        for cached_plate in self.whitelist_cache.keys():
            cached_normalized = cached_plate.upper().replace(' ', '').replace('-', '')
            if cached_normalized == plate_normalized:
                return True

        return False

    async def send_detection(self, plate: str, confidence: float = 0.95) -> dict:
        try:
            url = f"{self.config['portal_url']}/api/pod/detect"
            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            payload = {
                'site_id': self.config.get('site_id', ''),
                'plate': plate,
                'camera': self.config.get('camera_name', 'camera-1'),
                'pod_name': self.config['pod_id']
            }

            logger.info(f"Sending detection to portal: {plate}")
            response = requests.post(url, headers=headers, json=payload, timeout=10)

            if response.status_code == 200:
                result = response.json()
                action = result.get('action', 'unknown')
                gate_opened = result.get('gate_opened', False)

                logger.info(f"Portal response: action={action}, gate_opened={gate_opened}")

                if gate_opened:
                    logger.info(f"✓ GATE OPENED for plate: {plate}")
                else:
                    logger.info(f"✗ Access denied for plate: {plate}")

                return result
            else:
                logger.error(f"Failed to send detection: HTTP {response.status_code}")
                return {'success': False, 'action': 'deny'}

        except Exception as e:
            logger.error(f"Error sending detection: {e}")
            return {'success': False, 'action': 'deny'}

    def start_ffmpeg_stream(self):
        if self.ffmpeg_process and self.ffmpeg_process.poll() is None:
            return

        rtsp_url = self.config.get('camera_rtsp_url')
        if not rtsp_url:
            logger.warning("No RTSP URL configured, streaming disabled")
            return

        output_file = os.path.join(self.hls_output_dir, 'stream.m3u8')

        cmd = [
            'ffmpeg',
            '-rtsp_transport', 'tcp',
            '-i', rtsp_url,
            '-c:v', 'copy',
            '-c:a', 'aac',
            '-f', 'hls',
            '-hls_time', '2',
            '-hls_list_size', '5',
            '-hls_flags', 'delete_segments',
            '-hls_segment_filename', os.path.join(self.hls_output_dir, 'segment_%03d.ts'),
            output_file
        ]

        logger.info(f"Starting stream: {rtsp_url} -> HLS")

        try:
            self.ffmpeg_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            logger.info("Stream started successfully")
        except Exception as e:
            logger.error(f"Failed to start stream: {e}")

    def validate_stream_token(self, token: str) -> bool:
        try:
            parts = token.split('.')
            if len(parts) != 2:
                return False

            import base64
            payload_b64, signature = parts
            payload_json = base64.b64decode(payload_b64).decode('utf-8')
            payload = json.loads(payload_json)

            secret = self.config.get('stream_secret', 'default-secret')
            expected_data = payload_json + secret
            expected_hash = hashlib.sha256(expected_data.encode()).hexdigest()

            if signature != expected_hash:
                return False

            if payload.get('exp', 0) < time.time():
                return False

            return True
        except Exception as e:
            logger.error(f"Token validation error: {e}")
            return False

    def record_clip(self, duration: int = 30) -> Optional[str]:
        rtsp_url = self.config.get('camera_rtsp_url')
        if not rtsp_url:
            return None

        recordings_dir = self.config.get('recordings_dir', '/tmp/recordings')
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_file = os.path.join(recordings_dir, f'recording_{timestamp}.mp4')

        cmd = [
            'ffmpeg',
            '-rtsp_transport', 'tcp',
            '-i', rtsp_url,
            '-t', str(duration),
            '-c', 'copy',
            '-y',
            output_file
        ]

        logger.info(f"Recording {duration}s clip...")

        try:
            result = subprocess.run(cmd, capture_output=True, timeout=duration + 10)

            if result.returncode == 0 and os.path.exists(output_file):
                logger.info(f"Clip saved: {output_file}")
                return output_file
            else:
                logger.error(f"Recording failed: {result.stderr}")
                return None
        except Exception as e:
            logger.error(f"Recording error: {e}")
            return None

    async def upload_recording(self, file_path: str, plate_number: Optional[str] = None):
        try:
            filename = os.path.basename(file_path)
            camera_id = self.config['camera_id']

            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            logger.info(f"Requesting upload URL for {filename}")

            response = requests.post(
                f"{self.config['portal_url']}/api/pod/recordings/upload-url",
                headers=headers,
                json={
                    'camera_id': camera_id,
                    'filename': filename
                }
            )

            if response.status_code != 200:
                logger.error(f"Failed to get upload URL: {response.text}")
                return False

            upload_data = response.json()
            signed_url = upload_data['signed_url']

            logger.info("Uploading file...")

            with open(file_path, 'rb') as f:
                upload_response = requests.put(
                    signed_url,
                    data=f,
                    headers={'Content-Type': 'video/mp4'}
                )

            if upload_response.status_code not in [200, 201]:
                logger.error(f"Upload failed: {upload_response.status_code}")
                return False

            logger.info("Confirming upload...")

            file_size = os.path.getsize(file_path)

            confirm_response = requests.post(
                f"{self.config['portal_url']}/api/pod/recordings/confirm",
                headers=headers,
                json={
                    'camera_id': camera_id,
                    'file_path': upload_data['file_path'],
                    'file_size_bytes': file_size,
                    'duration_seconds': 30,
                    'event_type': 'plate_detection' if plate_number else 'manual',
                    'plate_number': plate_number
                }
            )

            if confirm_response.status_code == 200:
                logger.info("Upload confirmed successfully")
                os.remove(file_path)
                logger.info(f"Removed local file: {file_path}")
                return True
            else:
                logger.error(f"Failed to confirm: {confirm_response.text}")
                return False

        except Exception as e:
            logger.error(f"Upload error: {e}")
            return False

    async def send_heartbeat(self):
        try:
            url = f"{self.config['portal_url']}/api/pod/heartbeat"
            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            public_ip = self.config.get('public_ip', 'auto')
            if public_ip == 'auto':
                try:
                    public_ip = requests.get('https://api.ipify.org', timeout=3).text
                except:
                    public_ip = 'unknown'

            stream_port = self.config.get('stream_port', 8000)
            stream_url = f"https://{public_ip}:{stream_port}/stream"

            payload = {
                'pod_id': self.config['pod_id'],
                'camera_id': self.config['camera_id'],
                'stream_url': stream_url,
                'status': 'online'
            }

            response = requests.post(url, headers=headers, json=payload, timeout=5)

            if response.status_code == 200:
                logger.debug("Heartbeat sent")
                return True
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Heartbeat error: {e}")
            return False

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("Connected to MQTT broker")
            topic = self.config.get('mqtt_topic', 'frigate/events')
            client.subscribe(topic)
            logger.info(f"Subscribed to: {topic}")
        else:
            logger.error(f"MQTT connection failed: {rc}")

    def on_mqtt_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())

            if payload.get('type') == 'new' and 'after' in payload:
                event = payload['after']
                label = event.get('label', '')

                if label.lower() == 'license_plate':
                    plate = event.get('sub_label', '')
                    confidence = event.get('score', 0.0)

                    min_confidence = self.config.get('min_confidence', 0.7)

                    if plate and confidence >= min_confidence:
                        logger.info(f"Plate detected: {plate} ({confidence:.2%})")

                        asyncio.run(self.send_detection(plate, confidence))

                        if self.config.get('record_on_detection', True):
                            logger.info("Recording clip...")
                            clip_path = self.record_clip(duration=30)
                            if clip_path:
                                asyncio.run(self.upload_recording(clip_path, plate))

        except Exception as e:
            logger.error(f"MQTT message error: {e}")

    async def run(self):
        logger.info("=" * 60)
        logger.info("PlateBridge Complete Pod Agent")
        logger.info("=" * 60)
        logger.info(f"Portal: {self.config['portal_url']}")
        logger.info(f"Pod ID: {self.config['pod_id']}")
        logger.info(f"Camera ID: {self.config['camera_id']}")
        logger.info("=" * 60)

        await self.refresh_whitelist()

        if self.config.get('enable_streaming', True):
            self.start_ffmpeg_stream()
            threading.Thread(target=self.run_stream_server, daemon=True).start()

        if self.config.get('enable_mqtt', True):
            mqtt_host = self.config.get('mqtt_host', 'localhost')
            mqtt_port = self.config.get('mqtt_port', 1883)

            self.mqtt_client = mqtt.Client()
            self.mqtt_client.on_connect = self.on_mqtt_connect
            self.mqtt_client.on_message = self.on_mqtt_message

            logger.info(f"Connecting to MQTT: {mqtt_host}:{mqtt_port}")
            self.mqtt_client.connect(mqtt_host, mqtt_port, 60)
            self.mqtt_client.loop_start()

        refresh_interval = self.config.get('whitelist_refresh_interval', 300)
        heartbeat_interval = self.config.get('heartbeat_interval', 60)

        last_heartbeat = 0
        last_refresh = 0

        try:
            while True:
                current_time = time.time()

                if current_time - last_heartbeat >= heartbeat_interval:
                    await self.send_heartbeat()
                    last_heartbeat = current_time

                if current_time - last_refresh >= refresh_interval:
                    await self.refresh_whitelist()
                    last_refresh = current_time

                await asyncio.sleep(1)

        except KeyboardInterrupt:
            logger.info("Shutting down...")
            if self.mqtt_client:
                self.mqtt_client.loop_stop()
                self.mqtt_client.disconnect()
            if self.ffmpeg_process:
                self.ffmpeg_process.terminate()
            logger.info("Agent stopped")

    def run_stream_server(self):
        @app.route('/stream')
        def stream():
            token = request.args.get('token')

            if not token:
                return jsonify({'error': 'Missing token'}), 401

            if not self.validate_stream_token(token):
                return jsonify({'error': 'Invalid token'}), 403

            playlist_path = os.path.join(self.hls_output_dir, 'stream.m3u8')

            if not os.path.exists(playlist_path):
                return jsonify({'error': 'Stream not ready'}), 503

            return send_file(playlist_path, mimetype='application/vnd.apple.mpegurl')

        @app.route('/stream/segment/<filename>')
        def stream_segment(filename):
            segment_path = os.path.join(self.hls_output_dir, filename)

            if not os.path.exists(segment_path):
                return jsonify({'error': 'Segment not found'}), 404

            return send_file(segment_path, mimetype='video/MP2T')

        @app.route('/health')
        def health():
            return jsonify({
                'status': 'ok',
                'pod_id': self.config['pod_id'],
                'streaming': self.ffmpeg_process and self.ffmpeg_process.poll() is None
            })

        stream_port = self.config.get('stream_port', 8000)
        logger.info(f"Starting stream server on port {stream_port}")
        app.run(host='0.0.0.0', port=stream_port, threaded=True)


def main():
    global agent

    config_path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"
    agent = CompletePodAgent(config_path)

    try:
        asyncio.run(agent.run())
    except KeyboardInterrupt:
        logger.info("Stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
