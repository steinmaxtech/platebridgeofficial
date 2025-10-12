#!/bin/bash

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
echo -e "${BLUE} Force Clean DHCP/DNS Services${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}►${NC} Checking what's using port 67..."
ss -ulnp | grep ":67 " || echo "Nothing found on port 67"
echo ""

echo -e "${GREEN}►${NC} Checking what's using port 53..."
ss -ulnp | grep ":53 " || echo "Nothing found on port 53"
echo ""

echo -e "${GREEN}►${NC} Stopping all DHCP/DNS services..."
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop systemd-resolved 2>/dev/null || true
systemctl stop dhcpd 2>/dev/null || true
systemctl stop isc-dhcp-server 2>/dev/null || true

echo -e "${GREEN}►${NC} Killing any remaining processes..."
killall -9 dnsmasq 2>/dev/null || true
killall -9 systemd-resolve 2>/dev/null || true
killall -9 dhcpd 2>/dev/null || true

sleep 2

echo -e "${GREEN}►${NC} Checking ports again..."
if ss -ulnp | grep -E ":(67|53) "; then
    echo -e "${RED}✗${NC} Still have processes on ports 53 or 67:"
    ss -ulnp | grep -E ":(67|53) "
    echo ""
    echo "Run this to see what's holding them:"
    echo "  sudo lsof -i :67"
    echo "  sudo lsof -i :53"
else
    echo -e "${GREEN}✓${NC} Ports 53 and 67 are clear!"
fi

echo ""
echo -e "${GREEN}✓${NC} Cleanup complete. Now run:"
echo "  sudo bash /opt/platebridge-pod/fix-dhcp-enable.sh enp1s0"
