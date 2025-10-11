#!/bin/bash

################################################################################
# PlateBridge POD - Python Agent Installation (No Docker)
#
# This installs the pod-agent as a native Python systemd service
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/platebridge"
POD_USER="platebridge"

print_step() {
    echo -e "${GREEN}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_step "Creating POD user..."
if ! id "$POD_USER" &>/dev/null; then
    useradd -r -m -s /bin/bash "$POD_USER"
fi

print_step "Setting up directories..."
mkdir -p $INSTALL_DIR/{config,logs,recordings}
mkdir -p /tmp/hls_output

print_step "Installing Python dependencies..."
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv ffmpeg

print_step "Creating virtual environment..."
cd $INSTALL_DIR
python3 -m venv venv

print_step "Installing requirements..."
source venv/bin/activate
pip install --upgrade pip
pip install -r /path/to/requirements.txt
deactivate

print_step "Copying agent files..."
cp /path/to/complete_pod_agent.py $INSTALL_DIR/agent.py
cp /path/to/config.example.yaml $INSTALL_DIR/config.yaml

print_step "Configuring portal connection..."
read -p "Portal URL: " PORTAL_URL
read -p "Registration Token: " REG_TOKEN

# Get hardware info
SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || echo "POD-$(hostname)-$(date +%s)")
MAC=$(ip link show | grep link/ether | head -1 | awk '{print $2}')
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "PB-M1")

# Register POD
print_step "Registering POD with portal..."
REGISTER_RESPONSE=$(curl -s -X POST "$PORTAL_URL/api/pods/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"serial\": \"$SERIAL\",
        \"mac\": \"$MAC\",
        \"model\": \"$MODEL\",
        \"version\": \"1.0.0\",
        \"registration_token\": \"$REG_TOKEN\"
    }")

POD_API_KEY=$(echo "$REGISTER_RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
POD_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"pod_id":"[^"]*"' | cut -d'"' -f4)

if [ -z "$POD_API_KEY" ]; then
    print_error "Failed to register POD"
    exit 1
fi

print_success "POD registered: $POD_ID"

# Create config file
cat > $INSTALL_DIR/config.yaml << EOF
portal_url: "$PORTAL_URL"
api_key: "$POD_API_KEY"
pod_id: "$POD_ID"
camera_ip: "192.168.100.100"
stream_port: 8000
recordings_dir: "$INSTALL_DIR/recordings"
EOF

# Create systemd service
print_step "Creating systemd service..."
cat > /etc/systemd/system/platebridge-agent.service << EOF
[Unit]
Description=PlateBridge POD Agent
After=network.target

[Service]
Type=simple
User=$POD_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/agent.py
Restart=always
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/agent.log
StandardError=append:$INSTALL_DIR/logs/agent-error.log

[Install]
WantedBy=multi-user.target
EOF

print_step "Setting permissions..."
chown -R $POD_USER:$POD_USER $INSTALL_DIR
chmod 600 $INSTALL_DIR/config.yaml

print_step "Starting service..."
systemctl daemon-reload
systemctl enable platebridge-agent
systemctl start platebridge-agent

print_success "Installation complete!"
echo ""
echo "Service status:"
systemctl status platebridge-agent --no-pager

echo ""
echo "Useful commands:"
echo "  View logs: journalctl -u platebridge-agent -f"
echo "  Restart:   sudo systemctl restart platebridge-agent"
echo "  Status:    sudo systemctl status platebridge-agent"
