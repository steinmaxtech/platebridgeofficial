#!/bin/bash

# PlateBridge POD - DHCP/DNSmasq Complete Diagnostics
# Diagnoses and fixes all DHCP server issues

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

print_step() { echo -e "${GREEN}▶${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

print_header "PlateBridge POD - DHCP Diagnostics"

# Detect camera LAN interface
print_step "Detecting network interfaces..."
echo "Available interfaces:"
ip -4 addr show | grep -E "^[0-9]+: |inet " | sed 's/^/  /'
echo ""

LAN_INTERFACE=""
LAN_IP=""
for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|enp|ens|eno)'); do
    iface_ip=$(ip addr show $iface 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [[ "$iface_ip" == 192.168.100.* ]]; then
        LAN_INTERFACE="$iface"
        LAN_IP="$iface_ip"
        print_success "Found camera LAN: $LAN_INTERFACE ($LAN_IP)"
        break
    fi
done

if [ -z "$LAN_INTERFACE" ]; then
    print_warning "Could not auto-detect camera interface (192.168.100.x)"
    read -p "Enter camera LAN interface (e.g., eth1): " LAN_INTERFACE
    if [ -z "$LAN_INTERFACE" ]; then
        print_error "No interface specified"
        exit 1
    fi
    LAN_IP=$(ip addr show $LAN_INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 || echo "")
fi

# Check interface status
print_header "Interface Status"

if ! ip link show $LAN_INTERFACE &>/dev/null; then
    print_error "Interface $LAN_INTERFACE does not exist!"
    exit 1
fi

STATE=$(ip link show $LAN_INTERFACE | grep -oP '(?<=state )[^ ]+')
print_step "State: $STATE"

if [ "$STATE" != "UP" ]; then
    print_warning "Interface DOWN, bringing UP..."
    ip link set $LAN_INTERFACE up
    sleep 2
    STATE=$(ip link show $LAN_INTERFACE | grep -oP '(?<=state )[^ ]+')
    print_step "New state: $STATE"
fi

if [ -z "$LAN_IP" ]; then
    print_error "No IP address on $LAN_INTERFACE!"
    print_step "Assigning 192.168.100.1..."
    ip addr add 192.168.100.1/24 dev $LAN_INTERFACE || true
    LAN_IP="192.168.100.1"
fi

print_success "Interface OK: $LAN_INTERFACE = $LAN_IP"

# Check physical connection
print_step "Checking physical connection..."
if command -v ethtool &> /dev/null; then
    LINK=$(ethtool $LAN_INTERFACE 2>/dev/null | grep "Link detected" || echo "unknown")
    echo "  $LINK"
    if [[ "$LINK" == *"no"* ]]; then
        print_error "No link detected - cable not connected!"
    fi
else
    print_warning "ethtool not installed (run: apt install ethtool)"
fi

# Check dnsmasq installation
print_header "DHCP Server (dnsmasq)"

if ! command -v dnsmasq &> /dev/null; then
    print_error "dnsmasq not installed"
    print_step "Installing..."
    apt-get update -qq && apt-get install -y dnsmasq
fi

# Check configuration
CONF="/etc/dnsmasq.d/platebridge-cameras.conf"
if [ ! -f "$CONF" ]; then
    print_warning "Config missing, creating..."
    mkdir -p /etc/dnsmasq.d
    cat > $CONF <<EOF
# PlateBridge Camera DHCP
interface=$LAN_INTERFACE
bind-interfaces
dhcp-range=192.168.100.100,192.168.100.200,24h
dhcp-option=option:dns-server,192.168.100.1
dhcp-option=option:router,192.168.100.1
log-dhcp
log-queries
EOF
    print_success "Config created"
else
    print_success "Config exists"
    echo "Settings:"
    cat $CONF | grep -v "^#" | grep -v "^$" | sed 's/^/  /'
fi

# Check for conflicts
print_header "Checking Conflicts"

print_step "Port 53 (DNS)..."
if ss -ulnp 2>/dev/null | grep -q ":53 "; then
    PORT53=$(ss -ulnp 2>/dev/null | grep ":53 " | head -1)
    if echo "$PORT53" | grep -q systemd-resolved; then
        print_warning "systemd-resolved using port 53"
        print_step "Disabling stub listener..."
        mkdir -p /etc/systemd/resolved.conf.d
        cat > /etc/systemd/resolved.conf.d/no-stub.conf <<EOF
[Resolve]
DNSStubListener=no
EOF
        systemctl restart systemd-resolved
        sleep 1
    fi
else
    print_success "Port 53 available"
fi

print_step "Port 67 (DHCP)..."
if ss -ulnp 2>/dev/null | grep -q ":67 "; then
    print_success "Port 67 in use (dnsmasq running)"
else
    print_warning "Port 67 not in use (dnsmasq not running)"
fi

# Test configuration
print_step "Testing dnsmasq config..."
if dnsmasq --test 2>&1 | grep -q "OK"; then
    print_success "Configuration valid"
else
    print_error "Configuration has errors:"
    dnsmasq --test 2>&1
    exit 1
fi

# Restart dnsmasq
print_header "Restarting DHCP Server"

print_step "Stopping dnsmasq..."
systemctl stop dnsmasq 2>/dev/null || true

print_step "Starting dnsmasq..."
systemctl enable dnsmasq
systemctl start dnsmasq
sleep 3

if systemctl is-active --quiet dnsmasq; then
    print_success "dnsmasq running"
else
    print_error "dnsmasq failed to start!"
    journalctl -u dnsmasq --no-pager -n 20
    exit 1
fi

# Check listening
print_step "Checking if listening..."
if ss -ulnp 2>/dev/null | grep -q "dnsmasq.*:67"; then
    print_success "Listening on UDP port 67 (DHCP)"
else
    print_error "NOT listening on DHCP port!"
fi

# Check leases
print_header "DHCP Leases"

LEASES="/var/lib/misc/dnsmasq.leases"
if [ -f "$LEASES" ] && [ -s "$LEASES" ]; then
    print_success "Active leases:"
    cat $LEASES | while read line; do
        echo "  $line"
    done
else
    print_warning "No leases yet (no cameras have requested IPs)"
fi

# Monitor for requests
print_header "Monitoring for DHCP Requests"

print_success "Watching for camera DHCP activity..."
echo ""
print_step "Connect/power cycle your camera now"
print_step "Press Ctrl+C to stop monitoring"
echo ""
echo "Watching logs and network traffic..."
echo ""

# Watch in background
(journalctl -u dnsmasq -f --no-pager 2>/dev/null | grep --line-buffered -iE "dhcp") &
LOG_PID=$!

# Also tcpdump if available
if command -v tcpdump &> /dev/null; then
    timeout 120 tcpdump -i $LAN_INTERFACE -n -e port 67 or port 68 2>/dev/null &
    DUMP_PID=$!
fi

# Wait
trap "kill $LOG_PID $DUMP_PID 2>/dev/null; exit" INT TERM
wait $LOG_PID 2>/dev/null

print_header "Troubleshooting Tips"
echo ""
echo "If camera still not getting IP:"
echo ""
echo "1. Physical Check:"
echo "   • Camera powered? (check PoE lights on switch)"
echo "   • Cable good? (swap cable to test)"
echo "   • Connected to $LAN_INTERFACE? (not WAN)"
echo "   • Link detected: ethtool $LAN_INTERFACE | grep Link"
echo ""
echo "2. Camera Check:"
echo "   • Set to DHCP mode (not static IP)"
echo "   • Factory reset camera"
echo "   • Check camera docs for DHCP setup"
echo "   • Try different camera if available"
echo ""
echo "3. Network Check:"
echo "   • Watch packets: tcpdump -i $LAN_INTERFACE -vvv port 67 or port 68"
echo "   • Check ARP: ip neighbor show dev $LAN_INTERFACE"
echo "   • Try pinging broadcast: ping -I $LAN_INTERFACE -b 192.168.100.255"
echo ""
echo "4. Test with Static IP:"
echo "   • Set camera to: 192.168.100.50"
echo "   • Ping from POD: ping 192.168.100.50"
echo "   • Access web UI: http://192.168.100.50"
echo ""
echo "Useful commands:"
echo "  systemctl status dnsmasq"
echo "  journalctl -u dnsmasq -f"
echo "  cat /var/lib/misc/dnsmasq.leases"
echo "  tcpdump -i $LAN_INTERFACE port 67 or port 68"
echo "  ip addr show $LAN_INTERFACE"
echo "  ip neighbor show dev $LAN_INTERFACE"
echo ""
