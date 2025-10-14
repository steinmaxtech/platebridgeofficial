#!/bin/bash

# PlateBridge POD - Update Config and Restart
# Fixes config issues and restarts containers

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_step() {
    echo -e "${GREEN}▶${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

check_installation() {
    print_header "Checking Installation"

    if [ ! -d "/opt/platebridge-pod" ]; then
        print_error "POD not installed at /opt/platebridge-pod"
        exit 1
    fi

    print_success "Installation found"
}

backup_config() {
    print_header "Backing Up Existing Config"

    if [ -f "/opt/platebridge-pod/config/config.yaml" ]; then
        cp /opt/platebridge-pod/config/config.yaml /opt/platebridge-pod/config/config.yaml.backup.$(date +%s)
        print_success "Config backed up"
    else
        print_warning "No existing config found"
    fi
}

fix_pod_config() {
    print_header "Fixing POD Agent Config"

    CONFIG_FILE="/opt/platebridge-pod/config/config.yaml"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Config file not found at $CONFIG_FILE"
        return 1
    fi

    # Read current values
    PORTAL_URL=$(grep "portal_url:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    POD_ID=$(grep "pod_id:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')

    # Check for old key name
    if grep -q "^api_key:" "$CONFIG_FILE"; then
        API_KEY=$(grep "^api_key:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
        print_warning "Found old 'api_key' field, converting to 'pod_api_key'"
    elif grep -q "^pod_api_key:" "$CONFIG_FILE"; then
        API_KEY=$(grep "^pod_api_key:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"')
    else
        print_error "No API key found in config"
        return 1
    fi

    print_step "Creating updated config..."
    cat > "$CONFIG_FILE" << EOF
portal_url: "$PORTAL_URL"
pod_api_key: "$API_KEY"
pod_id: "$POD_ID"
camera_id: "camera_1"
camera_name: "Main Camera"
camera_rtsp_url: "rtsp://192.168.1.100:554/stream1"
camera_position: "main entrance"
camera_ip: "192.168.1.100"
stream_port: 8000
recordings_dir: "/recordings"
heartbeat_interval: 60
whitelist_refresh_interval: 300
EOF

    # Also copy to docker directory if it exists
    if [ -d "/opt/platebridge-pod/docker" ]; then
        cp "$CONFIG_FILE" /opt/platebridge-pod/docker/config.yaml
        print_success "Config synced to docker directory"
    fi

    print_success "POD config updated with correct keys"
}

fix_frigate_config() {
    print_header "Fixing Frigate Config"

    FRIGATE_CONFIG="/opt/platebridge-pod/frigate/config/config.yml"

    if [ ! -f "$FRIGATE_CONFIG" ]; then
        print_warning "Frigate config not found - skipping"
        return 0
    fi

    # Check if cameras section is empty or missing
    if ! grep -A 5 "^cameras:" "$FRIGATE_CONFIG" | grep -q "dummy:"; then
        print_step "Adding dummy camera to Frigate config..."

        # Backup
        cp "$FRIGATE_CONFIG" "${FRIGATE_CONFIG}.backup.$(date +%s)"

        # Replace empty cameras section with dummy camera
        sed -i '/^cameras:/,/^[^ ]/ {
            /^cameras:/ {
                a\  # Dummy camera to prevent startup errors\n  # Replace with your actual cameras\n  dummy:\n    enabled: false\n    ffmpeg:\n      inputs:\n        - path: rtsp://127.0.0.1:8554/dummy\n          roles: [detect]\n
            }
            /^  # Add cameras here/d
            /^  # camera_1:/,/^[^ ]/ {
                s/^  # /  # Example: /
            }
        }' "$FRIGATE_CONFIG"

        print_success "Frigate config updated with dummy camera"
    else
        print_success "Frigate config already has cameras configured"
    fi
}

stop_containers() {
    print_header "Stopping Containers"

    print_step "Stopping platebridge-pod..."
    docker stop platebridge-pod 2>/dev/null || print_warning "Container not running"

    print_step "Stopping frigate..."
    docker stop frigate 2>/dev/null || print_warning "Container not running"

    print_step "Stopping mosquitto..."
    docker stop mosquitto 2>/dev/null || print_warning "Container not running"

    print_success "Containers stopped"
}

start_containers() {
    print_header "Starting Containers"

    if [ -d "/opt/platebridge-pod/docker" ]; then
        cd /opt/platebridge-pod/docker

        print_step "Starting services..."
        docker compose up -d

        sleep 5

        print_step "Checking status..."
        docker ps | grep -E "platebridge|frigate|mosquitto" || print_warning "No containers running"

        print_success "Services started"
    else
        print_error "Docker directory not found"
        return 1
    fi
}

check_health() {
    print_header "Health Check"

    sleep 10

    # Check POD agent
    if docker ps | grep -q platebridge-pod; then
        RESTARTS=$(docker inspect platebridge-pod --format='{{.RestartCount}}' 2>/dev/null || echo "unknown")
        STATUS=$(docker inspect platebridge-pod --format='{{.State.Status}}' 2>/dev/null || echo "unknown")

        print_step "POD Agent:"
        echo "  Status: $STATUS"
        echo "  Restarts: $RESTARTS"

        if [ "$RESTARTS" != "0" ] && [ "$RESTARTS" != "unknown" ]; then
            print_error "Container is restarting!"
            echo ""
            print_step "Recent logs:"
            docker logs --tail 30 platebridge-pod
        else
            print_success "POD agent running stable"
        fi
    else
        print_error "POD agent not running"
    fi

    # Check Frigate
    if docker ps | grep -q frigate; then
        FRIGATE_STATUS=$(docker inspect frigate --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        print_step "Frigate: $FRIGATE_STATUS"

        if [ "$FRIGATE_STATUS" != "running" ]; then
            print_warning "Frigate issues detected"
            docker logs --tail 20 frigate
        fi
    fi
}

show_logs() {
    print_header "Recent Logs"

    echo -e "${YELLOW}POD Agent Logs:${NC}"
    docker logs --tail 20 platebridge-pod 2>/dev/null || print_warning "No logs available"

    echo ""
    echo -e "${YELLOW}Frigate Logs:${NC}"
    docker logs --tail 20 frigate 2>/dev/null || print_warning "No logs available"
}

main() {
    print_header "PlateBridge POD - Config Update & Restart"

    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi

    check_installation
    backup_config
    fix_pod_config
    fix_frigate_config
    stop_containers
    start_containers
    check_health

    echo ""
    print_header "Update Complete"

    echo "To monitor logs in real-time:"
    echo "  docker logs -f platebridge-pod"
    echo ""
    echo "To check container status:"
    echo "  docker ps"
    echo ""
    echo "Config location:"
    echo "  /opt/platebridge-pod/config/config.yaml"
}

main "$@"
