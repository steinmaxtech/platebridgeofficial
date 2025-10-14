#!/bin/bash

################################################################################
# PlateBridge POD - Complete Installation Script
#
# This script installs and configures everything needed for a production POD:
# - Docker & Docker Compose
# - Dual-NIC network configuration
# - DHCP server for cameras
# - Frigate NVR
# - PlateBridge POD agent
# - Camera discovery
# - Systemd services
#
# Usage: sudo ./install-complete.sh
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
INSTALL_DIR="/opt/platebridge"
POD_USER="platebridge"
WAN_INTERFACE="enp3s0"  # Cellular/Internet connection
LAN_INTERFACE="enp1s0"  # Camera network
LAN_IP="192.168.100.1"
LAN_NETWORK="192.168.100.0/24"
DHCP_RANGE_START="192.168.100.100"
DHCP_RANGE_END="192.168.100.200"
SSH_PORT="22"  # Will be changed to random port for security

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${GREEN}$1${BLUE}${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}➜${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
    print_success "Running as root"
}

check_ubuntu() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot detect OS"
        exit 1
    fi

    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        print_warning "This script is designed for Ubuntu. Detected: $ID"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    print_success "Ubuntu detected: $VERSION"
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
    print_header "Installing System Dependencies"

    print_step "Updating package lists..."
    apt-get update -qq

    print_step "Installing required packages..."

    # Install packages in stages to avoid conflicts
    # NOTE: We skip 'ufw' because it conflicts with iptables-persistent
    # We're using manual iptables rules which is more appropriate for a router

    # Stage 1: Core utilities
    apt-get install -y \
        curl \
        wget \
        git \
        python3 \
        python3-pip \
        python3-venv \
        net-tools \
        iproute2 \
        arp-scan \
        ffmpeg \
        avahi-daemon \
        jq \
        logwatch

    # Stage 2: Network packages
    apt-get install -y \
        iptables \
        iptables-persistent \
        dnsmasq \
        ethtool

    # Stage 3: Security packages (including SSH server)
    apt-get install -y \
        openssh-server \
        fail2ban \
        unattended-upgrades \
        apt-listchanges

    # Ensure SSH service is running
    systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null
    systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null

    print_success "System dependencies installed (using iptables without ufw)"
}

install_docker() {
    print_header "Installing Docker"

    if command -v docker &> /dev/null; then
        print_warning "Docker already installed: $(docker --version)"
        return 0
    fi

    print_step "Installing Docker..."
    curl -fsSL https://get.docker.com | sh

    print_step "Adding user to docker group..."
    if id "$POD_USER" &>/dev/null; then
        usermod -aG docker "$POD_USER"
    fi
    usermod -aG docker "$SUDO_USER"

    print_step "Configuring Docker DNS..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    print_success "Docker DNS configured"

    print_step "Enabling Docker service..."
    systemctl enable docker
    systemctl restart docker

    # Wait for Docker to be ready
    sleep 3

    print_success "Docker installed: $(docker --version)"
}

install_docker_compose() {
    print_header "Installing Docker Compose"

    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_warning "Docker Compose already installed: $(docker compose version)"
        return 0
    fi

    print_step "Docker Compose is included with Docker"
    print_success "Docker Compose available: $(docker compose version)"
}

configure_network() {
    print_header "Configuring Dual-NIC Network"

    print_step "Detecting network interfaces..."
    INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)
    echo "Available interfaces:"
    echo "$INTERFACES"
    echo ""

    read -p "WAN interface (internet-facing) [$WAN_INTERFACE]: " input_wan
    WAN_INTERFACE=${input_wan:-$WAN_INTERFACE}

    read -p "LAN interface (camera-facing) [$LAN_INTERFACE]: " input_lan
    LAN_INTERFACE=${input_lan:-$LAN_INTERFACE}

    print_step "WAN: $WAN_INTERFACE (DHCP)"
    print_step "LAN: $LAN_INTERFACE (Static: $LAN_IP)"

    # Create netplan configuration
    print_step "Creating netplan configuration..."
    cat > /etc/netplan/01-platebridge-network.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $WAN_INTERFACE:
      dhcp4: true
      dhcp6: false
      optional: true
    $LAN_INTERFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - $LAN_IP/24
      optional: true
EOF

    print_step "Applying netplan configuration..."
    netplan apply

    # Wait for interfaces to come up
    sleep 3

    # Install ethtool if not present
    if ! command -v ethtool &> /dev/null; then
        apt-get install -y ethtool
    fi

    # Disable hardware offloading on LAN interface (critical for DHCP)
    print_step "Disabling hardware offload on $LAN_INTERFACE (required for DHCP)..."
    ethtool -K $LAN_INTERFACE rx off tx off gso off tso off gro off 2>/dev/null || true

    # Make offload settings persistent across reboots
    cat > /etc/systemd/system/disable-offload.service << EOF
[Unit]
Description=Disable hardware offload on camera interface
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K $LAN_INTERFACE rx off tx off gso off tso off gro off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable disable-offload.service

    # Verify interface is up and has correct IP
    print_step "Verifying network configuration..."
    ip addr show $LAN_INTERFACE | grep -q "$LAN_IP" || {
        print_error "Failed to configure $LAN_INTERFACE with IP $LAN_IP"
        return 1
    }

    print_success "Network configured with hardware offload disabled"
}

