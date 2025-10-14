#!/bin/bash

################################################################################
# DHCP Diagnostics - Find out why DHCP isn't working
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LAN_INTERFACE="enp1s0"
LAN_IP="192.168.1.1"

echo -e "${GREEN}=== DHCP Diagnostic Report ===${NC}"
echo ""

# 1. Check if dnsmasq is installed
echo "1. dnsmasq installation:"
if command -v dnsmasq &> /dev/null; then
    echo -e "   ${GREEN}✓ Installed: $(dnsmasq --version | head -1)${NC}"
else
    echo -e "   ${RED}✗ NOT INSTALLED${NC}"
    echo "   Fix: sudo apt-get install -y dnsmasq"
fi
echo ""

# 2. Check if dnsmasq is running
echo "2. dnsmasq service:"
if systemctl is-active --quiet dnsmasq; then
    echo -e "   ${GREEN}✓ Running${NC}"
else
    echo -e "   ${RED}✗ NOT RUNNING${NC}"
    echo "   Fix: sudo systemctl start dnsmasq"
fi
echo ""

# 3. Check if listening on port 67
echo "3. DHCP port (67):"
if ss -ulnp 2>/dev/null | grep -q ":67"; then
    DHCP_PROC=$(ss -ulnp 2>/dev/null | grep ":67" | awk '{print $7}')
    echo -e "   ${GREEN}✓ Port 67 open: $DHCP_PROC${NC}"
else
    echo -e "   ${RED}✗ Nothing listening on port 67${NC}"
    echo "   This is why DHCP isn't working!"
fi
echo ""

# 4. Check DNS port
echo "4. DNS port (53):"
if ss -ulnp 2>/dev/null | grep -q ":53"; then
    DNS_PROC=$(ss -ulnp 2>/dev/null | grep ":53" | awk '{print $7}')
    echo -e "   ${GREEN}✓ Port 53 open: $DNS_PROC${NC}"
    if echo "$DNS_PROC" | grep -q "systemd-resolved"; then
        echo -e "   ${YELLOW}⚠ systemd-resolved is using port 53 (may conflict)${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ Nothing on port 53${NC}"
fi
echo ""

# 5. Check interface exists
echo "5. Network interface ($LAN_INTERFACE):"
if ip link show $LAN_INTERFACE &>/dev/null; then
    echo -e "   ${GREEN}✓ Interface exists${NC}"

    # Check if UP
    if ip link show $LAN_INTERFACE | grep -q "UP"; then
        echo -e "   ${GREEN}✓ Interface is UP${NC}"
    else
        echo -e "   ${RED}✗ Interface is DOWN${NC}"
        echo "   Fix: sudo ip link set $LAN_INTERFACE up"
    fi

    # Check if has IP
    if ip addr show $LAN_INTERFACE | grep -q "inet $LAN_IP"; then
        echo -e "   ${GREEN}✓ Has IP: $LAN_IP${NC}"
    else
        CURRENT_IP=$(ip addr show $LAN_INTERFACE | grep "inet " | awk '{print $2}' || echo "none")
        echo -e "   ${RED}✗ Wrong/missing IP: $CURRENT_IP${NC}"
        echo "   Fix: sudo ip addr add $LAN_IP/24 dev $LAN_INTERFACE"
    fi
else
    echo -e "   ${RED}✗ Interface $LAN_INTERFACE does not exist${NC}"
    echo "   Available interfaces:"
    ip link show | grep "^[0-9]" | awk -F': ' '{print "   - " $2}'
fi
echo ""

# 6. Check reverse path filtering
echo "6. Reverse path filtering (rp_filter):"
RP_ALL=$(sysctl -n net.ipv4.conf.all.rp_filter)
RP_IF=$(sysctl -n net.ipv4.conf.$LAN_INTERFACE.rp_filter 2>/dev/null || echo "N/A")
if [ "$RP_ALL" = "0" ] && [ "$RP_IF" = "0" ]; then
    echo -e "   ${GREEN}✓ Disabled (good for DHCP)${NC}"
else
    echo -e "   ${YELLOW}⚠ Enabled: all=$RP_ALL interface=$RP_IF${NC}"
    echo "   This can block DHCP packets!"
    echo "   Fix: sudo sysctl -w net.ipv4.conf.all.rp_filter=0"
    echo "        sudo sysctl -w net.ipv4.conf.$LAN_INTERFACE.rp_filter=0"
