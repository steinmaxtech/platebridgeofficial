#!/bin/bash

################################################################################
# Simple DHCP Fix - No BS Version
# This script sets up DHCP that actually works
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Simple DHCP Setup ===${NC}"
echo ""

# Configuration - CHANGE THESE IF NEEDED
LAN_INTERFACE="enp1s0"  # Your camera network interface
LAN_IP="192.168.1.1"
DHCP_START="192.168.1.100"
DHCP_END="192.168.1.200"

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run with sudo${NC}"
    exit 1
fi

echo "Step 1: Stop everything that might interfere"
systemctl stop systemd-resolved 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
killall dnsmasq 2>/dev/null || true
sleep 2

echo "Step 2: Install dnsmasq"
apt-get update -qq
apt-get install -y dnsmasq

echo "Step 3: Fix DNS resolution on the POD itself"
# Remove systemd-resolved's symlink
chattr -i /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf

# Create static DNS config
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Make it permanent
chattr +i /etc/resolv.conf

# Keep systemd-resolved disabled
systemctl disable systemd-resolved 2>/dev/null || true
systemctl mask systemd-resolved 2>/dev/null || true

echo "Step 4: Configure the LAN interface"
# Make sure interface has IP
ip addr flush dev $LAN_INTERFACE 2>/dev/null || true
ip addr add $LAN_IP/24 dev $LAN_INTERFACE 2>/dev/null || true
ip link set $LAN_INTERFACE up

# CRITICAL: Disable hardware offload (this breaks DHCP on many NICs)
ethtool -K $LAN_INTERFACE rx off tx off gso off tso off gro off lro off 2>/dev/null || true

echo "Step 5: Disable reverse path filtering (breaks DHCP)"
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.$LAN_INTERFACE.rp_filter=0

echo "Step 6: Create super simple dnsmasq config"
# Backup old config
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
rm -rf /etc/dnsmasq.d/* 2>/dev/null || true

# Create new simple config
cat > /etc/dnsmasq.conf << EOF
# Listen only on camera interface
interface=$LAN_INTERFACE
bind-interfaces

# DHCP settings
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
dhcp-option=option:router,$LAN_IP
dhcp-option=option:dns-server,8.8.8.8,8.8.4.4

# DNS settings
no-resolv
server=8.8.8.8
server=8.8.4.4

# Logging
log-dhcp
log-queries
EOF

echo "Step 7: Start dnsmasq"
systemctl enable dnsmasq
systemctl restart dnsmasq
sleep 2

echo ""
echo -e "${GREEN}=== Status Check ===${NC}"

# Check if running
if systemctl is-active --quiet dnsmasq; then
    echo -e "${GREEN}✓ dnsmasq is running${NC}"
else
    echo -e "${RED}✗ dnsmasq failed to start${NC}"
    echo "Logs:"
    journalctl -u dnsmasq -n 20 --no-pager
    exit 1
fi

# Check if listening
if ss -ulnp | grep -q ":67.*dnsmasq"; then
    echo -e "${GREEN}✓ Listening on port 67 (DHCP)${NC}"
else
    echo -e "${RED}✗ NOT listening on port 67${NC}"
fi

if ss -ulnp | grep -q ":53.*dnsmasq"; then
    echo -e "${GREEN}✓ Listening on port 53 (DNS)${NC}"
else
    echo -e "${RED}✗ NOT listening on port 53${NC}"
fi

# Check interface
if ip addr show $LAN_INTERFACE | grep -q "$LAN_IP"; then
    echo -e "${GREEN}✓ Interface $LAN_INTERFACE has IP $LAN_IP${NC}"
else
    echo -e "${RED}✗ Interface $LAN_INTERFACE missing IP${NC}"
fi

echo ""
echo -e "${GREEN}=== Next Steps ===${NC}"
echo "1. Plug in a camera to the $LAN_INTERFACE port"
echo "2. Watch for DHCP requests:"
echo "   sudo journalctl -u dnsmasq -f"
echo ""
echo "3. Or use tcpdump:"
echo "   sudo tcpdump -i $LAN_INTERFACE -n port 67 or port 68"
echo ""
echo "4. Check leases after camera connects:"
echo "   cat /var/lib/misc/dnsmasq.leases"
echo ""
echo -e "${YELLOW}If camera still doesn't get IP:${NC}"
echo "- Make sure camera is set to DHCP mode"
echo "- Try power cycling the camera"
echo "- Check camera LED status"
echo "- Try: sudo systemctl restart dnsmasq"