configure_dhcp() {
    print_header "Configuring DHCP Server (dnsmasq)"

    # Disable systemd-resolved to prevent DNS port conflict
    print_step "Disabling systemd-resolved (conflicts with dnsmasq)..."
    systemctl disable systemd-resolved
    systemctl stop systemd-resolved

    # Remove immutable flag if set (from previous install)
    chattr -i /etc/resolv.conf 2>/dev/null || true

    # Remove symlink to systemd-resolved
    if [ -L /etc/resolv.conf ]; then
        rm /etc/resolv.conf
    fi

    # Create static resolv.conf
    print_step "Creating static DNS configuration..."
    cat > /etc/resolv.conf << EOF
# Static DNS configuration (systemd-resolved disabled)
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    # Make it immutable so nothing overwrites it
    chattr +i /etc/resolv.conf

    # Backup existing config
    if [ -f /etc/dnsmasq.conf ]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    fi

    # Create dnsmasq configuration for cameras
    print_step "Creating DHCP configuration..."
    cat > /etc/dnsmasq.d/platebridge-cameras.conf << EOF
# PlateBridge Camera DHCP Configuration
# Only bind to camera network interface
interface=$LAN_INTERFACE
bind-interfaces

# DHCP range for cameras
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,24h

# Gateway (this POD)
dhcp-option=3,$LAN_IP

# DNS servers for cameras
dhcp-option=6,8.8.8.8,8.8.4.4

# Don't read /etc/resolv.conf for upstream servers
no-resolv

# Use these DNS servers for camera queries
server=8.8.8.8
server=8.8.4.4

# Logging
log-dhcp
log-queries

# Don't bind to port 53 on all interfaces (only LAN)
no-hosts
expand-hosts
domain=platebridge.local

# Cache size
cache-size=1000
EOF

    # Test dnsmasq configuration
    print_step "Testing dnsmasq configuration..."
    if dnsmasq --test -C /etc/dnsmasq.conf; then
        print_success "dnsmasq configuration valid"
    else
        print_error "dnsmasq configuration has errors"
        return 1
    fi

    print_step "Enabling and starting dnsmasq..."
    systemctl enable dnsmasq
    systemctl restart dnsmasq

    # Wait a moment and check status
    sleep 2
    if systemctl is-active --quiet dnsmasq; then
        print_success "DHCP server configured and running"
    else
        print_error "dnsmasq failed to start. Checking logs..."
        journalctl -u dnsmasq -n 20 --no-pager
        return 1
    fi

    # Verify dnsmasq is listening on the correct interface
    print_step "Verifying dnsmasq is listening on ports 53 and 67..."
    if ss -ulnp | grep -q ":53.*dnsmasq" && ss -ulnp | grep -q ":67.*dnsmasq"; then
        print_success "dnsmasq is listening on DNS (53) and DHCP (67)"
    else
        print_warning "dnsmasq may not be listening correctly"
        echo "Current listening ports:"
        ss -ulnp | grep dnsmasq || echo "No dnsmasq ports found"
    fi

    print_step "Testing DHCP with tcpdump..."
    print_warning "After connecting a camera, monitor with: sudo tcpdump -i $LAN_INTERFACE -n port 67 or port 68"
}

configure_firewall() {
    print_header "Configuring Router Security & Firewall"

    print_step "Enabling IP forwarding and security hardening..."
    cat > /etc/sysctl.d/99-platebridge-security.conf << EOF
# IP Forwarding for routing
net.ipv4.ip_forward=1

# Security hardening for router/gateway
# CRITICAL: Disable reverse path filtering on camera interface for DHCP
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.$LAN_INTERFACE.rp_filter=0

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0

# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0

# Ignore ICMP ping requests (optional, disable if you need ping)
net.ipv4.icmp_echo_ignore_all=0

# Protect against SYN flood attacks
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=5

# Log suspicious packets
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0

# IPv6 disabled (if not needed)
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF

    sysctl -p /etc/sysctl.d/99-platebridge-security.conf

    print_step "Configuring iptables firewall rules..."

    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Default policies - DROP everything by default (whitelist approach)
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established and related connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Anti-spoofing: drop packets from LAN claiming to be from WAN
    iptables -A INPUT -i $LAN_INTERFACE -s 0.0.0.0/8 -j DROP
    iptables -A INPUT -i $LAN_INTERFACE -s 10.0.0.0/8 -j DROP
    iptables -A INPUT -i $LAN_INTERFACE -s 169.254.0.0/16 -j DROP
    iptables -A INPUT -i $LAN_INTERFACE -s 172.16.0.0/12 -j DROP
    iptables -A INPUT -i $LAN_INTERFACE ! -s 192.168.100.0/24 -j DROP

    # Protect against port scanning
    iptables -N port-scanning
    iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
    iptables -A port-scanning -j DROP

    # Protection against common attacks
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP  # NULL packets
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP   # XMAS packets
    iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
    iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP

    # Rate limit SSH connections (prevent brute force)
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
    iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --rttl --name SSH -j DROP

    # Allow SSH from WAN (will be secured with fail2ban)
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 22 -m state --state NEW -j ACCEPT

    # Allow HTTPS for portal communication
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 443 -m state --state NEW -j ACCEPT

    # Allow stream server port
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 8000 -m state --state NEW -j ACCEPT

    # Allow Frigate Web UI from WAN
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 5000 -m state --state NEW -j ACCEPT

    # Allow go2rtc RTSP from WAN
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 8554 -m state --state NEW -j ACCEPT

    # Allow go2rtc API/WebRTC from WAN
    iptables -A INPUT -i $WAN_INTERFACE -p tcp --dport 8555 -m state --state NEW -j ACCEPT

    # Allow WebRTC UDP range from WAN
    iptables -A INPUT -i $WAN_INTERFACE -p udp --dport 50000:50100 -m state --state NEW -j ACCEPT

    # Allow all from LAN to POD
    iptables -A INPUT -i $LAN_INTERFACE -s $LAN_NETWORK -j ACCEPT

    # Allow DHCP from camera network
    iptables -A INPUT -i $LAN_INTERFACE -p udp --dport 67:68 --sport 67:68 -j ACCEPT

    # Allow DNS queries from camera network
    iptables -A INPUT -i $LAN_INTERFACE -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -i $LAN_INTERFACE -p tcp --dport 53 -j ACCEPT

    # NAT: Masquerade camera network traffic going to internet
    iptables -t nat -A POSTROUTING -o $WAN_INTERFACE -j MASQUERADE

    # Forward camera network traffic to internet
    iptables -A FORWARD -i $LAN_INTERFACE -o $WAN_INTERFACE -s $LAN_NETWORK -j ACCEPT
    iptables -A FORWARD -i $WAN_INTERFACE -o $LAN_INTERFACE -d $LAN_NETWORK -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Block forwarding from WAN to LAN (cameras not accessible from internet)
    iptables -A FORWARD -i $WAN_INTERFACE -o $LAN_INTERFACE -j DROP

    # Log dropped packets (for debugging)
    iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables INPUT denied: " --log-level 7
    iptables -A FORWARD -m limit --limit 5/min -j LOG --log-prefix "iptables FORWARD denied: " --log-level 7

    # Save iptables rules
    print_step "Saving firewall rules..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4

    print_success "Firewall configured with router security"
}

