#!/bin/bash

set -e

INSTALL_DIR="$HOME/platebridge-agent"
SERVICE_NAME="platebridge-agent"
PORTAL_URL="https://platebridgeofficial.vercel.app"
REPO_URL="https://raw.githubusercontent.com/platebridge/pod-agent/main"
API_KEY="$1"

echo "======================================"
echo "PlateBridge Pod Agent Installer"
echo "======================================"
echo ""

if [ -z "$API_KEY" ]; then
    echo "✗ Error: No API key provided"
    echo ""
    echo "Usage: curl -fsSL https://platebridgeofficial.vercel.app/install-pod.sh | bash -s -- \"YOUR_API_KEY\""
    exit 1
fi

echo "✓ API key received"
echo "✓ Portal: $PORTAL_URL"
echo ""

check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        echo "✓ Python 3 found: $(python3 --version)"
    else
        echo "✗ Python 3 is not installed"
        echo ""
        echo "Installing Python 3..."
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip
        PYTHON_CMD="python3"
    fi
}

check_pip() {
    if command -v pip3 &> /dev/null; then
        echo "✓ pip3 found"
    else
        echo "Installing pip3..."
        sudo apt-get install -y python3-pip
    fi
}

fetch_pod_info() {
    echo ""
    echo "Fetching POD configuration from portal..."

    local response=$(curl -s -H "Authorization: Bearer $API_KEY" \
        "${PORTAL_URL}/api/pod/info" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "✗ Failed to fetch POD info from portal"
        return 1
    fi

    COMMUNITY_ID=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('community_id', ''))" 2>/dev/null || echo "")
    POD_ID=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('pod_id', ''))" 2>/dev/null || echo "")
    POD_NAME=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', ''))" 2>/dev/null || echo "")
    COMMUNITY_NAME=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('community_name', ''))" 2>/dev/null || echo "")

    if [ -z "$COMMUNITY_ID" ] || [ -z "$POD_ID" ]; then
        echo "✗ Invalid API key or POD not found"
        return 1
    fi

    echo "✓ POD Info:"
    echo "  Name: $POD_NAME"
    echo "  POD ID: $POD_ID"
    echo "  Community: $COMMUNITY_NAME"
    return 0
}


