#!/bin/bash
#
# Complete dnsmasq DHCP Server Fix
# Resolves all common issues preventing DHCP from working
#
# Usage: sudo ./fix-dnsmasq.sh [interface]
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"
}

print_step() { echo -e "${GREEN}►${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

print_header "Complete dnsmasq DHCP Fix"

# Detect or get interface
if [ -n "$1" ]; then
    LAN_INTERFACE="$1"
    print_step "Using specified interface: $LAN_INTERFACE"
else
    print_step "Detecting camera LAN interface..."
    echo ""
    echo "Available interfaces:"
    ip -4 addr show | grep -E "^[0-9]+: |inet " | sed 's/^/  /'
    echo ""

    # Try auto-detect 192.168.100.x
    LAN_INTERFACE=""
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|ens|eno)'); do
        iface_ip=$(ip addr show $iface 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [[ "$iface_ip" == 192.168.100.* ]]; then
            LAN_INTERFACE="$iface"
            print_success "Auto-detected: $LAN_INTERFACE ($iface_ip)"
            break
        fi
    done

    if [ -z "$LAN_INTERFACE" ]; then
        read -p "Enter camera LAN interface (e.g., eth1, enp1s0): " LAN_INTERFACE
    fi
fi

if [ -z "$LAN_INTERFACE" ]; then
    print_error "No interface specified"
    exit 1
fi

echo ""

print_header "Step 1: Configure Network Interface"

print_step "Checking interface $LAN_INTERFACE..."
if ! ip link show $LAN_INTERFACE &>/dev/null; then
    print_error "Interface $LAN_INTERFACE does not exist!"
    exit 1
fi

# Bring interface UP
STATE=$(ip link show $LAN_INTERFACE | grep -oP '(?<=state )[^ ]+')
if [ "$STATE" != "UP" ]; then
    print_step "Bringing interface UP..."
    ip link set $LAN_INTERFACE up
    sleep 2
fi

# Ensure it has the right IP
CURRENT_IP=$(ip -4 addr show $LAN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ "$CURRENT_IP" != "192.168.100.1" ]; then
    print_step "Setting IP to 192.168.100.1..."
    ip addr flush dev $LAN_INTERFACE
    ip addr add 192.168.100.1/24 dev $LAN_INTERFACE
fi

print_success "Interface configured: $LAN_INTERFACE = 192.168.100.1"

print_header "Step 2: Stop Conflicting Services"

print_step "Stopping systemd-resolved..."
systemctl stop systemd-resolved 2>/dev/null || true

print_step "Disabling systemd-resolved DNS stub..."
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/no-stub.conf <<EOF
[Resolve]
DNSStubListener=no
EOF
systemctl restart systemd-resolved 2>/dev/null || true

print_success "Conflicts resolved"

print_header "Step 3: Configure dnsmasq"

print_step "Installing dnsmasq..."
apt-get update -qq 2>/dev/null
apt-get install -y dnsmasq 2>/dev/null

print_step "Stopping dnsmasq..."
systemctl stop dnsmasq 2>/dev/null || true

print_step "Creating clean configuration..."
mkdir -p /etc/dnsmasq.d
rm -f /etc/dnsmasq.d/platebridge-cameras.conf

cat > /etc/dnsmasq.d/platebridge-cameras.conf <<EOF
# PlateBridge Camera Network DHCP
# Interface to listen on
interface=$LAN_INTERFACE

# Only bind to specified interface
bind-interfaces

# DHCP range for cameras
dhcp-range=192.168.100.100,192.168.100.200,24h

# Gateway (this POD)
dhcp-option=option:router,192.168.100.1

# DNS servers
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4

# Domain
domain=cameras.local

# Enable verbose DHCP logging
log-dhcp
log-queries

# Ensure we respond to DHCP requests
dhcp-authoritative

# Increase lease file writes
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
EOF

print_success "Configuration created"

print_step "Testing configuration..."
if dnsmasq --test 2>&1 | grep -q "OK"; then
    print_success "Configuration valid"
else
    print_error "Configuration test failed:"
    dnsmasq --test 2>&1
    exit 1
fi

print_header "Step 4: Start dnsmasq"

print_step "Enabling dnsmasq service..."
systemctl enable dnsmasq

print_step "Starting dnsmasq..."
systemctl start dnsmasq
sleep 3

if systemctl is-active --quiet dnsmasq; then
    print_success "dnsmasq is RUNNING"
else
    print_error "dnsmasq FAILED to start!"
    echo ""
    journalctl -u dnsmasq --no-pager -n 30
    exit 1
fi

print_header "Step 5: Verify DHCP Server"

print_step "Checking if listening on port 67..."
if ss -ulnp 2>/dev/null | grep -q "dnsmasq.*:67"; then
    print_success "Listening on UDP port 67 (DHCP)"
    ss -ulnp | grep dnsmasq
else
    print_error "NOT listening on DHCP port!"
    print_step "Port status:"
    ss -ulnp | grep ":67" || echo "Nothing listening on port 67"
    exit 1
fi

print_step "Current DHCP leases:"
if [ -f /var/lib/misc/dnsmasq.leases ]; then
    if [ -s /var/lib/misc/dnsmasq.leases ]; then
        cat /var/lib/misc/dnsmasq.leases
    else
        echo "  (no leases yet)"
    fi
else
    echo "  (leases file not created yet)"
fi

print_header "✓ DHCP Server Fixed!"

echo ""
print_success "dnsmasq is now running and ready for DHCP requests"
echo ""
echo "Configuration:"
echo "  Interface:    $LAN_INTERFACE"
echo "  POD IP:       192.168.100.1"
echo "  DHCP Range:   192.168.100.100 - 192.168.100.200"
echo ""
echo "Next steps:"
echo "  1. Connect camera/device to $LAN_INTERFACE network"
echo "  2. Device should get IP automatically"
echo "  3. Monitor: sudo journalctl -u dnsmasq -f"
echo "  4. Check leases: cat /var/lib/misc/dnsmasq.leases"
echo ""
echo "To test, run: sudo journalctl -u dnsmasq -f"
echo "Then connect a device and watch for DHCP requests"
echo ""