configure_security_hardening() {
    print_header "Configuring Security Hardening"

    # Configure fail2ban for SSH protection
    print_step "Configuring fail2ban..."
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    # Configure automatic security updates
    print_step "Configuring automatic security updates..."
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades

    # Harden SSH configuration
    print_step "Hardening SSH configuration..."

    # Ensure SSH server is installed and running
    if ! command -v sshd &> /dev/null; then
        print_warning "OpenSSH server not found, installing..."
        apt-get install -y openssh-server
        systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null
        systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null
    fi

    # Backup existing config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Apply SSH hardening
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

    # Add if not exists
    grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
    grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
    grep -q "^PermitEmptyPasswords" /etc/ssh/sshd_config || echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config
    grep -q "^MaxAuthTries" /etc/ssh/sshd_config || echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
    grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config
    grep -q "^Protocol" /etc/ssh/sshd_config || echo "Protocol 2" >> /etc/ssh/sshd_config
    grep -q "^X11Forwarding" /etc/ssh/sshd_config || echo "X11Forwarding no" >> /etc/ssh/sshd_config

    # Test SSH config before restarting
    if sshd -t 2>/dev/null; then
        # Try ssh.service first (Ubuntu 24.04), fall back to sshd
        if systemctl list-unit-files | grep -q "^ssh.service"; then
            systemctl restart ssh
            print_success "SSH service restarted (ssh.service)"
        elif systemctl list-unit-files | grep -q "^sshd.service"; then
            systemctl restart sshd
            print_success "SSH service restarted (sshd.service)"
        else
            print_error "Could not find SSH service (neither ssh.service nor sshd.service)"
            return 1
        fi
    else
        print_error "SSH configuration test failed - config has syntax errors"
        return 1
    fi

    print_warning "SSH has been hardened. Make sure you have SSH key access configured!"
    print_warning "Root login is now disabled."

    # Set secure permissions on important files
    print_step "Setting secure file permissions..."
    chmod 700 /root
    chmod 600 /etc/ssh/sshd_config
    chmod 644 /etc/passwd
    chmod 644 /etc/group
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow

    # Disable unnecessary services
    print_step "Disabling unnecessary services..."
    systemctl disable bluetooth.service 2>/dev/null || true
    systemctl stop bluetooth.service 2>/dev/null || true

    print_success "Security hardening complete"
}

create_pod_user() {
    print_header "Creating POD User"

    if id "$POD_USER" &>/dev/null; then
        print_warning "User $POD_USER already exists"
        return 0
    fi

    print_step "Creating user $POD_USER..."
    useradd -r -m -s /bin/bash "$POD_USER"
    usermod -aG docker "$POD_USER"

    print_success "User $POD_USER created"
}

