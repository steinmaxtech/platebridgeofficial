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

validate_url() {
    local url=$1
    if [[ ! $url =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_not_empty() {
    local value=$1
    if [ -z "$value" ]; then
        return 1
    fi
    return 0
}

test_portal_connection() {
    local portal_url=$1
    local api_key=$2

    echo ""
    echo "Testing connection to portal..."

    local health_url="${portal_url}/api/gatewise/health"
    local response=$(curl -s -w "\n%{http_code}" "$health_url" -H "Authorization: Bearer $api_key" 2>/dev/null || echo "000")
    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
        echo "✓ Portal is reachable"
        return 0
    else
        echo "⚠ Warning: Could not reach portal (HTTP $http_code)"
        echo "  This might be a network issue or the portal might be down."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        return 1
    fi
}

fetch_sites() {
    local portal_url=$1
    local api_key=$2

    local sites_url="${portal_url}/api/companies"
    local response=$(curl -s "$sites_url" -H "Authorization: Bearer $api_key" 2>/dev/null)

    echo "$response"
}

configure_agent() {
    echo ""
    echo "======================================"
    echo "Interactive Agent Configuration"
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

    echo "This wizard will guide you through configuring your pod."
    echo ""
    echo "You'll need:"
    echo "  1. Your PlateBridge portal URL"
    echo "  2. An API key (generated from Settings → POD API Keys)"
    echo "  3. The Site ID where this pod is located"
    echo ""
    read -p "Press Enter to continue..."
    echo ""

    while true; do
        echo "Step 1: Portal URL"
        echo "────────────────────────────────────"
        read -p "Enter your portal URL (e.g., https://platebridge.vercel.app): " PORTAL_URL

        if validate_not_empty "$PORTAL_URL"; then
            if validate_url "$PORTAL_URL"; then
                PORTAL_URL=$(echo "$PORTAL_URL" | sed 's:/*$::')
                echo "✓ Valid URL format"
                break
            else
                echo "✗ Invalid URL. Must start with http:// or https://"
            fi
        else
            echo "✗ Portal URL cannot be empty"
        fi
        echo ""
    done
    echo ""

    while true; do
        echo "Step 2: API Key"
        echo "────────────────────────────────────"
        echo "To generate an API key:"
        echo "  1. Log into your portal"
        echo "  2. Go to Settings"
        echo "  3. Click 'POD API Keys'"
        echo "  4. Click 'Generate New Key'"
        echo "  5. Copy the key (you won't see it again!)"
        echo ""
        read -s -p "Paste your API key: " API_KEY
        echo ""

        if validate_not_empty "$API_KEY"; then
            echo "✓ API key received"

            if test_portal_connection "$PORTAL_URL" "$API_KEY"; then
                break
            fi
        else
            echo "✗ API key cannot be empty"
        fi
        echo ""
    done
    echo ""

    while true; do
        echo "Step 3: Site Selection"
        echo "────────────────────────────────────"
        echo "Fetching available sites from your portal..."
        echo ""

        SITES_JSON=$(fetch_sites "$PORTAL_URL" "$API_KEY")

        if [ -n "$SITES_JSON" ] && [ "$SITES_JSON" != "null" ]; then
            echo "Available sites:"
            echo "$SITES_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    companies = data.get("companies", [])
    if not companies:
        print("  No sites found in your portal")
        sys.exit(1)
    for idx, company in enumerate(companies, 1):
        print(f"  {idx}. {company.get("name", "Unnamed")} (ID: {company.get("id", "")})")
        sites = company.get("sites", [])
        for site in sites:
            print(f"     → {site.get("name", "Unnamed Site")} (ID: {site.get("id", "")})")
except:
    sys.exit(1)
' 2>/dev/null

            if [ $? -eq 0 ]; then
                echo ""
                echo "You can either:"
                echo "  - Enter a site number from the list above"
                echo "  - Paste a Site ID directly"
                echo ""
                read -p "Site # or Site ID: " SITE_INPUT

                if [[ $SITE_INPUT =~ ^[0-9]+$ ]]; then
                    SITE_ID=$(echo "$SITES_JSON" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    companies = data.get("companies", [])
    site_num = int(sys.argv[1])
    count = 0
    for company in companies:
        for site in company.get("sites", []):
            count += 1
            if count == site_num:
                print(site.get("id", ""))
                sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
' "$SITE_INPUT" 2>/dev/null)

                    if [ -n "$SITE_ID" ]; then
                        echo "✓ Selected site: $SITE_ID"
                        break
                    else
                        echo "✗ Invalid selection"
                    fi
                else
                    SITE_ID="$SITE_INPUT"
                    if validate_not_empty "$SITE_ID"; then
                        echo "✓ Using Site ID: $SITE_ID"
                        break
                    fi
                fi
            fi
        fi

        echo ""
        echo "Could not fetch sites automatically."
        read -p "Enter Site ID manually: " SITE_ID

        if validate_not_empty "$SITE_ID"; then
            echo "✓ Site ID set"
            break
        else
            echo "✗ Site ID cannot be empty"
        fi
        echo ""
    done
    echo ""

    while true; do
        echo "Step 4: Pod Identification"
        echo "────────────────────────────────────"
        echo "Give this pod a unique name (e.g., front-gate, main-entrance)"
        echo ""
        read -p "Pod ID: " POD_ID

        if validate_not_empty "$POD_ID"; then
            POD_ID=$(echo "$POD_ID" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            echo "✓ Pod ID: $POD_ID"
            break
        else
            echo "✗ Pod ID cannot be empty"
        fi
        echo ""
    done
    echo ""

    echo "Step 5: Frigate MQTT Configuration"
    echo "────────────────────────────────────"
    echo "Configure connection to your Frigate MQTT broker"
    echo "(Press Enter to use defaults)"
    echo ""

    read -p "MQTT Host [localhost]: " MQTT_HOST
    MQTT_HOST=${MQTT_HOST:-localhost}
    echo "  Using: $MQTT_HOST"

    read -p "MQTT Port [1883]: " MQTT_PORT
    MQTT_PORT=${MQTT_PORT:-1883}
    echo "  Using: $MQTT_PORT"

    read -p "MQTT Username (leave empty if not needed): " MQTT_USER
    if [ -n "$MQTT_USER" ]; then
        read -s -p "MQTT Password: " MQTT_PASS
        echo ""
        echo "  ✓ Credentials set"
    else
        MQTT_PASS=""
        echo "  No authentication configured"
    fi

    echo ""
    echo "======================================"
    echo "Configuration Summary"
    echo "======================================"
    echo "Portal URL: $PORTAL_URL"
    echo "Site ID: $SITE_ID"
    echo "Pod ID: $POD_ID"
    echo "MQTT Host: $MQTT_HOST:$MQTT_PORT"
    echo "======================================"
    echo ""
    read -p "Save this configuration? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Configuration cancelled. Run setup again to reconfigure."
        exit 0
    fi

    cat > "$INSTALL_DIR/config.yaml" << EOF
# PlateBridge Pod Configuration
# Generated on $(date)

# Portal Configuration
portal_url: "$PORTAL_URL"
api_key: "$API_KEY"

# Pod/Site Identification
site_id: "$SITE_ID"
pod_id: "$POD_ID"

# Frigate MQTT Configuration
frigate_mqtt_host: "$MQTT_HOST"
frigate_mqtt_port: $MQTT_PORT
frigate_mqtt_username: "$MQTT_USER"
frigate_mqtt_password: "$MQTT_PASS"
frigate_mqtt_topic: "frigate/events"

# Detection Settings
min_confidence: 0.7
whitelist_refresh_interval: 300

# Logging
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
