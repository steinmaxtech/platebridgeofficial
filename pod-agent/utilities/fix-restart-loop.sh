#!/bin/bash

# PlateBridge POD - Fix Container Restart Loops
# Diagnoses and fixes common issues causing restart loops

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

diagnose_pod_agent() {
    print_header "Diagnosing POD Agent"

    if ! docker ps -a | grep -q platebridge-pod; then
        print_error "POD agent container doesn't exist"
        return 1
    fi

    print_step "Container info:"
    docker inspect platebridge-pod --format='Status: {{.State.Status}}
Restart Count: {{.RestartCount}}
Exit Code: {{.State.ExitCode}}
Error: {{.State.Error}}'

    echo ""
    print_step "Recent logs:"
    docker logs --tail 50 platebridge-pod

    echo ""
    print_step "Checking configuration file..."
    if [ -f /opt/platebridge/config.yaml ]; then
        print_success "Config exists"

        # Check for common issues
        if ! grep -q "portal:" /opt/platebridge/config.yaml; then
            print_error "Missing portal configuration"
        fi
        if ! grep -q "cameras:" /opt/platebridge/config.yaml; then
            print_error "Missing cameras configuration"
        fi
    else
        print_error "Config file missing at /opt/platebridge/config.yaml"
    fi

    echo ""
    print_step "Checking required directories..."
    for dir in /opt/platebridge/recordings /opt/platebridge/logs /tmp/hls_output; do
        if [ -d "$dir" ]; then
            print_success "$dir exists"
        else
            print_warning "$dir missing - creating..."
            mkdir -p "$dir"
            chmod 755 "$dir"
        fi
    done
}

diagnose_frigate() {
    print_header "Diagnosing Frigate"

    if ! docker ps -a | grep -q frigate; then
        print_warning "Frigate not installed (optional)"
        return 0
    fi

    print_step "Container info:"
    docker inspect frigate --format='Status: {{.State.Status}}
Restart Count: {{.RestartCount}}
Exit Code: {{.State.ExitCode}}
Error: {{.State.Error}}'

    echo ""
    print_step "Recent logs:"
    docker logs --tail 50 frigate

    echo ""
    print_step "Checking Frigate config..."
    if [ -f /opt/platebridge/frigate.yml ]; then
        print_success "Frigate config exists"
    else
        print_warning "Frigate config missing - creating minimal config..."
        create_frigate_config
    fi
}

create_frigate_config() {
    mkdir -p /opt/platebridge
    cat > /opt/platebridge/frigate.yml << 'EOF'
mqtt:
  enabled: false

detectors:
  cpu1:
    type: cpu

cameras:
  dummy:
    enabled: false
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/dummy
          roles:
            - detect
EOF
    print_success "Minimal Frigate config created"
}

fix_permissions() {
    print_header "Fixing Permissions"

    print_step "Setting ownership..."
    chown -R 1000:1000 /opt/platebridge 2>/dev/null || true
    chmod -R 755 /opt/platebridge

    print_success "Permissions fixed"
}

create_minimal_config() {
    print_header "Creating Minimal Working Config"

    WAN_IP=$(ip -4 addr show $(ip route | grep default | awk '{print $5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

    cat > /opt/platebridge/config.yaml << EOF
# PlateBridge POD Configuration
# Edit this file with your actual values

pod:
  name: "POD-$(hostname)"
  location: "Location Name"
  mac_address: "$(cat /sys/class/net/$(ip route | grep default | awk '{print $5}' | head -1)/address)"

portal:
  url: "https://your-portal.vercel.app"
  api_key: "your-registration-token"
  heartbeat_interval: 60

cameras:
  # Add your cameras here
  # - name: "Front Gate"
  #   stream_url: "rtsp://admin:password@192.168.100.50:554/stream1"
  #   enabled: true

recording:
  enabled: true
  path: "/recordings"
  retention_days: 7
  max_size_gb: 50

detection:
  enabled: true
  confidence_threshold: 0.7
  save_images: true

network:
  stream_port: 8765
  health_check_port: 8080
  local_ip: "$WAN_IP"

logging:
  level: "INFO"
  path: "/logs"
EOF

    print_success "Minimal config created at /opt/platebridge/config.yaml"
    print_warning "IMPORTANT: Edit the config with your actual portal URL and registration token"
    echo ""
    echo "Edit with: nano /opt/platebridge/config.yaml"
}

stop_and_remove() {
    print_header "Stopping Problem Containers"

    print_step "Stopping all containers..."
    docker stop platebridge-pod 2>/dev/null || true
    docker stop frigate 2>/dev/null || true

    print_step "Removing containers (keeping volumes)..."
    docker rm platebridge-pod 2>/dev/null || true
    docker rm frigate 2>/dev/null || true

    print_success "Containers stopped and removed"
}

rebuild_and_start() {
    print_header "Rebuilding and Starting Services"

    cd /opt/platebridge-pod/docker 2>/dev/null || {
        print_error "Cannot find docker directory"
        print_warning "Run this from the installation directory or specify path"
        return 1
    }

    print_step "Rebuilding POD agent image..."
    docker build --network=host -t platebridge-pod-agent:latest .

    print_step "Starting services..."
    docker compose up -d

    sleep 5

    print_step "Status check..."
    docker ps -a | grep -E "platebridge|frigate"

    echo ""
    print_step "Waiting 10 seconds to check for restarts..."
    sleep 10

    RESTARTS=$(docker inspect platebridge-pod --format='{{.RestartCount}}')
    if [ "$RESTARTS" -gt 0 ]; then
        print_error "Still restarting! ($RESTARTS restarts)"
        echo ""
        print_step "Latest logs:"
        docker logs --tail 30 platebridge-pod
    else
        print_success "Container running stable!"
    fi
}

show_next_steps() {
    print_header "Next Steps"

    echo "1. Edit configuration:"
    echo "   nano /opt/platebridge/config.yaml"
    echo ""
    echo "2. Restart services:"
    echo "   cd /opt/platebridge-pod/docker && docker compose restart"
    echo ""
    echo "3. Monitor logs:"
    echo "   docker logs -f platebridge-pod"
    echo ""
    echo "4. Check status:"
    echo "   docker ps"
}

main() {
    print_header "PlateBridge POD Restart Loop Fix"

    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi

    diagnose_pod_agent
    diagnose_frigate
    fix_permissions

    echo ""
    read -p "Do you want to stop and rebuild the containers? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        stop_and_remove

        if [ ! -f /opt/platebridge/config.yaml ]; then
            create_minimal_config
            print_warning "Config created - please edit before starting"
            echo ""
            read -p "Press Enter after editing config.yaml..."
        fi

        rebuild_and_start
    fi

    show_next_steps

    print_header "Diagnosis Complete"
}

main "$@"
