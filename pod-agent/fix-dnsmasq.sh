#!/bin/bash
#
# Fix dnsmasq service startup issues
# Resolves conflict with systemd-resolved on port 53
#
# Usage: sudo ./fix-dnsmasq.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ${GREEN}Fixing dnsmasq Service${BLUE}         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
   exit 1
fi

echo -e "${BLUE}[INFO]${NC} Checking dnsmasq status..."
if systemctl is-active --quiet dnsmasq; then
    echo -e "${GREEN}[OK]${NC} dnsmasq is already running!"
    systemctl status dnsmasq --no-pager -l
    exit 0
fi

echo -e "${YELLOW}[WARNING]${NC} dnsmasq is not running. Attempting to fix..."
echo ""

# Step 1: Stop conflicting services
echo -e "${BLUE}[STEP 1]${NC} Stopping systemd-resolved (conflicts with dnsmasq)..."
systemctl stop systemd-resolved
systemctl disable systemd-resolved

# Step 2: Fix resolv.conf
echo -e "${BLUE}[STEP 2]${NC} Fixing /etc/resolv.conf..."

# Remove immutable flag if set
chattr -i /etc/resolv.conf 2>/dev/null || true

# Remove symlink
if [ -L /etc/resolv.conf ]; then
    rm /etc/resolv.conf
fi

# Create static resolv.conf
cat > /etc/resolv.conf << EOF
# Static DNS configuration (systemd-resolved disabled)
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

# Make immutable
chattr +i /etc/resolv.conf

echo -e "${GREEN}[OK]${NC} DNS configuration fixed"

# Step 3: Test dnsmasq configuration
echo -e "${BLUE}[STEP 3]${NC} Testing dnsmasq configuration..."
if dnsmasq --test; then
    echo -e "${GREEN}[OK]${NC} dnsmasq configuration is valid"
else
    echo -e "${RED}[ERROR]${NC} dnsmasq configuration has errors:"
    dnsmasq --test 2>&1
    exit 1
fi

# Step 4: Start dnsmasq
echo -e "${BLUE}[STEP 4]${NC} Starting dnsmasq..."
systemctl start dnsmasq
sleep 2

# Step 5: Check status
if systemctl is-active --quiet dnsmasq; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ dnsmasq Fixed and Running!       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    systemctl status dnsmasq --no-pager -l
    echo ""
    echo -e "${GREEN}[SUCCESS]${NC} You can now:"
    echo "  - View DHCP leases: cat /var/lib/misc/dnsmasq.leases"
    echo "  - View logs: sudo journalctl -u dnsmasq -f"
    echo "  - Check status: sudo systemctl status dnsmasq"
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ✗ dnsmasq Failed to Start           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${RED}[ERROR]${NC} dnsmasq failed to start. Showing logs:"
    echo ""
    journalctl -u dnsmasq -n 50 --no-pager
    echo ""
    echo -e "${YELLOW}Common Issues:${NC}"
    echo "  1. Port 53 still in use by another service"
    echo "  2. Configuration syntax error"
    echo "  3. Network interface not ready"
    echo ""
    echo -e "${YELLOW}Check:${NC}"
    echo "  sudo ss -tulpn | grep :53"
    echo "  sudo dnsmasq --test"
    echo "  cat /etc/dnsmasq.d/platebridge-cameras.conf"
    exit 1
fi
