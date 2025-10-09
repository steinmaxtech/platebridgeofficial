#!/usr/bin/env python3
"""
PlateBridge Pod Agent
Connects Frigate license plate detections to the PlateBridge portal
"""

import json
import time
import asyncio
import logging
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional, Dict, Any
import yaml
import requests
import paho.mqtt.client as mqtt

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('platebridge-agent')


class PlateBridgeAgent:
    def __init__(self, config_path: str = "config.yaml"):
        self.config_path = config_path
        self.config = self.load_config()
        self.whitelist_cache = {}
        self.cache_path = Path("whitelist_cache.json")
        self.last_whitelist_refresh = None
        self.mqtt_client = None

        self.load_whitelist_cache()

    def load_config(self) -> Dict[str, Any]:
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)

            required_fields = ['portal_url', 'api_key', 'site_id', 'pod_id']
            missing = [f for f in required_fields if f not in config]
            if missing:
                raise ValueError(f"Missing required config fields: {', '.join(missing)}")

            return config
        except FileNotFoundError:
            logger.error(f"Config file not found: {self.config_path}")
            logger.error("Please run setup.sh first to create your configuration")
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
                        item['license_plate']: item
                        for item in cache_data.get('plates', [])
                    }
                    self.last_whitelist_refresh = cache_data.get('last_updated')
                logger.info(f"Loaded {len(self.whitelist_cache)} plates from cache")
            except Exception as e:
                logger.error(f"Error loading whitelist cache: {e}")
                self.whitelist_cache = {}

    def save_whitelist_cache(self):
        try:
            cache_data = {
                'last_updated': datetime.now().isoformat(),
                'plates': list(self.whitelist_cache.values())
            }
            with open(self.cache_path, 'w') as f:
                json.dump(cache_data, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving whitelist cache: {e}")

    async def refresh_whitelist(self) -> bool:
        try:
            url = f"{self.config['portal_url']}/api/plates"
            headers = {
                'Authorization': f"Bearer {self.config['api_key']}",
                'Content-Type': 'application/json'
            }
            params = {'site_id': self.config['site_id']}

            logger.info("Fetching whitelist from portal...")
            response = requests.get(url, headers=headers, params=params, timeout=10)

            if response.status_code == 200:
                data = response.json()
                plates = data.get('plates', [])

                self.whitelist_cache = {
                    plate['license_plate']: plate
                    for plate in plates
                }
                self.last_whitelist_refresh = datetime.now().isoformat()
                self.save_whitelist_cache()

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

    async def send_detection(self, plate: str, confidence: float, image_path: Optional[str] = None) -> bool:
        try:
            url = f"{self.config['portal_url']}/api/pod/detect"
            headers = {
                'Authorization': f"Bearer {self.config['api_key']}",
                'Content-Type': 'application/json'
            }

            payload = {
                'pod_id': self.config['pod_id'],
                'site_id': self.config['site_id'],
                'license_plate': plate,
                'confidence': confidence,
                'timestamp': datetime.now().isoformat(),
                'image_path': image_path
            }

            logger.info(f"Sending detection to portal: {plate} ({confidence:.2%})")
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

                return True
            else:
                logger.error(f"Failed to send detection: HTTP {response.status_code}")
                logger.error(f"Response: {response.text}")
                return False

        except Exception as e:
            logger.error(f"Error sending detection: {e}")
            return False

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("Connected to Frigate MQTT broker")
            topic = f"{self.config.get('frigate_mqtt_topic', 'frigate/events')}"
            client.subscribe(topic)
            logger.info(f"Subscribed to topic: {topic}")
        else:
            logger.error(f"Failed to connect to MQTT broker: {rc}")

    def on_mqtt_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())

            if payload.get('type') == 'new' and 'after' in payload:
                event = payload['after']
                label = event.get('label', '')

                if label.lower() == 'license_plate':
                    plate = event.get('sub_label', '')
                    confidence = event.get('score', 0.0)
                    snapshot_path = event.get('snapshot', {}).get('path', '')

                    if plate and confidence >= self.config.get('min_confidence', 0.7):
                        logger.info(f"License plate detected: {plate} ({confidence:.2%})")

                        asyncio.run(self.send_detection(plate, confidence, snapshot_path))

        except Exception as e:
            logger.error(f"Error processing MQTT message: {e}")

    def on_mqtt_disconnect(self, client, userdata, rc):
        logger.warning(f"Disconnected from MQTT broker: {rc}")
        if rc != 0:
            logger.info("Attempting to reconnect...")

    def start_mqtt_listener(self):
        try:
            mqtt_host = self.config.get('frigate_mqtt_host', 'localhost')
            mqtt_port = self.config.get('frigate_mqtt_port', 1883)

            self.mqtt_client = mqtt.Client()
            self.mqtt_client.on_connect = self.on_mqtt_connect
            self.mqtt_client.on_message = self.on_mqtt_message
            self.mqtt_client.on_disconnect = self.on_mqtt_disconnect

            if self.config.get('frigate_mqtt_username'):
                self.mqtt_client.username_pw_set(
                    self.config['frigate_mqtt_username'],
                    self.config.get('frigate_mqtt_password', '')
                )

            logger.info(f"Connecting to Frigate MQTT at {mqtt_host}:{mqtt_port}")
            self.mqtt_client.connect(mqtt_host, mqtt_port, 60)

            return self.mqtt_client

        except Exception as e:
            logger.error(f"Error starting MQTT listener: {e}")
            return None

    async def send_heartbeat(self) -> bool:
        try:
            url = f"{self.config['portal_url']}/api/pod/heartbeat"
            headers = {
                'Authorization': f"Bearer {self.config['api_key']}",
                'Content-Type': 'application/json'
            }

            logger.debug("Sending heartbeat to portal...")
            response = requests.post(url, headers=headers, timeout=5)

            if response.status_code == 200:
                logger.debug("Heartbeat sent successfully")
                return True
            else:
                logger.warning(f"Failed to send heartbeat: HTTP {response.status_code}")
                return False

        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
            return False

    async def run(self):
        logger.info("=" * 60)
        logger.info("PlateBridge Pod Agent Starting")
        logger.info("=" * 60)
        logger.info(f"Portal URL: {self.config['portal_url']}")
        logger.info(f"Site ID: {self.config['site_id']}")
        logger.info(f"Pod ID: {self.config['pod_id']}")
        logger.info("=" * 60)

        await self.refresh_whitelist()

        mqtt_client = self.start_mqtt_listener()
        if not mqtt_client:
            logger.error("Failed to start MQTT listener")
            return

        mqtt_client.loop_start()

        refresh_interval = self.config.get('whitelist_refresh_interval', 300)
        heartbeat_interval = self.config.get('heartbeat_interval', 30)

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
            logger.info("\nShutting down gracefully...")
            mqtt_client.loop_stop()
            mqtt_client.disconnect()
            logger.info("Agent stopped")


def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"

    agent = PlateBridgeAgent(config_path)

    try:
        asyncio.run(agent.run())
    except KeyboardInterrupt:
        logger.info("\nAgent stopped by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
