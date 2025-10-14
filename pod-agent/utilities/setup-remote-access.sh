#!/bin/bash

# PlateBridge POD - Remote Access & Management Setup
# This script configures SSH access and installs Portainer for container management

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
POD_USER="${POD_USER:-platebridge}"
SSH_PORT="${SSH_PORT:-22}"
PORTAINER_PORT="${PORTAINER_PORT:-9443}"

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

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root (use sudo)"
        exit 1
    fi
}

check_logs() {
    print_header "Checking Container Status & Logs"

    print_step "Container status..."
    docker ps -a

    echo ""
    print_step "POD Agent logs (last 20 lines)..."
    if docker ps -a | grep -q platebridge-pod; then
        docker logs --tail 20 platebridge-pod 2>&1 || echo "No logs available"
    else
        print_warning "POD agent container not found"
    fi

    echo ""
    print_step "Frigate logs (last 20 lines)..."
    if docker ps -a | grep -q frigate; then
        docker logs --tail 20 frigate 2>&1 || echo "No logs available"
    else
        print_warning "Frigate container not running (this is OK if not using Frigate)"
    fi
}

fix_config() {
    print_header "Checking Configuration Files"

    if [ ! -f /opt/platebridge/config.yaml ]; then
        print_error "Config file not found at /opt/platebridge/config.yaml"
        print_warning "Creating minimal config..."

        mkdir -p /opt/platebridge
        cat > /opt/platebridge/config.yaml << 'EOF'
pod:
  name: "POD-$(hostname)"
  location: "Default Location"

portal:
  url: "https://your-portal-url.vercel.app"
  api_key: "your-api-key-here"

cameras:
  - name: "Camera 1"
    stream_url: "rtsp://admin:password@192.168.1.50:554/stream1"
    enabled: true

recording:
  enabled: true
  path: "/recordings"
  retention_days: 7

detection:
  confidence_threshold: 0.7

network:
  stream_port: 8765
  health_check_port: 8080
EOF
        print_success "Template config created - EDIT /opt/platebridge/config.yaml with your settings"
    else
        print_success "Config file exists"
        echo "Current config:"
        cat /opt/platebridge/config.yaml
    fi
}

configure_ssh() {
    print_header "Configuring SSH Access"

    print_step "Installing OpenSSH server..."
    apt-get update -qq
    apt-get install -y openssh-server

    print_step "Configuring SSH..."

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Configure SSH securely
    cat > /etc/ssh/sshd_config.d/platebridge.conf << EOF
# PlateBridge POD SSH Configuration
Port $SSH_PORT
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

    print_step "Enabling and starting SSH service..."
    systemctl enable ssh
    systemctl restart ssh

    print_success "SSH configured on port $SSH_PORT"

    # Get IP addresses
    WAN_IP=$(ip -4 addr show $(ip route | grep default | awk '{print $5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

    echo ""
    print_success "SSH Access Information:"
    echo "  Local: ssh $POD_USER@$WAN_IP -p $SSH_PORT"
    echo "  From outside: You'll need to configure port forwarding on your router"
    echo "  Router setup: Forward external port $SSH_PORT to $WAN_IP:$SSH_PORT"
}

install_portainer() {
    print_header "Installing Portainer"

    # Check if already running
    if docker ps | grep -q portainer; then
        print_warning "Portainer already running"
        return 0
    fi

    print_step "Creating Portainer volume..."
    docker volume create portainer_data

    print_step "Starting Portainer..."
    docker run -d \
        --name portainer \
        --restart=unless-stopped \
        -p 8000:8000 \
        -p $PORTAINER_PORT:9443 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    sleep 5

    if docker ps | grep -q portainer; then
        print_success "Portainer installed successfully!"

        WAN_IP=$(ip -4 addr show $(ip route | grep default | awk '{print $5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

        echo ""
        print_success "Portainer Access:"
        echo "  Local: https://$WAN_IP:$PORTAINER_PORT"
        echo "  From outside: Configure router port forwarding for port $PORTAINER_PORT"
        echo ""
        print_warning "First-time setup:"
        echo "  1. Open the URL above in your browser"
        echo "  2. Create an admin account (do this within 5 minutes!)"
        echo "  3. Select 'Docker' as the environment"
        echo "  4. Manage all containers from the web UI"
    else
        print_error "Portainer failed to start"
        docker logs portainer
    fi
}

restart_services() {
    print_header "Restarting POD Services"

    cd /opt/platebridge-pod/docker 2>/dev/null || cd /opt/platebridge 2>/dev/null || {
        print_error "Cannot find POD directory"
        return 1
    }

    print_step "Stopping services..."
    docker compose down 2>/dev/null || true

    print_step "Starting services..."
    docker compose up -d

    sleep 5

    print_step "Service status..."
    docker ps
}

show_troubleshooting() {
    print_header "Troubleshooting Commands"

    echo "View logs:"
    echo "  docker logs -f platebridge-pod       # Follow POD agent logs"
    echo "  docker logs -f frigate               # Follow Frigate logs"
    echo ""
    echo "Container management:"
    echo "  docker ps -a                         # List all containers"
    echo "  docker restart platebridge-pod       # Restart POD agent"
    echo "  docker compose restart               # Restart all services"
    echo ""
    echo "Configuration:"
    echo "  nano /opt/platebridge/config.yaml   # Edit config"
    echo "  docker compose up -d                 # Apply changes"
    echo ""
    echo "Portainer:"
    echo "  https://$(hostname -I | awk '{print $1}'):$PORTAINER_PORT"
}

# Main execution
main() {
    print_header "PlateBridge POD - Remote Access Setup"

    check_root
    check_logs
    fix_config
    configure_ssh
    install_portainer
    restart_services
    show_troubleshooting

    print_header "Setup Complete!"
    print_success "Your POD is now configured for remote management"
}

main "$@"
