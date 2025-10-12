#!/bin/bash

# Fix dnsmasq to actually enable DHCP server

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${BLUE} Fix dnsmasq DHCP Server${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

# Get interface
if [ -n "$1" ]; then
    IFACE="$1"
else
    echo "Available interfaces:"
    ip -4 addr show | grep -E "^[0-9]+: " | awk -F': ' '{print "  " $2}'
    echo ""
    read -p "Enter camera LAN interface (e.g., eth1): " IFACE
fi

if [ -z "$IFACE" ]; then
    echo -e "${RED}No interface specified${NC}"
    exit 1
fi

echo -e "${GREEN}►${NC} Using interface: $IFACE"
echo ""

# Configure interface first
echo -e "${GREEN}►${NC} Configuring interface..."
ip link set $IFACE up
ip addr flush dev $IFACE
ip addr add 192.168.100.1/24 dev $IFACE
echo -e "${GREEN}✓${NC} Interface configured"
echo ""

# Stop dnsmasq
echo -e "${GREEN}►${NC} Stopping dnsmasq..."
systemctl stop dnsmasq
sleep 2

# Backup main config
if [ -f /etc/dnsmasq.conf ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
fi

# Create minimal main config
echo -e "${GREEN}►${NC} Creating main config..."
cat > /etc/dnsmasq.conf <<EOF
# Main dnsmasq configuration
# Include all files in /etc/dnsmasq.d/
conf-dir=/etc/dnsmasq.d/,*.conf
EOF

# Create DHCP config
echo -e "${GREEN}►${NC} Creating DHCP config..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/platebridge-cameras.conf <<EOF
# PlateBridge Camera Network DHCP Server

# Bind only to camera interface
interface=$IFACE
bind-interfaces

# Don't read /etc/hosts
no-hosts

# Don't read /etc/resolv.conf
no-resolv

# Upstream DNS servers (for DNS queries from this server)
server=8.8.8.8
server=8.8.4.4

# DHCP Configuration
dhcp-range=$IFACE,192.168.100.100,192.168.100.200,24h

# DHCP Options
dhcp-option=$IFACE,option:router,192.168.100.1
dhcp-option=$IFACE,option:dns-server,192.168.100.1
dhcp-option=$IFACE,option:netmask,255.255.255.0

# Domain
domain=cameras.local

# Be authoritative
dhcp-authoritative

# Logging
log-dhcp
log-queries

# Lease file
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
EOF

echo -e "${GREEN}✓${NC} Configuration created"
echo ""

# Test config
echo -e "${GREEN}►${NC} Testing configuration..."
if dnsmasq --test 2>&1 | grep -q "OK"; then
    echo -e "${GREEN}✓${NC} Configuration is valid"
else
    echo -e "${RED}✗${NC} Configuration error:"
    dnsmasq --test 2>&1
    exit 1
fi
echo ""

# Start dnsmasq
echo -e "${GREEN}►${NC} Starting dnsmasq..."
systemctl start dnsmasq
sleep 3

# Check status
if ! systemctl is-active --quiet dnsmasq; then
    echo -e "${RED}✗${NC} dnsmasq failed to start!"
    echo ""
    journalctl -u dnsmasq --no-pager -n 20
    exit 1
fi

echo -e "${GREEN}✓${NC} dnsmasq is running"
echo ""

# Verify DHCP port
echo -e "${GREEN}►${NC} Checking DHCP server..."
sleep 2

if ss -ulnp | grep -q "dnsmasq.*:67"; then
    echo -e "${GREEN}✓${NC} DHCP server listening on port 67!"
    echo ""
    ss -ulnp | grep dnsmasq
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ SUCCESS! DHCP Server is Running${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    echo "Configuration:"
    echo "  Interface:    $IFACE"
    echo "  POD IP:       192.168.100.1/24"
    echo "  DHCP Range:   192.168.100.100 - 192.168.100.200"
    echo ""
    echo "Test it:"
    echo "  1. Connect device to $IFACE network"
    echo "  2. Monitor: sudo journalctl -u dnsmasq -f"
    echo "  3. Check leases: cat /var/lib/misc/dnsmasq.leases"
    echo ""
else
    echo -e "${RED}✗${NC} Still not listening on port 67!"
    echo ""
    echo "Port status:"
    ss -ulnp | grep dnsmasq || echo "dnsmasq not in port list"
    echo ""
    echo "Logs:"
    journalctl -u dnsmasq --no-pager -n 20
    exit 1
fi
