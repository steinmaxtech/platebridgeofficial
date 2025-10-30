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
import psutil

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
        self.community_id = None
        self.whitelist_cache = {}
        self.cache_path = Path("whitelist_cache.json")
        self.last_whitelist_refresh = None
        self.mqtt_client = None
        self.ffmpeg_process = None
        self.hls_output_dir = '/tmp/hls_output'

        os.makedirs(self.hls_output_dir, exist_ok=True)
        os.makedirs(self.config.get('recordings_dir', '/tmp/recordings'), exist_ok=True)

        self.load_whitelist_cache()

    def get_system_stats(self) -> Dict[str, Any]:
        """Collect CPU, memory, disk, and temperature information"""
        try:
            stats = {
                'cpu_usage': psutil.cpu_percent(interval=1),
                'memory_usage': psutil.virtual_memory().percent,
                'disk_usage': psutil.disk_usage('/').percent,
                'temperature': None
            }

            # Try to get temperature from sensors
            try:
                if hasattr(psutil, 'sensors_temperatures'):
                    temps = psutil.sensors_temperatures()
                    if temps:
                        # Try common sensor names
                        for sensor_name in ['coretemp', 'cpu_thermal', 'k10temp']:
                            if sensor_name in temps:
                                sensor_temps = temps[sensor_name]
                                if sensor_temps:
                                    stats['temperature'] = sensor_temps[0].current
                                    break

                        # If no common sensor found, use first available
                        if stats['temperature'] is None:
                            first_sensor = next(iter(temps.values()), None)
                            if first_sensor:
                                stats['temperature'] = first_sensor[0].current
            except Exception as e:
                logger.debug(f"Could not read temperature: {e}")

            # Fallback: try reading from thermal zone files
            if stats['temperature'] is None:
                try:
                    thermal_paths = [
                        '/sys/class/thermal/thermal_zone0/temp',
                        '/sys/class/thermal/thermal_zone1/temp'
                    ]
                    for path in thermal_paths:
                        if os.path.exists(path):
                            with open(path, 'r') as f:
                                temp = int(f.read().strip())
                                # Convert from millidegrees to degrees
                                stats['temperature'] = temp / 1000.0
                                break
                except Exception as e:
                    logger.debug(f"Could not read thermal zone: {e}")

            return stats
        except Exception as e:
            logger.error(f"Error getting system stats: {e}")
            return {
                'cpu_usage': None,
                'memory_usage': None,
                'disk_usage': None,
                'temperature': None
            }

    def load_config(self) -> Dict[str, Any]:
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            required_fields = ['portal_url', 'pod_api_key', 'pod_id', 'camera_id']
            missing = [f for f in required_fields if f not in config]
            if missing:
                raise ValueError(f"Missing required config fields: {', '.join(missing)}")

            # Store community_id if provided in config (optional now)
            if 'community_id' in config:
                self.community_id = config['community_id']

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
            if not self.community_id:
                logger.warning("No community_id available yet, skipping whitelist refresh")
                return False

            url = f"{self.config['portal_url']}/api/access/list/{self.community_id}"
            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            logger.info("Fetching whitelist from portal...")
            response = requests.get(url, headers=headers, timeout=10)

            if response.status_code == 200:
                data = response.json()
                access_list = data.get('access_list', [])

                self.whitelist_cache = {
                    entry['license_plate']: entry
                    for entry in access_list
                    if entry.get('is_active', True)
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

    async def register_recording(self, file_path: str, plate_number: Optional[str] = None, snapshot_path: Optional[str] = None):
        try:
            filename = os.path.basename(file_path)
            camera_id = self.config['camera_id']
            file_size = os.path.getsize(file_path)

            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            logger.info(f"Registering recording in portal: {filename}")

            payload = {
                'camera_id': camera_id,
                'file_path': file_path,
                'file_size_bytes': file_size,
                'duration_seconds': 30,
                'event_type': 'plate_detection' if plate_number else 'manual',
                'plate_number': plate_number
            }

            if snapshot_path:
                payload['thumbnail_path'] = snapshot_path

            response = requests.post(
                f"{self.config['portal_url']}/api/pod/recordings",
                headers=headers,
                json=payload
            )

            if response.status_code == 200:
                logger.info("Recording registered successfully")
                return True
            else:
                logger.error(f"Failed to register recording: {response.text}")
                return False

        except Exception as e:
            logger.error(f"Registration error: {e}")
            return False

    def list_local_recordings(self):
        recordings_dir = self.config.get('recordings_dir', '/tmp/recordings')
        recordings = []

        if os.path.exists(recordings_dir):
            for filename in os.listdir(recordings_dir):
                if filename.endswith('.mp4'):
                    file_path = os.path.join(recordings_dir, filename)
                    stat = os.stat(file_path)
                    recordings.append({
                        'filename': filename,
                        'path': file_path,
                        'size': stat.st_size,
                        'created': datetime.fromtimestamp(stat.st_ctime).isoformat()
                    })

        return recordings

    async def send_heartbeat(self):
        try:
            url = f"{self.config['portal_url']}/api/pod/heartbeat"
            headers = {
                'Authorization': f"Bearer {self.config['pod_api_key']}",
                'Content-Type': 'application/json'
            }

            # Try to get Tailscale IP first, fall back to public IP
            tailscale_ip = None
            tailscale_hostname = None
            public_ip = self.config.get('public_ip', 'auto')

            # Try Tailscale first
            tailscale_funnel_url = None
            try:
                result = subprocess.run(['tailscale', 'ip', '-4'],
                                      capture_output=True, text=True, timeout=2)
                if result.returncode == 0 and result.stdout.strip():
                    tailscale_ip = result.stdout.strip()
                    logger.info(f"Tailscale IP detected: {tailscale_ip}")

                    # Get Tailscale hostname and check for funnel
                    try:
                        hostname_result = subprocess.run(['tailscale', 'status', '--json'],
                                                       capture_output=True, text=True, timeout=2)
                        if hostname_result.returncode == 0:
                            import json
                            status_data = json.loads(hostname_result.stdout)
                            tailscale_hostname = status_data.get('Self', {}).get('HostName', '')

                            # Build Tailscale Funnel URL
                            tailnet = status_data.get('CurrentTailnet', {}).get('Name', '')
                            if tailscale_hostname and tailnet:
                                tailscale_funnel_url = f"https://{tailscale_hostname}.{tailnet}.ts.net"
                                logger.info(f"Tailscale Funnel URL: {tailscale_funnel_url}")
                    except:
                        pass
            except Exception as e:
                logger.debug(f"Tailscale not available: {e}")

            # Get public IP if auto
            if public_ip == 'auto':
                try:
                    if tailscale_ip:
                        public_ip = tailscale_ip
                    else:
                        public_ip = requests.get('https://api.ipify.org', timeout=3).text
                except:
                    public_ip = 'unknown'

            stream_port = self.config.get('stream_port', 8000)
            stream_url = f"https://{tailscale_ip or public_ip}:{stream_port}/stream"

            cameras = []
            if self.config.get('camera_id') and self.config.get('camera_name'):
                cameras.append({
                    'camera_id': self.config['camera_id'],
                    'name': self.config['camera_name'],
                    'rtsp_url': self.config.get('camera_rtsp_url', ''),
                    'position': self.config.get('camera_position', 'main entrance')
                })

            # Get system stats
            sys_stats = self.get_system_stats()

            payload = {
                'pod_id': self.config['pod_id'],
                'ip_address': public_ip,
                'firmware_version': '1.0.0',
                'status': 'online',
                'cameras': cameras,
                'cpu_usage': sys_stats['cpu_usage'],
                'memory_usage': sys_stats['memory_usage'],
                'disk_usage': sys_stats['disk_usage'],
                'temperature': sys_stats['temperature']
            }

            # Add Tailscale info if available
            if tailscale_ip:
                payload['tailscale_ip'] = tailscale_ip
            if tailscale_hostname:
                payload['tailscale_hostname'] = tailscale_hostname
            if tailscale_funnel_url:
                payload['tailscale_funnel_url'] = tailscale_funnel_url

            response = requests.post(url, headers=headers, json=payload, timeout=5)

            if response.status_code == 200:
                result = response.json()

                # Store community_id from response if not already set
                if not self.community_id and 'community_id' in result:
                    self.community_id = result['community_id']
                    logger.info(f"Community ID obtained: {self.community_id}")

                logger.debug("Heartbeat sent")
                return True
            else:
                logger.warning(f"Heartbeat failed: {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Heartbeat error: {e}")
            return False

    def get_frigate_snapshot(self, event_id: str) -> Optional[str]:
        try:
            frigate_url = self.config.get('frigate_url', 'http://localhost:5000')
            snapshot_url = f"{frigate_url}/api/events/{event_id}/snapshot.jpg"

            response = requests.get(snapshot_url, timeout=10)

            if response.status_code == 200:
                recordings_dir = self.config.get('recordings_dir', '/tmp/recordings')
                snapshot_path = os.path.join(recordings_dir, f'{event_id}_snapshot.jpg')

                with open(snapshot_path, 'wb') as f:
                    f.write(response.content)

                logger.info(f"Saved snapshot: {snapshot_path}")
                return snapshot_path
            else:
                logger.warning(f"Failed to get snapshot: HTTP {response.status_code}")
                return None

        except Exception as e:
            logger.error(f"Snapshot retrieval error: {e}")
            return None

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("Connected to Frigate MQTT broker")
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
                event_id = event.get('id', '')
                label = event.get('label', '')
                camera = event.get('camera', 'unknown')

                if label.lower() == 'license_plate':
                    plate = event.get('sub_label', '')
                    confidence = event.get('score', 0.0)

                    min_confidence = self.config.get('min_confidence', 0.7)

                    if plate and confidence >= min_confidence:
                        logger.info(f"[{camera}] Plate detected: {plate} ({confidence:.2%})")

                        snapshot_path = None
                        if self.config.get('save_snapshots', True) and event_id:
                            snapshot_path = self.get_frigate_snapshot(event_id)

                        asyncio.run(self.send_detection(plate, confidence))

                        if self.config.get('record_on_detection', True):
                            logger.info("Recording clip...")
                            clip_path = self.record_clip(duration=30)
                            if clip_path:
                                asyncio.run(self.register_recording(
                                    clip_path,
                                    plate,
                                    snapshot_path=snapshot_path
                                ))

            elif payload.get('type') == 'end' and 'before' in payload:
                event = payload['before']
                logger.debug(f"Event ended: {event.get('id')}")

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

        @app.route('/recordings/list')
        def list_recordings():
            token = request.args.get('token')

            if not token or not self.validate_stream_token(token):
                return jsonify({'error': 'Invalid token'}), 403

            recordings = self.list_local_recordings()
            return jsonify({'recordings': recordings})

        @app.route('/recording/<recording_id>')
        def get_recording(recording_id):
            token = request.args.get('token')

            if not token or not self.validate_stream_token(token):
                return jsonify({'error': 'Invalid token'}), 403

            recordings_dir = self.config.get('recordings_dir', '/tmp/recordings')

            for filename in os.listdir(recordings_dir):
                if filename.endswith('.mp4'):
                    file_path = os.path.join(recordings_dir, filename)
                    if recording_id in filename or os.path.basename(file_path) == recording_id:
                        if os.path.exists(file_path):
                            return send_file(file_path, mimetype='video/mp4')

            return jsonify({'error': 'Recording not found'}), 404

        @app.route('/thumbnail/<recording_id>')
        def get_thumbnail(recording_id):
            token = request.args.get('token')

            if not token or not self.validate_stream_token(token):
                return jsonify({'error': 'Invalid token'}), 403

            recordings_dir = self.config.get('recordings_dir', '/tmp/recordings')
            thumbnail_path = os.path.join(recordings_dir, f'{recording_id}_thumb.jpg')

            if os.path.exists(thumbnail_path):
                return send_file(thumbnail_path, mimetype='image/jpeg')

            return jsonify({'error': 'Thumbnail not found'}), 404

        @app.route('/health')
        def health():
            recordings = self.list_local_recordings()
            return jsonify({
                'status': 'ok',
                'pod_id': self.config['pod_id'],
                'streaming': self.ffmpeg_process and self.ffmpeg_process.poll() is None,
                'recording_count': len(recordings)
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
