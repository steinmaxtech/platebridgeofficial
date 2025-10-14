#!/bin/bash
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() { echo -e "${BLUE}╔══════════════════════════════════╗${NC}"; echo -e "${BLUE}║  ${GREEN}$1${NC}"; echo -e "${BLUE}╚══════════════════════════════════╝${NC}"; echo ""; }
print_step() { echo -e "${GREEN}➜${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

check_root() { [ "$EUID" -ne 0 ] && echo "Must run as root" && exit 1; }

main() {
    clear
    print_header "PlateBridge POD Final Lockdown"
    check_root
    
    print_step "Hardening kernel parameters..."
    cat > /etc/sysctl.d/99-platebridge-lockdown.conf << 'EOF'
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
vm.swappiness=10
net.ipv4.tcp_rfc1337=1
EOF
    sysctl -p /etc/sysctl.d/99-platebridge-lockdown.conf > /dev/null
    print_success "Kernel hardened"
    
    print_step "Creating monitoring script..."
    cat > /opt/platebridge/monitor-system.sh << 'EOF'
#!/bin/bash
echo "=== POD Health $(date) ==="
df -h | grep -E "Filesystem|/media/frigate|/$"
echo ""
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""
ip -brief addr
EOF
    chmod +x /opt/platebridge/monitor-system.sh
    print_success "Monitor script created"
    
    print_step "Creating backup script..."
    cat > /opt/platebridge/backup-config.sh << 'EOF'
#!/bin/bash
mkdir -p /opt/platebridge/backups
tar -czf /opt/platebridge/backups/config_$(date +%Y%m%d).tar.gz \
    /etc/netplan/01-platebridge-network.yaml \
    /etc/dnsmasq.d/ \
    /etc/iptables/ \
    /opt/platebridge/docker/.env \
    /opt/platebridge/frigate/config/ 2>/dev/null
echo "Backup created"
EOF
    chmod +x /opt/platebridge/backup-config.sh
    print_success "Backup script created"
    
    print_header "Lockdown Complete!"
    echo -e "${GREEN}✓ Kernel hardened${NC}"
    echo -e "${GREEN}✓ Scripts created${NC}"
    echo ""
    echo "Commands:"
    echo "  /opt/platebridge/monitor-system.sh"
    echo "  /opt/platebridge/backup-config.sh"
}

main