setup_usb_storage() {
    print_header "Setting Up USB Storage for Recordings"

    # Detect USB drive
    print_step "Detecting USB drives..."
    USB_DRIVE=$(lsblk -o NAME,SIZE,TYPE,TRAN | grep usb | grep disk | awk '{print $1}' | head -n1)

    if [ -z "$USB_DRIVE" ]; then
        print_warning "No USB drive detected - will use local storage"
        return 0
    fi

    print_success "Found USB drive: /dev/$USB_DRIVE"

    # Check if it has partitions
    USB_PART=$(lsblk -o NAME,TYPE | grep "^├─\|^└─" | grep "$USB_DRIVE" | head -n1 | awk '{print $1}' | sed 's/[├─└─]//g' | xargs)

    if [ -z "$USB_PART" ]; then
        print_step "Creating partition..."
        parted -s /dev/$USB_DRIVE mklabel gpt
        parted -s /dev/$USB_DRIVE mkpart primary ext4 0% 100%
        sleep 2
        USB_PART="${USB_DRIVE}1"

        print_step "Formatting as ext4..."
        mkfs.ext4 -F /dev/$USB_PART -L FRIGATE_DATA
    else
        USB_PART=$(echo $USB_PART | sed 's/^[├└]─//g')
        FS_TYPE=$(lsblk -o NAME,FSTYPE /dev/$USB_PART | tail -1 | awk '{print $2}')
        if [ -z "$FS_TYPE" ]; then
            print_step "Formatting as ext4..."
            mkfs.ext4 -F /dev/$USB_PART -L FRIGATE_DATA
        fi
        e2label /dev/$USB_PART FRIGATE_DATA 2>/dev/null || true
    fi

    # Get UUID
    USB_UUID=$(blkid /dev/$USB_PART | grep -oP 'UUID="\K[^"]+')
    print_success "UUID: $USB_UUID"

    # Create mount point
    mkdir -p /media/frigate

    # Add to fstab if not already there
    if ! grep -q "/media/frigate" /etc/fstab; then
        echo "UUID=$USB_UUID /media/frigate ext4 defaults,nofail 0 2" >> /etc/fstab
        print_success "Added to /etc/fstab"
    fi

    # Mount
    mount -a

    # Create Frigate directories on USB
    mkdir -p /media/frigate/{recordings,clips,snapshots}
    chown -R 1000:1000 /media/frigate
    chmod 755 /media/frigate

    print_success "USB storage configured for Frigate recordings"
}

setup_directories() {
    print_header "Setting Up Directories"

    print_step "Creating directory structure..."
    mkdir -p $INSTALL_DIR/{config,docker,logs,frigate,platerecognizer}
    mkdir -p $INSTALL_DIR/frigate/{config,storage,media}

    print_step "Setting permissions..."
    chown -R $POD_USER:$POD_USER $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR

    print_success "Directories created"
}

install_frigate() {
    print_header "Setting Up Frigate NVR"

    print_step "Creating Frigate configuration..."
    cat > $INSTALL_DIR/frigate/config/config.yml << 'EOF'
# Frigate Configuration for PlateBridge POD
ui:
  timezone: America/New_York

mqtt:
  host: mosquitto
  topic_prefix: frigate
  client_id: frigate

# Hardware decode only
ffmpeg:
  hwaccel_args: preset-vaapi

# Keep DB on USB storage
database:
  path: /media/frigate/frigate.db

detectors:
  cpu1:
    type: cpu
    num_threads: 3

cameras:
  # Dummy camera to prevent startup errors
  # Replace with your actual cameras
  dummy:
    enabled: false
    ffmpeg:
      inputs:
        - path: rtsp://127.0.0.1:8554/dummy
          roles: [detect]

  # Add real cameras here - Example configuration:
  # camera_1:
  #   enabled: true
  #   ffmpeg:
  #     inputs:
  #       # SUB stream for detection
  #       - path: rtsp://admin:123456@192.168.100.20:554/
  #         roles: [detect]
  #       # MAIN stream for recording
  #       - path: rtsp://admin:123456@192.168.100.22:554/
  #         roles: [record]
  #   detect:
  #     width: 640
  #     height: 360
  #     fps: 5
  #   snapshots:
  #     enabled: true
  #   objects:
  #     track:
  #       - car
  #       - person
  #       - truck
  #       - motorcycle
  #       - bus
  #       - bicycle
  #       - license_plate
  #     filters:
  #       car:
  #         min_area: 140000
  #         max_area: 2000000
  #         threshold: 0.8

record:
  enabled: true
  retain:
    days: 7
    mode: motion

snapshots:
  enabled: true
  retain:
    default: 7

lpr:
  enabled: true

detect:
  enabled: true

version: 0.16-0
EOF

    print_step "Creating POD Agent Dockerfile..."
    cat > $INSTALL_DIR/docker/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY complete_pod_agent.py agent.py
COPY config.yaml .

# Create directories
RUN mkdir -p /config /logs /recordings /tmp/hls_output

# Expose ports
EXPOSE 8000 1883

# Run the agent
CMD ["python3", "agent.py"]
DOCKERFILE

    print_step "Creating agent requirements.txt..."
    cat > $INSTALL_DIR/docker/requirements.txt << EOF
pyyaml>=6.0
requests>=2.31.0
paho-mqtt>=1.6.1
flask>=2.3.0
psutil>=5.9.0
EOF

    print_step "Creating Frigate docker-compose.yml..."
    cat > $INSTALL_DIR/docker/docker-compose.yml << EOF
version: '3.8'

services:
  mosquitto:
    image: eclipse-mosquitto:latest
    container_name: mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - $INSTALL_DIR/frigate/mosquitto:/mosquitto/data
      - $INSTALL_DIR/frigate/mosquitto/log:/mosquitto/log
    command: mosquitto -c /mosquitto-no-auth.conf

  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    container_name: frigate
    restart: unless-stopped
    privileged: true
    shm_size: 256mb
    devices:
      - /dev/bus/usb:/dev/bus/usb  # USB cameras
      - /dev/dri:/dev/dri          # Hardware acceleration
    volumes:
      - $INSTALL_DIR/frigate/config:/config
      - /media/frigate:/media/frigate  # USB storage for recordings
      - /etc/localtime:/etc/localtime:ro
      - type: tmpfs
        target: /tmp/cache
        tmpfs:
          size: 1000000000
    ports:
      - "5000:5000"    # Web UI
      - "8554:8554"    # RTSP feeds
      - "8555:8555/tcp"    # WebRTC over tcp
      - "8555:8555/udp"    # WebRTC over udp
    environment:
      - FRIGATE_RTSP_PASSWORD=password
    network_mode: host
    depends_on:
      - mosquitto

  platerecognizer:
    image: platerecognizer/alpr-stream:latest
    container_name: platerecognizer
    restart: unless-stopped
    volumes:
      - $INSTALL_DIR/platerecognizer:/user-data
    environment:
      - LICENSE_KEY=\${PLATE_RECOGNIZER_LICENSE_KEY}
      - TOKEN=\${PLATE_RECOGNIZER_TOKEN}
    network_mode: host
    depends_on:
      - mosquitto

  platebridge-agent:
    build:
      context: .
      dockerfile: Dockerfile
    image: platebridge-pod-agent:latest
    container_name: platebridge-agent
    restart: unless-stopped
    volumes:
      - $INSTALL_DIR/config/config.yaml:/app/config.yaml:ro
      - $INSTALL_DIR/logs:/logs
      - /media/frigate/recordings:/recordings  # USB storage
    environment:
      - PORTAL_URL=\${PORTAL_URL}
      - POD_API_KEY=\${POD_API_KEY}
      - POD_ID=\${POD_ID}
      - MQTT_HOST=localhost
      - MQTT_PORT=1883
    network_mode: host
    depends_on:
      - frigate
      - mosquitto
      - platerecognizer
EOF

    print_step "Creating .env file template..."
    cat > $INSTALL_DIR/docker/.env.example << EOF
# PlateBridge Portal Configuration
PORTAL_URL=https://your-portal.platebridge.io
POD_API_KEY=your-api-key-here
SITE_ID=your-site-id-here

# Plate Recognizer Configuration
PLATE_RECOGNIZER_LICENSE_KEY=your-license-key-here
PLATE_RECOGNIZER_TOKEN=your-api-token-here

# Frigate Configuration
FRIGATE_RTSP_PASSWORD=password
EOF

    chown -R $POD_USER:$POD_USER $INSTALL_DIR/docker
    chown -R $POD_USER:$POD_USER $INSTALL_DIR/frigate

    print_success "Frigate configured"
}

