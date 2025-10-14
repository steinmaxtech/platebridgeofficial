#!/bin/bash

# Debug why dnsmasq isn't listening on port 67

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
echo -e "${BLUE} Debugging DHCP Port Issue${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}1. Check if dnsmasq process is running:${NC}"
ps aux | grep dnsmasq | grep -v grep
echo ""

echo -e "${GREEN}2. Check dnsmasq service status:${NC}"
systemctl status dnsmasq --no-pager -l | head -20
echo ""

echo -e "${GREEN}3. Check what's using port 67:${NC}"
ss -ulnp | grep ":67 " || echo "Nothing listening on port 67"
echo ""

echo -e "${GREEN}4. Check for any errors in logs:${NC}"
journalctl -u dnsmasq --no-pager -n 30 | tail -20
echo ""

echo -e "${GREEN}5. Test dnsmasq config:${NC}"
dnsmasq --test
echo ""

echo -e "${GREEN}6. Check dnsmasq config files:${NC}"
echo "Main config:"
if [ -f /etc/dnsmasq.conf ]; then
    grep -v "^#" /etc/dnsmasq.conf | grep -v "^$" | head -10
else
    echo "  (not found)"
fi
echo ""
echo "Camera config:"
if [ -f /etc/dnsmasq.d/platebridge-cameras.conf ]; then
    cat /etc/dnsmasq.d/platebridge-cameras.conf
else
    echo "  (not found)"
fi
echo ""

echo -e "${GREEN}7. Check if interface exists and is UP:${NC}"
read -p "Enter interface name (e.g., eth1): " IFACE
if [ -n "$IFACE" ]; then
    ip addr show $IFACE 2>/dev/null || echo "Interface not found"
fi
echo ""

echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW} Attempting Fix${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""

# Stop everything
echo "Stopping dnsmasq..."
systemctl stop dnsmasq
killall dnsmasq 2>/dev/null || true
sleep 2

# Check if anything else on port 67
echo "Checking port 67..."
if ss -ulnp | grep -q ":67 "; then
    echo -e "${RED}Something else is using port 67:${NC}"
    ss -ulnp | grep ":67 "
    echo ""
    echo "Kill it? (yes/no)"
    read KILL
    if [ "$KILL" = "yes" ]; then
        PID=$(ss -ulnp | grep ":67 " | grep -oP 'pid=\K[0-9]+' | head -1)
        if [ -n "$PID" ]; then
            echo "Killing process $PID..."
            kill -9 $PID
            sleep 1
        fi
    fi
fi

# Try running dnsmasq in foreground to see errors
echo ""
echo -e "${GREEN}Running dnsmasq in foreground (Ctrl+C to stop):${NC}"
echo "This will show real-time errors..."
echo ""
sleep 2

dnsmasq --no-daemon --log-queries --log-dhcp
