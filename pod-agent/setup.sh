#!/bin/bash

set -e

echo "======================================"
echo "PlateBridge Pod Agent Setup"
echo "======================================"
echo ""

INSTALL_DIR="$HOME/platebridge-agent"
SERVICE_NAME="platebridge-agent"

check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        echo "✓ Python 3 found: $(python3 --version)"
    else
        echo "✗ Python 3 is not installed"
        echo "Please install Python 3: sudo apt-get install python3 python3-pip"
        exit 1
    fi
}

check_pip() {
    if command -v pip3 &> /dev/null; then
        echo "✓ pip3 found"
    else
        echo "✗ pip3 is not installed"
        echo "Please install pip: sudo apt-get install python3-pip"
        exit 1
    fi
}

install_agent() {
    echo ""
    echo "Installing PlateBridge Agent to $INSTALL_DIR..."

    mkdir -p "$INSTALL_DIR"

    cp agent.py "$INSTALL_DIR/"
    cp requirements.txt "$INSTALL_DIR/"
    cp config.example.yaml "$INSTALL_DIR/"

    chmod +x "$INSTALL_DIR/agent.py"

    cd "$INSTALL_DIR"
    echo "Installing Python dependencies..."
    pip3 install -r requirements.txt

    echo "✓ Agent files installed"
}

configure_agent() {
    echo ""
    echo "======================================"
    echo "Agent Configuration"
    echo "======================================"
    echo ""

    if [ -f "$INSTALL_DIR/config.yaml" ]; then
        echo "⚠ config.yaml already exists"
        read -p "Overwrite existing configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping configuration. Edit $INSTALL_DIR/config.yaml manually."
            return
        fi
    fi

    echo "Please provide the following information:"
    echo ""

    read -p "Portal URL (e.g., https://your-portal.vercel.app): " PORTAL_URL
    read -p "API Key (from your portal): " API_KEY
    read -p "Site ID (from your portal): " SITE_ID
    read -p "Pod ID (e.g., front-gate, back-gate): " POD_ID

    echo ""
    echo "Frigate MQTT Configuration (press Enter for defaults):"
    read -p "MQTT Host [localhost]: " MQTT_HOST
    MQTT_HOST=${MQTT_HOST:-localhost}

    read -p "MQTT Port [1883]: " MQTT_PORT
    MQTT_PORT=${MQTT_PORT:-1883}

    read -p "MQTT Username (optional): " MQTT_USER
    read -s -p "MQTT Password (optional): " MQTT_PASS
    echo ""

    cat > "$INSTALL_DIR/config.yaml" << EOF
portal_url: "$PORTAL_URL"
api_key: "$API_KEY"

site_id: "$SITE_ID"
pod_id: "$POD_ID"

frigate_mqtt_host: "$MQTT_HOST"
frigate_mqtt_port: $MQTT_PORT
frigate_mqtt_username: "$MQTT_USER"
frigate_mqtt_password: "$MQTT_PASS"
frigate_mqtt_topic: "frigate/events"

min_confidence: 0.7
whitelist_refresh_interval: 300

log_level: "INFO"
EOF

    echo ""
    echo "✓ Configuration saved to $INSTALL_DIR/config.yaml"
}

create_systemd_service() {
    echo ""
    echo "======================================"
    echo "Creating systemd service"
    echo "======================================"
    echo ""

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

    echo "✓ Systemd service created"
    echo ""
    echo "To start the agent automatically:"
    echo "  sudo systemctl enable $SERVICE_NAME"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo ""
    echo "To check status:"
    echo "  sudo systemctl status $SERVICE_NAME"
    echo ""
    echo "To view logs:"
    echo "  sudo journalctl -u $SERVICE_NAME -f"
}

test_agent() {
    echo ""
    read -p "Test the agent now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Starting agent in test mode (Ctrl+C to stop)..."
        echo ""
        cd "$INSTALL_DIR"
        $PYTHON_CMD agent.py config.yaml
    fi
}

main() {
    check_python
    check_pip
    install_agent
    configure_agent
    create_systemd_service

    echo ""
    echo "======================================"
    echo "✓ Installation Complete!"
    echo "======================================"
    echo ""
    echo "Next steps:"
    echo "1. Review your config: $INSTALL_DIR/config.yaml"
    echo "2. Start the service: sudo systemctl start $SERVICE_NAME"
    echo "3. Enable auto-start: sudo systemctl enable $SERVICE_NAME"
    echo "4. Check logs: sudo journalctl -u $SERVICE_NAME -f"
    echo ""

    test_agent
}

main