install_platerecognizer() {
    print_header "Configuring Plate Recognizer Stream"

    print_step "Creating Plate Recognizer data directory..."
    mkdir -p $INSTALL_DIR/platerecognizer

    # Plate Recognizer Stream uses environment variables directly
    # No config file needed - credentials passed via LICENSE_KEY and TOKEN env vars

    chown -R $POD_USER:$POD_USER $INSTALL_DIR/platerecognizer
    print_success "Plate Recognizer data directory created"
}

install_pod_agent() {
    print_header "Installing PlateBridge POD Agent"

    print_step "Creating Python virtual environment..."
    cd $INSTALL_DIR
    python3 -m venv venv

    print_step "Installing Python dependencies..."
    cat > $INSTALL_DIR/requirements.txt << EOF
paho-mqtt>=1.6.1
requests>=2.28.0
pyyaml>=6.0
pillow>=9.0.0
opencv-python>=4.7.0
numpy>=1.24.0
EOF

    source $INSTALL_DIR/venv/bin/activate
    pip install --upgrade pip
    pip install -r $INSTALL_DIR/requirements.txt
    deactivate

    print_step "Copying agent files..."
    if [ -f "$(dirname "$0")/agent.py" ]; then
        cp "$(dirname "$0")/agent.py" $INSTALL_DIR/
        print_success "Agent copied"
    else
        print_warning "agent.py not found in script directory"
        print_step "You'll need to manually copy agent.py to $INSTALL_DIR/"
    fi

    chown -R $POD_USER:$POD_USER $INSTALL_DIR

    print_success "POD agent installed"
}

create_camera_discovery_script() {
    print_header "Creating Camera Discovery Script"

    cat > $INSTALL_DIR/discover-cameras.sh << 'EOF'
#!/bin/bash

echo "Scanning for cameras on 192.168.100.0/24..."
echo ""

sudo arp-scan --interface=enp1s0 192.168.100.0/24 | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}"

echo ""
echo "DHCP leases:"
cat /var/lib/misc/dnsmasq.leases

echo ""
echo "Testing RTSP streams (common URLs)..."

for ip in $(sudo arp-scan --interface=enp1s0 192.168.100.0/24 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep "192.168.100"); do
    echo "Testing $ip..."

    # Common RTSP paths
    for path in "/stream" "/h264" "/live" "/ch01" "/Streaming/Channels/101"; do
        ffprobe -rtsp_transport tcp -v quiet "rtsp://$ip:554$path" 2>&1 | grep -q "Stream" && echo "  ✓ rtsp://$ip:554$path"
    done
