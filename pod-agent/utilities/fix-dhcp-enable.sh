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

# Get interface - MUST be provided as argument
if [ -n "$1" ] && [ "$1" != "lo" ]; then
    IFACE="$1"
else
    echo -e "${YELLOW}Available network interfaces:${NC}"
    ip -4 addr show | grep -E "^[0-9]+: " | awk -F': ' '{print "  " $2}' | grep -v lo
    echo ""
    echo -e "${RED}ERROR: You must specify a network interface (not lo)${NC}"
    echo ""
    echo "Usage: $0 <interface>"
    echo "Example: $0 eth1"
    echo "Example: $0 enp3s0"
    exit 1
fi

# Validate interface exists and is not lo
if ! ip link show "$IFACE" &>/dev/null; then
    echo -e "${RED}ERROR: Interface '$IFACE' does not exist${NC}"
    exit 1
fi

if [ "$IFACE" = "lo" ]; then
    echo -e "${RED}ERROR: Cannot use loopback interface 'lo'${NC}"
    exit 1
fi

echo -e "${GREEN}►${NC} Using interface: $IFACE"
echo ""

# Configure interface first
echo -e "${GREEN}►${NC} Configuring interface..."
ip link set $IFACE up
ip addr flush dev $IFACE
ip addr add 192.168.1.1/24 dev $IFACE

# Verify
if ! ip addr show $IFACE | grep -q "192.168.1.1"; then
    echo -e "${RED}✗${NC} Failed to set IP on $IFACE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Interface configured: 192.168.1.1/24"
ip addr show $IFACE | grep "inet "
echo ""

# Stop dnsmasq
echo -e "${GREEN}►${NC} Stopping dnsmasq..."
systemctl stop dnsmasq
sleep 2

# Backup main config
if [ -f /etc/dnsmasq.conf ] && [ ! -f /etc/dnsmasq.conf.backup ]; then
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    echo -e "${GREEN}✓${NC} Backed up original config"
fi

# Create minimal main config
echo -e "${GREEN}►${NC} Creating main config..."
cat > /etc/dnsmasq.conf <<EOF
# Main dnsmasq configuration
# Include all files in /etc/dnsmasq.d/
conf-dir=/etc/dnsmasq.d/,*.conf

# Don't use /etc/hosts
no-hosts

# Don't poll /etc/resolv.conf
no-poll
EOF

# Create DHCP config
echo -e "${GREEN}►${NC} Creating DHCP config..."
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/platebridge-cameras.conf <<EOF
# PlateBridge Camera Network DHCP Server

# ONLY bind to camera interface - NOT lo
interface=$IFACE
bind-interfaces

# Explicitly exclude loopback
except-interface=lo

# Don't read /etc/resolv.conf for DNS
no-resolv

# Upstream DNS servers
server=8.8.8.8
server=8.8.4.4

# DHCP Configuration
dhcp-range=$IFACE,192.168.1.100,192.168.1.200,24h

# DHCP Options
dhcp-option=$IFACE,3,192.168.1.1
dhcp-option=$IFACE,6,192.168.1.1
dhcp-option=$IFACE,1,255.255.255.0

# Domain
domain=cameras.local
local=/cameras.local/

# Be authoritative
dhcp-authoritative

# Logging
log-dhcp
log-queries

# Lease file
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
EOF

echo -e "${GREEN}✓${NC} Configuration created"
cat /etc/dnsmasq.d/platebridge-cameras.conf
echo ""

# Test config
echo -e "${GREEN}►${NC} Testing configuration..."
TEST_OUTPUT=$(dnsmasq --test 2>&1)
if echo "$TEST_OUTPUT" | grep -q "syntax check OK"; then
    echo -e "${GREEN}✓${NC} Configuration is valid"
else
    echo -e "${RED}✗${NC} Configuration error:"
    echo "$TEST_OUTPUT"
    exit 1
fi
echo ""

# Start dnsmasq
echo -e "${GREEN}►${NC} Starting dnsmasq..."
systemctl enable dnsmasq
systemctl start dnsmasq
sleep 3

# Check status
if ! systemctl is-active --quiet dnsmasq; then
    echo -e "${RED}✗${NC} dnsmasq failed to start!"
    echo ""
    echo "Status:"
    systemctl status dnsmasq --no-pager -l
    echo ""
    echo "Logs:"
    journalctl -u dnsmasq --no-pager -n 30
    exit 1
fi

echo -e "${GREEN}✓${NC} dnsmasq is running"
echo ""

# Verify DHCP port
echo -e "${GREEN}►${NC} Checking DHCP server..."
sleep 2

echo "All UDP ports dnsmasq is listening on:"
ss -ulnp | grep dnsmasq
echo ""

if ss -ulnp | grep -q "dnsmasq.*:67 "; then
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ SUCCESS! DHCP Server is Running${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo ""
    echo "Configuration:"
    echo "  Interface:    $IFACE"
    echo "  POD IP:       192.168.1.1/24"
    echo "  DHCP Range:   192.168.1.100 - 192.168.1.200"
    echo ""
    echo "Monitor DHCP requests:"
    echo "  sudo journalctl -u dnsmasq -f"
    echo ""
    echo "Check leases:"
    echo "  cat /var/lib/misc/dnsmasq.leases"
    echo ""
    echo "Next steps:"
    echo "  1. Connect camera to $IFACE network"
    echo "  2. Camera should get IP 192.168.1.100-200"
    echo "  3. Find camera: sudo nmap -sn 192.168.1.0/24"
    echo ""
else
    echo -e "${RED}✗${NC} Still not listening on port 67!"
    echo ""
    echo "Logs:"
    journalctl -u dnsmasq --no-pager -n 30
    echo ""
    echo "Try running manually to see errors:"
    echo "  sudo dnsmasq --no-daemon --log-dhcp --interface=$IFACE"
    exit 1
fi
