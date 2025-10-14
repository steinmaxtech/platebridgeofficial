#!/bin/bash

# Basic Network Interface Test
# Tests if the interface can provide DHCP at all

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}▶${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    print_error "Run as root: sudo $0"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE} Basic Network Diagnostics${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

# Show all interfaces
print_step "All network interfaces:"
ip link show | grep -E "^[0-9]+:" | sed 's/^/  /'
echo ""

# Show IPs
print_step "Interface IP addresses:"
ip -4 addr show | grep -E "inet " | sed 's/^/  /'
echo ""

# Find camera interface
LAN_INTERFACE=""
read -p "Enter camera LAN interface name (e.g., eth1, enp1s0): " LAN_INTERFACE

if [ -z "$LAN_INTERFACE" ]; then
    print_error "No interface specified"
    exit 1
fi

echo ""
print_step "Testing interface: $LAN_INTERFACE"
echo ""

# Check if exists
if ! ip link show $LAN_INTERFACE &>/dev/null; then
    print_error "Interface $LAN_INTERFACE does not exist!"
    print_step "Available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}'
    exit 1
fi

# Check state
STATE=$(ip link show $LAN_INTERFACE | grep -oP '(?<=state )[^ ]+')
echo "Current state: $STATE"

if [ "$STATE" != "UP" ]; then
    print_step "Bringing interface UP..."
    ip link set $LAN_INTERFACE up
    sleep 2
    STATE=$(ip link show $LAN_INTERFACE | grep -oP '(?<=state )[^ ]+')
    echo "New state: $STATE"
fi

# Check if it has an IP
CURRENT_IP=$(ip -4 addr show $LAN_INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -n "$CURRENT_IP" ]; then
    print_success "Has IP: $CURRENT_IP"
else
    print_step "No IP, assigning 192.168.1.1..."
    ip addr flush dev $LAN_INTERFACE
    ip addr add 192.168.1.1/24 dev $LAN_INTERFACE
    CURRENT_IP="192.168.1.1"
fi

echo ""
print_step "Interface details:"
ip addr show $LAN_INTERFACE
echo ""

# Check link status
if command -v ethtool &> /dev/null; then
    print_step "Physical link status:"
    ethtool $LAN_INTERFACE | grep -E "Link detected|Speed|Duplex"
else
    print_step "Installing ethtool..."
    apt-get update -qq && apt-get install -y ethtool
    print_step "Physical link status:"
    ethtool $LAN_INTERFACE | grep -E "Link detected|Speed|Duplex"
fi

echo ""
LINK_DETECTED=$(ethtool $LAN_INTERFACE 2>/dev/null | grep "Link detected" | grep -o "yes\|no")

if [ "$LINK_DETECTED" = "no" ]; then
    print_error "NO PHYSICAL LINK DETECTED!"
    echo ""
    echo "This means:"
    echo "  • Nothing is physically connected to this port"
    echo "  • Cable is bad"
    echo "  • Device on other end is powered off"
    echo "  • Wrong port (check you're using the right interface)"
    echo ""
    echo "Check:"
    echo "  1. Is cable plugged in to THIS port?"
    echo "  2. Is PoE switch powered on?"
    echo "  3. Are switch port lights on?"
    echo "  4. Try different cable"
    echo "  5. Try plugging laptop directly (no switch)"
    exit 1
fi

print_success "Physical link detected!"
echo ""

# Check for layer 2 traffic
print_step "Watching for ANY network traffic (15 seconds)..."
echo "Connect device now if not connected..."
echo ""

if command -v tcpdump &> /dev/null; then
    timeout 15 tcpdump -i $LAN_INTERFACE -e -n 2>/dev/null | head -20 &
    TCPDUMP_PID=$!
    wait $TCPDUMP_PID 2>/dev/null

    echo ""
    if [ $? -eq 124 ]; then
        print_success "Timeout (normal)"
    fi
else
    print_step "Installing tcpdump..."
    apt-get install -y tcpdump
    print_step "Watching traffic..."
    timeout 15 tcpdump -i $LAN_INTERFACE -e -n 2>/dev/null | head -20
fi

echo ""
print_step "Checking ARP table..."
ip neighbor show dev $LAN_INTERFACE

echo ""
print_step "Testing broadcast ping..."
ping -I $LAN_INTERFACE -b -c 3 192.168.1.255 2>&1 | grep "bytes from" || echo "No responses"

echo ""
echo "═══════════════════════════════════════"
print_step "DHCP Server Check"
echo "═══════════════════════════════════════"
echo ""

# Check if dnsmasq installed
if ! command -v dnsmasq &> /dev/null; then
    print_step "Installing dnsmasq..."
    apt-get update -qq && apt-get install -y dnsmasq
fi

# Simple dnsmasq config
print_step "Creating minimal DHCP config..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/test.conf <<EOF
interface=$LAN_INTERFACE
bind-interfaces
dhcp-range=192.168.1.100,192.168.1.200,12h
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,8.8.8.8
log-dhcp
log-queries
EOF

print_step "Testing config..."
if dnsmasq --test 2>&1 | grep -q "OK"; then
    print_success "Config valid"
else
    print_error "Config error:"
    dnsmasq --test 2>&1
    exit 1
fi

# Stop conflicting services
print_step "Stopping conflicting services..."
systemctl stop systemd-resolved 2>/dev/null || true

# Start dnsmasq
print_step "Starting dnsmasq..."
systemctl stop dnsmasq 2>/dev/null || true
systemctl start dnsmasq

sleep 2

if systemctl is-active --quiet dnsmasq; then
    print_success "dnsmasq running"
else
    print_error "dnsmasq failed!"
    journalctl -u dnsmasq --no-pager -n 20
    exit 1
fi

# Check if listening
if ss -ulnp 2>/dev/null | grep -q "dnsmasq.*:67"; then
    print_success "DHCP server listening on port 67"
else
    print_error "NOT listening on DHCP port!"
    ss -ulnp | grep dnsmasq || echo "dnsmasq not in port list"
fi

echo ""
echo "═══════════════════════════════════════"
print_step "MONITORING FOR DHCP REQUESTS"
echo "═══════════════════════════════════════"
echo ""
echo "Now connect your device (computer/camera)"
echo "Or if already connected, disconnect and reconnect"
echo ""
echo "Watching for 60 seconds... Press Ctrl+C to stop"
echo ""

# Watch both logs and packets
(journalctl -u dnsmasq -f --no-pager | grep --line-buffered -i dhcp) &
LOG_PID=$!

timeout 60 tcpdump -i $LAN_INTERFACE -vv port 67 or port 68 2>/dev/null &
DUMP_PID=$!

trap "kill $LOG_PID $DUMP_PID 2>/dev/null; exit" INT TERM
wait $LOG_PID 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════"
echo ""
print_step "Check results:"
echo ""
echo "DHCP leases issued:"
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || echo "  (none)"
echo ""
echo "ARP table (devices seen):"
ip neighbor show dev $LAN_INTERFACE
echo ""
echo "═══════════════════════════════════════"
echo ""
echo "If still no DHCP:"
echo ""
echo "1. PHYSICAL ISSUE:"
echo "   • Wrong port on POD"
echo "   • Bad cable"
echo "   • PoE switch not working"
echo "   • Check switch lights"
echo ""
echo "2. CLIENT ISSUE:"
echo "   • Device not set to DHCP"
echo "   • Device network adapter disabled"
echo "   • Try different device"
echo ""
echo "3. POD ISSUE:"
echo "   • Wrong interface specified"
echo "   • Try other interface: $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp)' | tr '\n' ' ')"
echo ""