fi
echo ""

# 7. Check hardware offload
echo "7. Hardware offload:"
if command -v ethtool &> /dev/null && ip link show $LAN_INTERFACE &>/dev/null; then
    OFFLOADS=$(ethtool -k $LAN_INTERFACE 2>/dev/null | grep -E "^(tx-|rx-|generic-)" | grep "on$" | wc -l)
    if [ "$OFFLOADS" -gt 0 ]; then
        echo -e "   ${YELLOW}⚠ $OFFLOADS offload features enabled (can break DHCP)${NC}"
        echo "   Fix: sudo ethtool -K $LAN_INTERFACE rx off tx off gso off tso off gro off lro off"
    else
        echo -e "   ${GREEN}✓ Offload disabled${NC}"
    fi
else
    echo "   N/A (ethtool not installed or interface missing)"
fi
echo ""

# 8. Check firewall
echo "8. Firewall (iptables):"
if iptables -L INPUT -n 2>/dev/null | grep -q "67"; then
    echo -e "   ${GREEN}✓ DHCP rules present${NC}"
else
    echo -e "   ${YELLOW}⚠ No explicit DHCP rules found${NC}"
    echo "   May need to add: sudo iptables -A INPUT -p udp --dport 67 -j ACCEPT"
fi
echo ""

# 9. Check dnsmasq config
echo "9. dnsmasq configuration:"
if [ -f /etc/dnsmasq.conf ]; then
    echo "   Config file exists:"
    if grep -q "^interface=" /etc/dnsmasq.conf; then
        IF=$(grep "^interface=" /etc/dnsmasq.conf | cut -d= -f2)
        echo -e "   ${GREEN}✓ Interface set to: $IF${NC}"
    else
        echo -e "   ${RED}✗ No interface specified${NC}"
    fi

    if grep -q "^dhcp-range=" /etc/dnsmasq.conf; then
        RANGE=$(grep "^dhcp-range=" /etc/dnsmasq.conf | cut -d= -f2)
        echo -e "   ${GREEN}✓ DHCP range: $RANGE${NC}"
    else
        echo -e "   ${RED}✗ No DHCP range configured${NC}"
    fi
else
    echo -e "   ${RED}✗ Config file missing${NC}"
fi
echo ""

# 10. Check recent logs
echo "10. Recent dnsmasq errors:"
if systemctl is-active --quiet dnsmasq; then
    ERRORS=$(journalctl -u dnsmasq --since "5 minutes ago" 2>/dev/null | grep -i "error\|failed\|warning" | tail -3)
    if [ -z "$ERRORS" ]; then
        echo -e "   ${GREEN}✓ No recent errors${NC}"
    else
        echo -e "   ${YELLOW}⚠ Recent issues:${NC}"
        echo "$ERRORS" | sed 's/^/   /'
    fi
else
    echo "   Service not running"
fi
echo ""

# Summary
echo -e "${GREEN}=== Summary ===${NC}"
echo ""

# Count problems
PROBLEMS=0

! systemctl is-active --quiet dnsmasq && PROBLEMS=$((PROBLEMS + 1))
! ss -ulnp 2>/dev/null | grep -q ":67" && PROBLEMS=$((PROBLEMS + 1))
! ip addr show $LAN_INTERFACE 2>/dev/null | grep -q "inet $LAN_IP" && PROBLEMS=$((PROBLEMS + 1))
[ "$RP_ALL" != "0" ] && PROBLEMS=$((PROBLEMS + 1))

if [ $PROBLEMS -eq 0 ]; then
    echo -e "${GREEN}Everything looks good!${NC}"
    echo ""
    echo "If cameras still aren't getting IPs:"
    echo "1. Check camera is set to DHCP mode"
    echo "2. Power cycle the camera"
    echo "3. Monitor with: sudo tcpdump -i $LAN_INTERFACE -n port 67 or port 68"
    echo "4. Check leases: cat /var/lib/misc/dnsmasq.leases"
else
    echo -e "${RED}Found $PROBLEMS issue(s) that need fixing${NC}"
    echo ""
    echo "Run this to fix most issues:"
    echo "  sudo ./fix-dhcp-simple.sh"
fi