done
EOF

    chmod +x $INSTALL_DIR/discover-cameras.sh
    chown $POD_USER:$POD_USER $INSTALL_DIR/discover-cameras.sh

    print_success "Camera discovery script created"
}

configure_interactive() {
    print_header "Interactive Configuration"

    echo "Let's configure your POD connection to the portal."
    echo ""
    echo "STEP 1: Go to the portal's Properties page"
    echo "STEP 2: Click 'Generate POD Registration Token' on your site"
    echo "STEP 3: Copy the generated token"
    echo ""

    read -p "Portal URL (e.g., https://platebridge.vercel.app): " PORTAL_URL
    read -p "Registration Token (from portal): " REG_TOKEN

    # Get POD hardware info for registration
    # Use hostname as serial if hardware serial not available
    SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || hostname)
    MAC=$(ip link show $LAN_INTERFACE | grep link/ether | awk '{print $2}')
    MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "PB-M1")

    echo ""
    print_step "Registering POD with portal..."
    echo "  Serial: $SERIAL"
    echo "  MAC: $MAC"
    echo "  Model: $MODEL"
    echo ""

    # Register POD and get API key
    REGISTER_RESPONSE=$(curl -s -X POST "$PORTAL_URL/api/pods/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"serial\": \"$SERIAL\",
            \"mac\": \"$MAC\",
            \"model\": \"$MODEL\",
            \"version\": \"1.0.0\",
            \"registration_token\": \"$REG_TOKEN\"
        }")

    # Extract API key, POD ID, and Community ID from response
    POD_API_KEY=$(echo "$REGISTER_RESPONSE" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
    POD_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"pod_id":"[^"]*"' | cut -d'"' -f4)
    COMMUNITY_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"community_id":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$POD_API_KEY" ] || [ -z "$COMMUNITY_ID" ]; then
        print_error "Failed to register POD with portal"
        echo "Response: $REGISTER_RESPONSE"
        echo ""
        echo "Common issues:"
        echo "  1. Token expired (tokens valid for 24 hours)"
        echo "  2. Token already used"
        echo "  3. Portal URL is incorrect"
        echo "  4. Network connectivity issue"
        echo ""
        echo "Generate a new token from the portal and try again."
        exit 1
    fi

    print_success "POD registered successfully!"
    echo ""
    echo "  POD ID: $POD_ID"
    echo "  Community ID: $COMMUNITY_ID"
    echo "  API Key: ${POD_API_KEY:0:20}..."
    echo ""

    # Prompt for Plate Recognizer credentials
    echo ""
    print_step "Plate Recognizer Configuration"
    echo "You need a Plate Recognizer Stream license and API token for each POD."
    echo "Get them from: https://app.platerecognizer.com/"
    echo ""
    read -p "Plate Recognizer License Key: " PLATE_LICENSE
    read -p "Plate Recognizer API Token: " PLATE_TOKEN
    echo ""

    # Create .env file
    cat > $INSTALL_DIR/docker/.env << EOF
PORTAL_URL=$PORTAL_URL
POD_API_KEY=$POD_API_KEY
POD_ID=$POD_ID
COMMUNITY_ID=$COMMUNITY_ID
POD_SERIAL=$SERIAL
PLATE_RECOGNIZER_LICENSE_KEY=$PLATE_LICENSE
PLATE_RECOGNIZER_TOKEN=$PLATE_TOKEN
FRIGATE_RTSP_PASSWORD=password
EOF

    chown $POD_USER:$POD_USER $INSTALL_DIR/docker/.env
    chmod 600 $INSTALL_DIR/docker/.env

    # Create config directory and config.yaml for the agent
    mkdir -p $INSTALL_DIR/config
    cat > $INSTALL_DIR/config/config.yaml << EOF
