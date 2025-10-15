#!/bin/bash

set -e

API_KEY="$1"
REPO_URL="https://github.com/yourusername/platebridge-pod-agent.git"

echo "======================================"
echo "PlateBridge Pod Agent (Docker)"
echo "======================================"
echo ""

if [ -z "$API_KEY" ]; then
    echo "✗ Error: No API key provided"
    echo ""
    echo "Usage: curl -fsSL https://your-portal.com/install-pod-docker.sh | bash -s -- \"YOUR_API_KEY\""
    exit 1
fi

if [[ ! $API_KEY =~ ^pbk_ ]]; then
    echo "✗ Error: Invalid API key format (must start with pbk_)"
    exit 1
fi

echo "✓ API key received"

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "✗ Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker $USER
        echo "✓ Docker installed"
        echo "⚠ Please log out and back in for Docker permissions to take effect"
        exit 0
    fi
    echo "✓ Docker found"
}

detect_portal_url() {
    echo ""
    echo "Detecting portal URL..."

    local test_urls=(
        "https://platebridgeofficial.vercel.app"
        "https://platebridge.vercel.app"
        "https://app.platebridge.com"
    )

    for url in "${test_urls[@]}"; do
        local response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $API_KEY" \
            "${url}/api/pod/info" 2>/dev/null || echo "000")
        local http_code=$(echo "$response" | tail -n1)

        if [ "$http_code" = "200" ]; then
            PORTAL_URL="$url"
            echo "✓ Portal detected: $PORTAL_URL"
            return 0
        fi
    done

    echo "✗ Could not detect portal URL"
    read -p "Enter your portal URL: " PORTAL_URL
    PORTAL_URL=$(echo "$PORTAL_URL" | sed 's:/*$::')
    return 0
}

fetch_pod_info() {
    echo ""
    echo "Fetching POD configuration..."

    local response=$(curl -s -H "Authorization: Bearer $API_KEY" \
        "${PORTAL_URL}/api/pod/info" 2>/dev/null || echo "")

    if [ -z "$response" ]; then
        echo "✗ Failed to fetch POD info"
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
}

clone_repository() {
    echo ""
    echo "Cloning repository..."

    INSTALL_DIR="$HOME/platebridgeofficial/pod-agent"

    if [ -d "$INSTALL_DIR" ]; then
        echo "✓ Repository already exists, updating..."
        cd "$INSTALL_DIR"
        git pull
    else
        mkdir -p "$HOME/platebridgeofficial"
        cd "$HOME/platebridgeofficial"
        git clone "$REPO_URL" pod-agent
        cd pod-agent
    fi

    echo "✓ Repository ready"
}

create_config() {
    echo ""
    echo "Creating configuration..."

    sudo mkdir -p /opt/platebridge
    sudo mkdir -p /opt/platebridge/recordings
    sudo mkdir -p /opt/platebridge/logs
    sudo mkdir -p /tmp/hls_output

    sudo tee /opt/platebridge/config.yaml > /dev/null << EOF
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

cameras: []
EOF

    sudo chmod 644 /opt/platebridge/config.yaml
    echo "✓ Configuration created at /opt/platebridge/config.yaml"
}

build_and_start() {
    echo ""
    echo "Building and starting Docker container..."

    cd "$INSTALL_DIR"

    # Stop existing container if running
    docker stop platebridge-pod 2>/dev/null || true
    docker rm platebridge-pod 2>/dev/null || true

    # Build the image
    docker build -t platebridge-pod-agent:latest .

    # Start the container
    docker compose up -d

    echo "✓ Container started"
}

main() {
    check_docker
    detect_portal_url

    if ! fetch_pod_info; then
        echo ""
        echo "✗ Failed to configure POD"
        echo "Please check your API key and try again"
        exit 1
    fi

    configure_frigate
    clone_repository
    create_config
    build_and_start

    echo ""
    echo "======================================"
    echo "✓ Installation Complete!"
    echo "======================================"
    echo ""
    echo "Configuration: /opt/platebridge/config.yaml"
    echo "Logs: docker logs -f platebridge-pod"
    echo ""
    echo "Useful commands:"
    echo "  View logs:     docker logs -f platebridge-pod"
    echo "  Stop POD:      docker stop platebridge-pod"
    echo "  Start POD:     docker start platebridge-pod"
    echo "  Restart POD:   docker restart platebridge-pod"
    echo "  Rebuild:       cd $INSTALL_DIR && docker compose up -d --build"
    echo ""
}

main