download_agent_files() {
    echo ""
    echo "Downloading agent files..."

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    cat > agent.py << 'AGENT_EOF'
#!/usr/bin/env python3
import json
import time
import asyncio
import logging
import os
import sys
from datetime import datetime
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
        self.mqtt_client = None

    def load_config(self) -> Dict[str, Any]:
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            sys.exit(1)

    async def send_detection(self, plate: str, confidence: float, camera: str = "unknown"):
        try:
            url = f"{self.config['portal_url']}/api/pod/detect"
            headers = {
                'Authorization': f"Bearer {self.config['api_key']}",
                'Content-Type': 'application/json'
            }
            payload = {
                'community_id': self.config.get('community_id', ''),
                'plate': plate,
                'camera': camera,
                'pod_name': self.config['pod_id']
            }

            response = requests.post(url, headers=headers, json=payload, timeout=10)

            if response.status_code == 200:
                result = response.json()
                action = result.get('action', 'deny')
                gate_opened = result.get('gate_opened', False)

                if action == 'allow' and gate_opened:
                    logger.info(f"✓ GATE OPENED for plate: {plate}")
                elif action == 'allow':
                    logger.info(f"✓ Plate authorized: {plate}")
                else:
                    logger.info(f"✗ Access denied for plate: {plate}")
                return True
            else:
                logger.error(f"Detection failed: HTTP {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"Error sending detection: {e}")
            return False

    def on_mqtt_connect(self, client, userdata, flags, rc):
        if rc == 0:
            logger.info("Connected to Frigate MQTT")
            topic = self.config.get('frigate_mqtt_topic', 'frigate/events')
            client.subscribe(topic)
            logger.info(f"Subscribed to: {topic}")
        else:
            logger.error(f"MQTT connection failed: {rc}")

    def on_mqtt_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
            if payload.get('type') == 'new' and 'after' in payload:
                event = payload['after']
                if event.get('label', '').lower() == 'license_plate':
                    plate = event.get('sub_label', '')
                    confidence = event.get('score', 0.0)
                    camera = event.get('camera', 'unknown')

                    if plate and confidence >= self.config.get('min_confidence', 0.7):
                        logger.info(f"Plate detected: {plate} ({confidence:.0%}) on {camera}")
                        asyncio.run(self.send_detection(plate, confidence, camera))
        except Exception as e:
            logger.error(f"Error processing MQTT message: {e}")

    def start_mqtt_listener(self):
        try:
            mqtt_host = self.config.get('frigate_mqtt_host', 'localhost')
            mqtt_port = self.config.get('frigate_mqtt_port', 1883)

            self.mqtt_client = mqtt.Client()
            self.mqtt_client.on_connect = self.on_mqtt_connect
            self.mqtt_client.on_message = self.on_mqtt_message

            if self.config.get('frigate_mqtt_username'):
                self.mqtt_client.username_pw_set(
                    self.config['frigate_mqtt_username'],
                    self.config.get('frigate_mqtt_password', '')
                )

            logger.info(f"Connecting to MQTT at {mqtt_host}:{mqtt_port}")
            self.mqtt_client.connect(mqtt_host, mqtt_port, 60)
            return self.mqtt_client
        except Exception as e:
            logger.error(f"MQTT connection error: {e}")
            return None

    async def send_heartbeat(self):
        try:
            url = f"{self.config['portal_url']}/api/pod/heartbeat"
            headers = {
                'Authorization': f"Bearer {self.config['api_key']}",
                'Content-Type': 'application/json'
            }

            cameras = []
            if self.config.get('cameras'):
                for cam in self.config['cameras']:
                    cameras.append({
                        'camera_id': cam.get('id', cam.get('name', 'default')),
                        'name': cam.get('name', 'Camera'),
                        'rtsp_url': cam.get('rtsp_url', ''),
                        'position': cam.get('position', 'entrance')
                    })

            payload = {
                'pod_id': self.config['pod_id'],
                'firmware_version': '1.0.0',
                'status': 'online',
                'cameras': cameras
            }

            requests.post(url, headers=headers, json=payload, timeout=5)
        except Exception as e:
            logger.error(f"Heartbeat failed: {e}")

    async def run(self):
        logger.info("=" * 60)
        logger.info("PlateBridge Pod Agent Starting")
        logger.info(f"Portal: {self.config['portal_url']}")
        logger.info(f"Community: {self.config.get('community_id', 'N/A')}")
        logger.info(f"POD: {self.config['pod_id']}")
        logger.info("=" * 60)

        mqtt_client = self.start_mqtt_listener()
        if not mqtt_client:
            logger.error("Failed to start MQTT listener")
            return

        mqtt_client.loop_start()

        try:
            while True:
                await self.send_heartbeat()
                await asyncio.sleep(60)
        except KeyboardInterrupt:
            logger.info("Shutting down...")
            mqtt_client.loop_stop()
            mqtt_client.disconnect()

def main():
    agent = PlateBridgeAgent()
    try:
        asyncio.run(agent.run())
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
AGENT_EOF

    cat > requirements.txt << 'REQ_EOF'
paho-mqtt>=1.6.1
requests>=2.31.0
pyyaml>=6.0
REQ_EOF

    chmod +x agent.py
    echo "✓ Agent files created"
}

configure_frigate() {
    echo ""
    echo "======================================"
    echo "Frigate Configuration"
    echo "======================================"
    echo ""
    echo "Enter your Frigate MQTT connection details"
    echo "(Press Enter to use defaults)"
    echo ""

    read -p "MQTT Host [localhost]: " MQTT_HOST
    MQTT_HOST=${MQTT_HOST:-localhost}

    read -p "MQTT Port [1883]: " MQTT_PORT
    MQTT_PORT=${MQTT_PORT:-1883}

    read -p "MQTT Username (optional): " MQTT_USER
    if [ -n "$MQTT_USER" ]; then
        read -s -p "MQTT Password: " MQTT_PASS
        echo ""
    else
        MQTT_PASS=""
    fi

    echo ""
    echo "======================================"
    echo "Camera Configuration"
    echo "======================================"
    echo ""
    read -p "Camera Name [Front Gate]: " CAMERA_NAME
    CAMERA_NAME=${CAMERA_NAME:-Front Gate}

    read -p "Camera RTSP URL (e.g., rtsp://192.168.1.100:554/stream): " CAMERA_RTSP
    CAMERA_RTSP=${CAMERA_RTSP:-}

    read -p "Camera Position [entrance]: " CAMERA_POSITION
    CAMERA_POSITION=${CAMERA_POSITION:-entrance}

    CAMERA_ID=$(echo -n "${CAMERA_NAME}${CAMERA_RTSP}" | md5sum | cut -d' ' -f1 | head -c 8)
}

create_config() {
    echo ""
    echo "Creating configuration file..."

    cat > "$INSTALL_DIR/config.yaml" << EOF
# PlateBridge Pod Configuration
# Auto-generated on $(date)

portal_url: "$PORTAL_URL"
api_key: "$API_KEY"
community_id: "$COMMUNITY_ID"
pod_id: "$POD_ID"

frigate_mqtt_host: "$MQTT_HOST"
frigate_mqtt_port: $MQTT_PORT
frigate_mqtt_username: "$MQTT_USER"
frigate_mqtt_password: "$MQTT_PASS"
frigate_mqtt_topic: "frigate/events"

min_confidence: 0.7
log_level: "INFO"

cameras:
  - id: "$CAMERA_ID"
    name: "$CAMERA_NAME"
    rtsp_url: "$CAMERA_RTSP"
    position: "$CAMERA_POSITION"
EOF

    echo "✓ Configuration saved"
}

install_dependencies() {
    echo ""
    echo "Installing Python dependencies..."
    cd "$INSTALL_DIR"
    sudo PIP_BREAK_SYSTEM_PACKAGES=1 pip3 install -r requirements.txt -q
    echo "✓ Dependencies installed"
}

create_systemd_service() {
    echo ""
    echo "Creating systemd service..."

    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=PlateBridge Pod Agent
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_CMD $INSTALL_DIR/agent.py $INSTALL_DIR/config.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME

    echo "✓ Service created and started"
}

main() {
    check_python
    check_pip

    if ! fetch_pod_info; then
        echo ""
        echo "✗ Failed to configure POD"
        echo "Please check your API key and try again"
        exit 1
    fi

    download_agent_files
    configure_frigate
    create_config
    install_dependencies
    create_systemd_service

    echo ""
    echo "======================================"
    echo "✓ Installation Complete!"
    echo "======================================"
    echo ""
    echo "POD Status:"
    sudo systemctl status $SERVICE_NAME --no-pager | head -n 10
    echo ""
    echo "Useful commands:"
    echo "  View logs:   sudo journalctl -u $SERVICE_NAME -f"
    echo "  Stop POD:    sudo systemctl stop $SERVICE_NAME"
    echo "  Start POD:   sudo systemctl start $SERVICE_NAME"
    echo "  Restart POD: sudo systemctl restart $SERVICE_NAME"
    echo ""
}

main