portal_url: "$PORTAL_URL"
pod_api_key: "$POD_API_KEY"
pod_id: "$POD_ID"
community_id: "$COMMUNITY_ID"
camera_id: "camera_1"
camera_name: "Main Camera"
camera_rtsp_url: "rtsp://192.168.100.100:554/stream1"
camera_position: "main entrance"
camera_ip: "192.168.100.100"
stream_port: 8000
recordings_dir: "/recordings"
heartbeat_interval: 60
whitelist_refresh_interval: 300
EOF

    # Also copy to docker directory for building
    cp $INSTALL_DIR/config/config.yaml $INSTALL_DIR/docker/config.yaml

    # Copy all Docker build files to docker directory
    print_step "Copying Docker build files to docker directory..."
    echo "Source directory: $SCRIPT_DIR"
    echo "Target directory: $INSTALL_DIR/docker"

    # Copy Python agent
    if [ -f "$SCRIPT_DIR/complete_pod_agent.py" ]; then
        cp "$SCRIPT_DIR/complete_pod_agent.py" $INSTALL_DIR/docker/
        print_success "Agent Python file copied"
    else
        print_warning "complete_pod_agent.py not found in $SCRIPT_DIR"
        print_warning "Docker build will fail without this file"
    fi

    # Copy Dockerfile
    if [ -f "$SCRIPT_DIR/Dockerfile" ]; then
        cp "$SCRIPT_DIR/Dockerfile" $INSTALL_DIR/docker/
        print_success "Dockerfile copied"
    else
        print_warning "Dockerfile not found in $SCRIPT_DIR"
    fi

    # Copy requirements.txt
    if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
        cp "$SCRIPT_DIR/requirements.txt" $INSTALL_DIR/docker/
        print_success "requirements.txt copied"
    else
        print_warning "requirements.txt not found in $SCRIPT_DIR"
    fi

    # Copy config example
    if [ -f "$SCRIPT_DIR/config.example.yaml" ]; then
        cp "$SCRIPT_DIR/config.example.yaml" $INSTALL_DIR/docker/
        print_success "config.example.yaml copied"
    else
        print_warning "config.example.yaml not found in $SCRIPT_DIR"
    fi

    # Copy .dockerignore
    if [ -f "$SCRIPT_DIR/.dockerignore" ]; then
        cp "$SCRIPT_DIR/.dockerignore" $INSTALL_DIR/docker/
        print_success ".dockerignore copied"
    fi

    # Verify all required files are present
    print_step "Verifying Docker build files..."
    if [ ! -f "$INSTALL_DIR/docker/complete_pod_agent.py" ]; then
        print_error "Missing: complete_pod_agent.py"
        return 1
    fi
    if [ ! -f "$INSTALL_DIR/docker/Dockerfile" ]; then
        print_error "Missing: Dockerfile"
        return 1
    fi
    if [ ! -f "$INSTALL_DIR/docker/requirements.txt" ]; then
        print_error "Missing: requirements.txt"
        return 1
    fi
    print_success "All Docker build files present"

    chown -R $POD_USER:$POD_USER $INSTALL_DIR/docker

    print_success "Configuration saved"
}

start_services() {
    print_header "Starting Services"

    # Check if containers are already running and stop them
    print_step "Checking for existing containers..."
    EXISTING_CONTAINERS=$(docker ps -a --filter "name=platebridge-pod\|frigate\|mosquitto\|platerecognizer" --format "{{.Names}}" 2>/dev/null || true)

    if [ ! -z "$EXISTING_CONTAINERS" ]; then
        print_warning "Found existing containers, stopping them..."
        docker stop platebridge-pod platebridge-agent frigate mosquitto platerecognizer 2>/dev/null || true
        print_success "Existing containers stopped"
    fi

    print_step "Checking internet connectivity..."
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_success "Internet connectivity OK"
    else
        print_error "No internet connectivity detected"
        print_warning "Docker build requires internet access to download packages"
        print_warning "Please check your network configuration"
        return 1
    fi

    print_step "Checking DNS resolution..."
    if ping -c 1 google.com >/dev/null 2>&1; then
        print_success "DNS resolution OK"
    else
        print_error "DNS resolution failed"
        print_warning "Docker build requires DNS to work"
        print_warning "Try: sudo systemctl restart systemd-resolved"
        return 1
    fi

    print_step "Testing DNS inside Docker..."
    if docker run --rm alpine ping -c 1 google.com >/dev/null 2>&1; then
        print_success "Docker DNS working"
    else
        print_error "Docker cannot resolve DNS"
        print_warning "Checking Docker DNS configuration..."
        if [ -f /etc/docker/daemon.json ]; then
            echo "Current daemon.json:"
            cat /etc/docker/daemon.json
        else
            print_warning "/etc/docker/daemon.json not found"
        fi
        print_warning "Attempting to fix Docker DNS..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
DOCKEREOF
        systemctl restart docker
        sleep 5
        print_warning "Retrying DNS test..."
        if docker run --rm alpine ping -c 1 google.com >/dev/null 2>&1; then
            print_success "Docker DNS fixed!"
        else
            print_error "Docker DNS still not working. Manual intervention required."
            return 1
        fi
    fi

    print_step "Checking Docker build directory contents..."
    echo "Contents of $INSTALL_DIR/docker/:"
    ls -la $INSTALL_DIR/docker/
    echo ""

    print_step "Building Docker image locally..."
    cd $INSTALL_DIR/docker

    if [ -f "Dockerfile" ]; then
        echo "Building with context: $(pwd)"
        # Build with explicit network=host to use host DNS
        docker build --network=host -t platebridge-pod-agent:latest .
        if [ $? -ne 0 ]; then
            print_error "Docker build failed"
            print_warning "Common issues:"
            print_warning "  1. No internet connectivity"
            print_warning "  2. DNS not working (try: sudo systemctl restart systemd-resolved)"
            print_warning "  3. Docker daemon not running"
            return 1
        fi
        print_success "Docker image built"
    else
        print_error "Dockerfile not found in $(pwd)"
        return 1
    fi

    if [ -f ".env" ]; then
        print_step "Starting Docker services..."
        docker compose up -d --remove-orphans
        print_success "Docker services started"
    else
        print_warning ".env file not found. Run configuration first."
        print_step "Copy .env.example to .env and configure it"
    fi
}

create_startup_service() {
    print_header "Creating Startup Service"

    cat > /etc/systemd/system/platebridge-pod.service << EOF
[Unit]
Description=PlateBridge POD Services
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/docker
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
User=$POD_USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable platebridge-pod

    print_success "Startup service created"
}

