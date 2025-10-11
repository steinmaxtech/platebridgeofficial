#!/bin/bash
#
# PlateBridge POD - Dual NIC Network Configuration
# Sets up two network interfaces:
#   - eth0/enp0s3: WAN (Internet connection)
#   - eth1/enp0s8: LAN (Camera network, isolated)
#
# Usage: sudo ./network-config.sh
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_info "🌐 PlateBridge POD - Dual NIC Network Setup"
echo ""

# Detect network interfaces
log_info "Detecting network interfaces..."
INTERFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|ens|eno)' | head -2))

if [ ${#INTERFACES[@]} -lt 2 ]; then
    log_error "Could not find 2 network interfaces. Found: ${INTERFACES[@]}"
    log_info "Available interfaces:"
    ip -o link show | awk -F': ' '{print $2}'
    exit 1
fi

WAN_INTERFACE="${INTERFACES[0]}"
LAN_INTERFACE="${INTERFACES[1]}"

log_success "Detected interfaces:"
log_info "  WAN (Internet): $WAN_INTERFACE"
log_info "  LAN (Cameras):  $LAN_INTERFACE"
echo ""

# Prompt for confirmation
read -p "Is this correct? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Please edit this script to manually set WAN_INTERFACE and LAN_INTERFACE"
    exit 0
fi

# Network configuration
WAN_USE_DHCP=true
WAN_STATIC_IP=""
WAN_GATEWAY=""
WAN_DNS="8.8.8.8,8.8.4.4"

LAN_NETWORK="192.168.100"
LAN_IP="${LAN_NETWORK}.1"
LAN_NETMASK="255.255.255.0"
LAN_DHCP_START="${LAN_NETWORK}.100"
LAN_DHCP_END="${LAN_NETWORK}.200"

echo ""
log_info "📡 WAN Configuration"
read -p "Use DHCP for WAN? (yes/no) [yes]: " WAN_DHCP_INPUT
WAN_DHCP_INPUT=${WAN_DHCP_INPUT:-yes}

if [[ "$WAN_DHCP_INPUT" != "yes" ]]; then
    WAN_USE_DHCP=false
    read -p "WAN Static IP (e.g., 192.168.1.100): " WAN_STATIC_IP
    read -p "WAN Gateway (e.g., 192.168.1.1): " WAN_GATEWAY
    read -p "DNS Servers [8.8.8.8,8.8.4.4]: " WAN_DNS_INPUT
    WAN_DNS=${WAN_DNS_INPUT:-8.8.8.8,8.8.4.4}
fi

echo ""
log_info "📷 Camera Network Configuration"
read -p "Camera network subnet [192.168.100]: " LAN_INPUT
LAN_NETWORK=${LAN_INPUT:-192.168.100}
LAN_IP="${LAN_NETWORK}.1"
LAN_DHCP_START="${LAN_NETWORK}.100"
LAN_DHCP_END="${LAN_NETWORK}.200"

echo ""
log_info "Configuration Summary:"
log_info "  WAN Interface: $WAN_INTERFACE"
if [ "$WAN_USE_DHCP" = true ]; then
    log_info "    Mode: DHCP"
else
    log_info "    Mode: Static"
    log_info "    IP: $WAN_STATIC_IP"
    log_info "    Gateway: $WAN_GATEWAY"
fi
log_info "  LAN Interface: $LAN_INTERFACE"
log_info "    POD IP: $LAN_IP/24"
log_info "    Camera DHCP Range: $LAN_DHCP_START - $LAN_DHCP_END"
echo ""

read -p "Apply this configuration? (yes/no): " APPLY
if [[ "$APPLY" != "yes" ]]; then
    log_info "Configuration cancelled"
    exit 0
fi

# Backup existing configuration
log_info "Backing up existing network configuration..."
mkdir -p /opt/platebridge/backups
if [ -f /etc/netplan/01-netcfg.yaml ]; then
    cp /etc/netplan/01-netcfg.yaml /opt/platebridge/backups/01-netcfg.yaml.backup.$(date +%Y%m%d%H%M%S)
fi

# Create netplan configuration
log_info "Creating netplan configuration..."
cat > /etc/netplan/01-platebridge-network.yaml <<EOF
# PlateBridge POD Network Configuration
# Generated: $(date)
#
# WAN: $WAN_INTERFACE (Internet)
# LAN: $LAN_INTERFACE (Cameras)

network:
  version: 2
  renderer: networkd
  ethernets:
    $WAN_INTERFACE:
      dhcp4: $WAN_USE_DHCP
EOF

if [ "$WAN_USE_DHCP" = false ]; then
    cat >> /etc/netplan/01-platebridge-network.yaml <<EOF
      addresses:
        - $WAN_STATIC_IP/24
      routes:
        - to: default
          via: $WAN_GATEWAY
      nameservers:
        addresses: [$(echo $WAN_DNS | tr ',' ' ')]
EOF
fi

cat >> /etc/netplan/01-platebridge-network.yaml <<EOF
    $LAN_INTERFACE:
      dhcp4: false
      addresses:
        - $LAN_IP/24
EOF

log_success "Netplan configuration created"

# Install and configure dnsmasq for DHCP on camera network
log_info "Installing dnsmasq for camera DHCP..."
apt-get update -qq
apt-get install -y -qq dnsmasq

# Backup dnsmasq config
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /opt/platebridge/backups/dnsmasq.conf.backup.$(date +%Y%m%d%H%M%S)
fi

# Create dnsmasq configuration
log_info "Configuring DHCP server for camera network..."
cat > /etc/dnsmasq.d/platebridge-cameras.conf <<EOF
# PlateBridge Camera Network DHCP Configuration
# Generated: $(date)

# Listen only on camera interface
interface=$LAN_INTERFACE
bind-interfaces

# DHCP range for cameras
dhcp-range=$LAN_DHCP_START,$LAN_DHCP_END,24h

# DNS servers for cameras (use POD as relay)
dhcp-option=option:dns-server,$LAN_IP

# Domain name
domain=cameras.local

# Log DHCP requests
log-dhcp

# Don't forward DNS queries for this network to upstream
no-resolv
no-poll

# Use upstream DNS from WAN
server=$WAN_DNS
EOF

log_success "DHCP server configured"

# Enable IP forwarding (for internet access to cameras if needed)
log_info "Configuring IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-platebridge-forwarding.conf
sysctl -p /etc/sysctl.d/99-platebridge-forwarding.conf

# Configure firewall
log_info "Configuring firewall..."

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow ssh

# Allow from camera network
ufw allow from $LAN_NETWORK.0/24

# Allow RTSP from cameras
ufw allow from $LAN_NETWORK.0/24 to any port 8554 proto tcp

# Allow HTTP/HTTPS for Frigate UI (optional)
ufw allow from $LAN_NETWORK.0/24 to any port 5000 proto tcp
ufw allow from $LAN_NETWORK.0/24 to any port 443 proto tcp

# Allow WAN access
ufw allow in on $WAN_INTERFACE to any port 80 proto tcp
ufw allow in on $WAN_INTERFACE to any port 443 proto tcp
ufw allow in on $WAN_INTERFACE to any port 8000 proto tcp  # Stream server

# Enable NAT for cameras (optional - allows cameras to reach internet)
read -p "Allow cameras to access internet via NAT? (yes/no) [no]: " ENABLE_NAT
ENABLE_NAT=${ENABLE_NAT:-no}

if [[ "$ENABLE_NAT" == "yes" ]]; then
    log_info "Enabling NAT for camera network..."

    # Enable NAT in UFW
    cat >> /etc/ufw/before.rules <<EOF

# PlateBridge NAT rules
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $LAN_NETWORK.0/24 -o $WAN_INTERFACE -j MASQUERADE
COMMIT
EOF

    log_success "NAT enabled for cameras"
else
    log_info "Cameras will NOT have internet access (isolated network)"
fi

# Enable firewall
ufw --force enable
log_success "Firewall configured"

# Apply network configuration
log_info "Applying network configuration..."
netplan apply

# Restart dnsmasq
systemctl enable dnsmasq
systemctl restart dnsmasq

# Wait for network to settle
sleep 5

# Verify configuration
log_info "Verifying network configuration..."
echo ""

log_info "WAN Interface ($WAN_INTERFACE):"
ip addr show $WAN_INTERFACE | grep "inet " || log_warning "No IP address assigned"

echo ""
log_info "LAN Interface ($LAN_INTERFACE):"
ip addr show $LAN_INTERFACE | grep "inet "

echo ""
log_info "DHCP Server Status:"
systemctl status dnsmasq --no-pager | head -5

echo ""
log_info "Testing internet connectivity..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log_success "Internet connectivity: OK"
else
    log_warning "Internet connectivity: FAILED (check WAN configuration)"
fi

# Create network info file
cat > /opt/platebridge/network-info.txt <<EOF
PlateBridge POD Network Configuration
Generated: $(date)

WAN Interface: $WAN_INTERFACE
WAN Mode: $([ "$WAN_USE_DHCP" = true ] && echo "DHCP" || echo "Static")
$([ "$WAN_USE_DHCP" = false ] && echo "WAN IP: $WAN_STATIC_IP")
$([ "$WAN_USE_DHCP" = false ] && echo "WAN Gateway: $WAN_GATEWAY")

LAN Interface: $LAN_INTERFACE
LAN IP: $LAN_IP/24
Camera Network: $LAN_NETWORK.0/24
DHCP Range: $LAN_DHCP_START - $LAN_DHCP_END

NAT Enabled: $ENABLE_NAT

Camera Configuration:
- Set cameras to DHCP
- They will receive IPs in range $LAN_DHCP_START - $LAN_DHCP_END
- RTSP URLs will be: rtsp://<camera-ip>:554/stream

To view connected cameras:
  sudo arp-scan --interface=$LAN_INTERFACE $LAN_NETWORK.0/24
  sudo nmap -sn $LAN_NETWORK.0/24

To see DHCP leases:
  cat /var/lib/misc/dnsmasq.leases

Firewall status:
  sudo ufw status

Network interfaces:
  ip addr show
EOF

log_success "Network info saved to /opt/platebridge/network-info.txt"

echo ""
log_success "================================================"
log_success "✅ Network Configuration Complete!"
log_success "================================================"
echo ""
log_info "Next Steps:"
log_info "1. Connect cameras to $LAN_INTERFACE network"
log_info "2. Cameras should automatically get DHCP IPs"
log_info "3. Scan for cameras:"
log_info "   sudo apt install arp-scan nmap"
log_info "   sudo arp-scan --interface=$LAN_INTERFACE $LAN_NETWORK.0/24"
echo ""
log_info "4. Find camera RTSP URLs:"
log_info "   - Check camera web interface"
log_info "   - Default: rtsp://<camera-ip>:554/stream"
log_info "   - Common paths: /stream, /h264, /live, /ch01"
echo ""
log_info "Configuration saved to:"
log_info "  /opt/platebridge/network-info.txt"
log_info "  /etc/netplan/01-platebridge-network.yaml"
log_info "  /etc/dnsmasq.d/platebridge-cameras.conf"
echo ""
log_warning "A reboot is recommended to ensure all settings take effect"
read -p "Reboot now? (yes/no): " REBOOT
if [[ "$REBOOT" == "yes" ]]; then
    log_info "Rebooting in 5 seconds..."
    sleep 5
    reboot
fi
