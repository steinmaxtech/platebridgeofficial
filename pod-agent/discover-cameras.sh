#!/bin/bash
#
# PlateBridge Camera Discovery Tool
# Scans the camera network and tests RTSP connections
#
# Usage:
#   sudo ./discover-cameras.sh [interface]
#
# Examples:
#   sudo ./discover-cameras.sh           # Auto-detect camera interface
#   sudo ./discover-cameras.sh eth1      # Use specific interface
#   sudo ./discover-cameras.sh enp3s0    # Use specific interface
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "📷 PlateBridge Camera Discovery Tool"
echo ""

# Check if interface provided as argument
if [ -n "$1" ]; then
    CAMERA_INTERFACE="$1"
    log_info "Using specified interface: $CAMERA_INTERFACE"
else
    # Find camera interface
    log_info "Detecting network interfaces..."
    echo ""

    # List all interfaces with IPs
    echo "Available interfaces:"
    ip -o -4 addr show | awk '{print $2, $4}' | while read iface ip; do
        echo "  $iface: $ip"
    done
    echo ""

    # Try to auto-detect camera interface
    # Camera LAN is typically 192.168.100.x range
    CAMERA_INTERFACE=""
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|ens|eno)'); do
        iface_ip=$(ip addr show $iface 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$iface_ip" ]; then
            # Check if this is the 192.168.100.x network
            if [[ "$iface_ip" == 192.168.100.* ]]; then
                CAMERA_INTERFACE="$iface"
                log_success "Auto-detected camera interface: $CAMERA_INTERFACE"
                break
            fi
        fi
    done

    # If not found, prompt user
    if [ -z "$CAMERA_INTERFACE" ]; then
        log_warning "Could not auto-detect camera interface (looking for 192.168.100.x)"
        echo ""
        read -p "Enter camera LAN interface name (e.g., eth1, enp3s0): " CAMERA_INTERFACE

        if [ -z "$CAMERA_INTERFACE" ]; then
            log_error "No interface specified"
            exit 1
        fi
    fi
fi

LAN_INTERFACE="$CAMERA_INTERFACE"

# Get network from interface
LAN_IP=$(ip addr show $LAN_INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
if [ -z "$LAN_IP" ]; then
    log_error "Interface $LAN_INTERFACE has no IP address"
    log_info "Make sure the camera network is configured"
    exit 1
fi

LAN_NETWORK=$(echo $LAN_IP | cut -d'.' -f1-3)

log_success "Camera interface: $LAN_INTERFACE ($LAN_IP)"
log_info "Camera network: $LAN_NETWORK.0/24"
echo ""

# Install required tools
log_info "Checking required tools..."
if ! command -v arp-scan &> /dev/null; then
    log_info "Installing arp-scan..."
    apt-get update -qq
    apt-get install -y -qq arp-scan
fi

if ! command -v nmap &> /dev/null; then
    log_info "Installing nmap..."
    apt-get install -y -qq nmap
fi

if ! command -v ffprobe &> /dev/null; then
    log_info "Installing ffmpeg tools..."
    apt-get install -y -qq ffmpeg
fi

log_success "Tools ready"
echo ""

# Scan for devices
log_info "🔍 Scanning for devices on camera network..."
echo "This may take 30-60 seconds..."
echo ""

DEVICES=$(arp-scan --interface=$LAN_INTERFACE $LAN_NETWORK.0/24 2>/dev/null | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v "packets received" || true)

if [ -z "$DEVICES" ]; then
    log_warning "No devices found on camera network"
    log_info "Make sure cameras are:"
    log_info "  1. Powered on"
    log_info "  2. Connected to camera network port"
    log_info "  3. Set to DHCP mode (or static IP in $LAN_NETWORK.0/24)"
    exit 1
fi

log_success "Found devices on network:"
echo "$DEVICES"
echo ""

# Extract IPs
IPS=($(echo "$DEVICES" | awk '{print $1}'))

log_info "📹 Testing for cameras and RTSP streams..."
echo ""

# Common RTSP paths to test
RTSP_PATHS=(
    "/stream"
    "/h264"
    "/h265"
    "/live"
    "/ch01"
    "/Streaming/Channels/101"
    "/video1"
    "/cam/realmonitor?channel=1&subtype=0"
    "/1"
    "/0"
)

CAMERA_COUNT=0
declare -A CAMERA_URLS

for IP in "${IPS[@]}"; do
    # Skip gateway (usually .1)
    if [[ "$IP" == "$LAN_IP" ]]; then
        continue
    fi

    log_info "Testing $IP..."

    # Check if port 554 (RTSP) is open
    if timeout 2 bash -c "echo >/dev/tcp/$IP/554" 2>/dev/null; then
        log_success "  RTSP port 554 open"

        # Test common RTSP paths
        for PATH in "${RTSP_PATHS[@]}"; do
            RTSP_URL="rtsp://$IP:554$PATH"

            # Test with ffprobe (timeout 3 seconds)
            if timeout 3 ffprobe -rtsp_transport tcp -i "$RTSP_URL" 2>&1 | grep -q "Video:"; then
                log_success "  ✓ Found working RTSP stream: $RTSP_URL"
                CAMERA_URLS[$IP]="$RTSP_URL"
                ((CAMERA_COUNT++))
                break
            fi
        done

        if [ -z "${CAMERA_URLS[$IP]}" ]; then
            log_warning "  Found RTSP port but no valid stream paths"
            log_info "  Try accessing http://$IP in web browser to find RTSP URL"
        fi
    else
        # Check if port 80 (HTTP) is open
        if timeout 2 bash -c "echo >/dev/tcp/$IP/80" 2>/dev/null; then
            log_info "  HTTP port 80 open - likely a camera with web interface"
            log_info "  Access: http://$IP (check for RTSP settings)"
        else
            log_info "  No camera services detected"
        fi
    fi
    echo ""
done

# Summary
echo ""
log_info "================================================"
log_success "✅ Discovery Complete"
log_info "================================================"
echo ""

if [ $CAMERA_COUNT -eq 0 ]; then
    log_warning "No working RTSP cameras found"
    log_info ""
    log_info "Troubleshooting:"
    log_info "1. Access cameras via web browser (http://<ip>)"
    log_info "2. Enable RTSP in camera settings"
    log_info "3. Note the RTSP URL path from camera UI"
    log_info "4. Test manually:"
    log_info "   ffplay -rtsp_transport tcp rtsp://<ip>:554/<path>"
else
    log_success "Found $CAMERA_COUNT working camera(s)!"
    echo ""

    # Create config file
    CONFIG_FILE="/opt/platebridge/camera-urls.txt"
    log_info "Saving camera URLs to: $CONFIG_FILE"

    cat > $CONFIG_FILE <<EOF
# PlateBridge Camera URLs
# Generated: $(date)
#
# Use these URLs in your pod config.yaml

EOF

    CAM_NUM=1
    for IP in "${!CAMERA_URLS[@]}"; do
        URL="${CAMERA_URLS[$IP]}"
        echo "camera_${CAM_NUM}_url: \"$URL\"" >> $CONFIG_FILE
        echo "camera_${CAM_NUM}_name: \"Camera $CAM_NUM ($IP)\"" >> $CONFIG_FILE
        echo "" >> $CONFIG_FILE
        ((CAM_NUM++))
    done

    cat $CONFIG_FILE
fi

echo ""
log_info "Network Information:"
log_info "  Interface: $LAN_INTERFACE"
log_info "  POD IP: $LAN_IP"
log_info "  Network: $LAN_NETWORK.0/24"
echo ""

log_info "To view DHCP leases:"
log_info "  cat /var/lib/misc/dnsmasq.leases"
echo ""

log_info "To test a specific RTSP URL:"
log_info "  ffplay -rtsp_transport tcp rtsp://<ip>:554/<path>"
echo ""

if [ $CAMERA_COUNT -gt 0 ]; then
    log_success "Camera URLs saved to: $CONFIG_FILE"
    log_info "Copy these URLs to your /opt/platebridge/config.yaml"
fi