save_network_info() {
    print_header "Saving Network Information"

    cat > $INSTALL_DIR/network-info.txt << EOF
PlateBridge POD Network & Security Configuration
=================================================
Installation Date: $(date)
POD acts as secure router between cellular WAN and camera LAN

Network Interfaces:
- WAN (Cellular): $WAN_INTERFACE (DHCP from carrier)
- LAN (Cameras):  $LAN_INTERFACE (Static: $LAN_IP)

Camera Network (Isolated):
- Network:     $LAN_NETWORK
- Gateway:     $LAN_IP (this POD)
- DHCP Range:  $DHCP_RANGE_START - $DHCP_RANGE_END
- DNS:         8.8.8.8, 8.8.4.4
- Isolation:   Cameras CANNOT be accessed from internet
- NAT:         Camera traffic masqueraded through $WAN_INTERFACE

Services (Accessible from WAN):
- SSH:             Port 22 (hardened, fail2ban protected)
- Frigate Web UI:  http://$(hostname -I | awk '{print $1}'):5000
- HTTPS Portal:    Port 443
- Stream Server:   Port 8000
- RTSP Server:     rtsp://$(hostname -I | awk '{print $1}'):8554

Security Features:
- ✓ iptables firewall (default DROP policy)
- ✓ NAT for camera network
- ✓ Anti-spoofing rules
- ✓ SYN flood protection
- ✓ Port scan detection
- ✓ SSH rate limiting (max 3 attempts/min)
- ✓ fail2ban (3 failed SSH = 1hr ban)
- ✓ Root login disabled
- ✓ Automatic security updates
- ✓ Camera network isolated from internet
- ✓ WAN cannot access cameras directly

Useful Commands:
================
# Check Docker services
cd $INSTALL_DIR/docker && docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Discover cameras
$INSTALL_DIR/discover-cameras.sh

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Scan camera network
sudo arp-scan --interface=$LAN_INTERFACE $LAN_NETWORK

# Check network
ip addr show

Security Monitoring:
====================
# View firewall logs (dropped packets)
sudo tail -f /var/log/syslog | grep iptables

# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client status sshd | grep "Banned IP"

# Unban an IP
sudo fail2ban-client set sshd unbanip <ip-address>

# View SSH login attempts
sudo tail -f /var/log/auth.log

# Check firewall rules
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n

# View security updates
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# Check open ports
sudo ss -tulpn

Configuration Files:
====================
- Network:  /etc/netplan/01-platebridge-network.yaml
- DHCP:     /etc/dnsmasq.d/platebridge-cameras.conf
- Firewall: /etc/iptables/rules.v4
- Frigate:  $INSTALL_DIR/frigate/config/config.yml
- Docker:   $INSTALL_DIR/docker/docker-compose.yml
- Portal:   $INSTALL_DIR/docker/.env
EOF

    chown $POD_USER:$POD_USER $INSTALL_DIR/network-info.txt

    print_success "Network info saved to $INSTALL_DIR/network-info.txt"
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    clear
    print_header "PlateBridge POD - Complete Installation"

    echo "This script will install and configure:"
    echo "  • Docker & Docker Compose"
    echo "  • Dual-NIC network configuration"
    echo "  • DHCP server for cameras"
    echo "  • Frigate NVR"
    echo "  • Plate Recognizer Stream"
    echo "  • PlateBridge POD agent"
    echo "  • Camera discovery tools"
    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    # Pre-flight checks
    check_root
    check_ubuntu

    # Installation steps
    install_dependencies
    install_docker
    install_docker_compose
    create_pod_user
    setup_usb_storage        # Configure USB drive FIRST
    setup_directories
    configure_network
    configure_dhcp
    configure_firewall
    configure_security_hardening
    install_frigate
    install_platerecognizer
    install_pod_agent
    create_camera_discovery_script
    create_startup_service
    save_network_info

    # Optional configuration
    echo ""
    read -p "Configure portal connection now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        configure_interactive
        start_services
    fi

    # Final summary
    print_header "Installation Complete!"

    echo -e "${GREEN}✓ Docker and Docker Compose installed${NC}"
    echo -e "${GREEN}✓ Network configured (Dual-NIC: $WAN_INTERFACE, $LAN_INTERFACE)${NC}"
    echo -e "${GREEN}✓ DHCP server running${NC}"
    echo -e "${GREEN}✓ Firewall configured with router security${NC}"
    echo -e "${GREEN}✓ Security hardening applied (fail2ban, auto-updates)${NC}"
    echo -e "${GREEN}✓ SSH hardened (root login disabled)${NC}"
    echo -e "${GREEN}✓ Frigate NVR ready${NC}"
    echo -e "${GREEN}✓ Plate Recognizer Stream configured${NC}"
    echo -e "${GREEN}✓ POD agent installed${NC}"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Connect cameras to $LAN_INTERFACE"
    echo "2. Run camera discovery: $INSTALL_DIR/discover-cameras.sh"
    echo "3. Configure .env: $INSTALL_DIR/docker/.env"
    echo "4. Start services: cd $INSTALL_DIR/docker && docker compose up -d --remove-orphans"
    echo "5. Access Frigate: http://$(hostname -I | awk '{print $1}'):5000"
    echo ""
    echo -e "${BLUE}📄 Full configuration details: $INSTALL_DIR/network-info.txt${NC}"
    echo ""
    echo -e "${GREEN}🎉 Your PlateBridge POD is ready!${NC}"
}

# Run main installation
main
