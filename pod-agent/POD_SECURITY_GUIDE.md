# 🔒 PlateBridge POD Security Guide

## Overview

Your PlateBridge POD acts as a **secure router** between the internet (cellular WAN) and your camera network (isolated LAN). This guide covers the security architecture and how to maintain it.

---

## 🏗️ Network Architecture

```
Internet (Cellular)
        │
        │ enp3s0 (WAN)
        │ DHCP from carrier
        │
    ┌───▼────┐
    │  POD   │ ← Secure Router
    │ Router │ ← Firewall + NAT
    └───┬────┘
        │ enp1s0 (LAN)
        │ 192.168.100.1/24
        │
    ┌───▼────────────────┐
    │  Camera Network    │
    │  192.168.100.0/24  │
    │  (ISOLATED)        │
    └────────────────────┘
    │
    Cameras (192.168.100.100-200)
```

---

## 🛡️ Security Features

### 1. **Firewall (iptables)**

**Default Policy: DROP**
- All incoming traffic is BLOCKED by default
- Only explicitly allowed services can be accessed
- Cameras are completely isolated from internet

**Allowed Incoming (WAN → POD):**
```
✓ SSH (Port 22) - Rate limited, fail2ban protected
✓ HTTPS (Port 443) - Portal communication
✓ Stream Server (Port 8000) - Video streaming
```

**Blocked:**
```
✗ Everything else from internet
✗ Direct access to cameras from WAN
✗ Cameras cannot be reached from internet
```

### 2. **NAT (Network Address Translation)**

**Camera Traffic:**
- Cameras can reach internet (for updates, NTP)
- Camera traffic is masqueraded through WAN interface
- Source IPs hidden from internet
- Cameras appear as single IP (WAN IP)

**Protection:**
- Cameras invisible from internet
- Cannot be port-scanned
- Cannot be accessed directly

### 3. **Anti-Spoofing Rules**

**Prevents:**
- IP spoofing attacks
- Packets claiming to be from private ranges on WAN
- Malformed packets
- Source routing attacks

**Rules:**
```bash
# Block private IPs on WAN interface
✓ Drop 0.0.0.0/8 on WAN
✓ Drop 10.0.0.0/8 on WAN
✓ Drop 169.254.0.0/16 on WAN
✓ Drop 172.16.0.0/12 on WAN
✓ Only allow 192.168.100.0/24 on LAN
```

### 4. **DDoS Protection**

**SYN Flood Protection:**
```
✓ TCP SYN cookies enabled
✓ Max SYN backlog: 2048
✓ SYN retries limited
```

**Port Scan Detection:**
```
✓ Unusual TCP flag combinations dropped
✓ NULL packets dropped
✓ XMAS packets dropped
✓ Rate limiting on suspicious traffic
```

### 5. **SSH Hardening**

**Configuration:**
```
✓ Root login disabled
✓ Max 3 login attempts per session
✓ Session timeout after 10 minutes idle
✓ Protocol 2 only (SSH v1 disabled)
✓ X11 forwarding disabled
✓ Empty passwords not allowed
```

**Rate Limiting:**
```
✓ Max 3 connection attempts per minute
✓ 4th attempt triggers temporary block
✓ Prevents brute force attacks
```

### 6. **Fail2Ban**

**SSH Protection:**
```
✓ 3 failed login attempts = 1 hour ban
✓ Automatic IP blocking
✓ Email alerts on ban (configurable)
✓ Persistent across reboots
```

**Status:**
```bash
# Check fail2ban status
sudo fail2ban-client status

# Check SSH jail
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client status sshd | grep "Banned IP"

# Unban IP
sudo fail2ban-client set sshd unbanip <ip-address>
```

### 7. **Automatic Security Updates**

**Unattended Upgrades:**
```
✓ Security patches installed automatically
✓ Daily update checks
✓ System packages updated
✓ No manual intervention needed
✓ Auto-reboot disabled (optional)
```

**Logs:**
```bash
sudo tail -f /var/log/unattended-upgrades/unattended-upgrades.log
```

---

## 🔍 Security Monitoring

### Check Firewall Status

```bash
# View all firewall rules
sudo iptables -L -v -n

# View NAT rules
sudo iptables -t nat -L -v -n

# View dropped packets (live)
sudo tail -f /var/log/syslog | grep iptables
```

### Monitor SSH Attempts

```bash
# View all SSH login attempts
sudo tail -f /var/log/auth.log

# Count failed SSH attempts
sudo grep "Failed password" /var/log/auth.log | wc -l

# View successful logins
sudo grep "Accepted password" /var/log/auth.log
```

### Check Active Connections

```bash
# View all open ports and connections
sudo ss -tulpn

# View only listening services
sudo ss -tulpn | grep LISTEN

# View established connections
sudo ss -o state established
```

### Check Banned IPs

```bash
# List all banned IPs
sudo fail2ban-client status sshd

# Check if specific IP is banned
sudo fail2ban-client status sshd | grep <ip-address>

# View ban log
sudo tail -f /var/log/fail2ban.log
```

---

## 🔐 Access Control

### Who Can Access What?

**From Internet (WAN):**
```
✓ SSH to POD (port 22) - Authenticated users only
✓ HTTPS to POD (port 443) - Portal communication
✓ Stream Server (port 8000) - Video access
✗ Direct camera access - BLOCKED
✗ Other POD services - BLOCKED
```

**From Camera Network (LAN):**
```
✓ Full access to POD services
✓ Internet access through NAT
✓ DNS queries (8.8.8.8, 8.8.4.4)
✗ Cannot access WAN network directly
```

**From POD:**
```
✓ Full access to cameras
✓ Internet access
✓ All services
```

---

## 🚨 Incident Response

### Suspicious Activity Detected

**1. Check Firewall Logs:**
```bash
# View recent dropped packets
sudo tail -100 /var/log/syslog | grep iptables

# Count drops by source IP
sudo grep "iptables INPUT denied" /var/log/syslog | awk '{print $(NF-2)}' | sort | uniq -c | sort -rn
```

**2. Check Failed Logins:**
```bash
# Recent failed SSH attempts
sudo grep "Failed password" /var/log/auth.log | tail -20

# Group by IP
sudo grep "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn
```

**3. Manual IP Ban:**
```bash
# Ban specific IP immediately
sudo fail2ban-client set sshd banip <ip-address>

# Or block via iptables
sudo iptables -I INPUT -s <ip-address> -j DROP
sudo iptables-save > /etc/iptables/rules.v4
```

### Compromised Account

**1. Disable User:**
```bash
sudo usermod -L <username>  # Lock account
sudo passwd -l <username>   # Lock password
```

**2. Kill Sessions:**
```bash
# View active sessions
who

# Kill user sessions
sudo pkill -u <username>
```

**3. Review Access:**
```bash
# Check user's recent activity
sudo lastlog
sudo last -a <username>

# Check sudo commands
sudo grep <username> /var/log/auth.log | grep sudo
```

### Reset Security

**1. Clear All Bans:**
```bash
sudo fail2ban-client unban --all
```

**2. Reset Firewall:**
```bash
# Reapply rules
sudo iptables-restore < /etc/iptables/rules.v4
```

**3. Restart Security Services:**
```bash
sudo systemctl restart fail2ban
sudo systemctl restart ssh
```

---

## 🔧 Security Configuration Files

### Firewall Rules
```
Location: /etc/iptables/rules.v4
Backup:   /etc/iptables/rules.v4.backup
```

```bash
# View current rules
sudo iptables -L -v -n

# Save changes
sudo iptables-save > /etc/iptables/rules.v4

# Restore from backup
sudo iptables-restore < /etc/iptables/rules.v4.backup
```

### Fail2Ban Configuration
```
Global:  /etc/fail2ban/jail.local
Logs:    /var/log/fail2ban.log
```

```bash
# Edit configuration
sudo nano /etc/fail2ban/jail.local

# Restart after changes
sudo systemctl restart fail2ban
```

### SSH Configuration
```
Location: /etc/ssh/sshd_config
Backup:   /etc/ssh/sshd_config.backup
```

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Test configuration
sudo sshd -t

# Restart SSH
sudo systemctl restart sshd
```

### Network Configuration
```
Location: /etc/netplan/01-platebridge-network.yaml
```

```bash
# Edit network config
sudo nano /etc/netplan/01-platebridge-network.yaml

# Apply changes
sudo netplan apply
```

### Security Kernel Parameters
```
Location: /etc/sysctl.d/99-platebridge-security.conf
```

```bash
# Edit sysctl config
sudo nano /etc/sysctl.d/99-platebridge-security.conf

# Apply changes
sudo sysctl -p /etc/sysctl.d/99-platebridge-security.conf
```

---

## 📊 Security Audit Checklist

### Daily Checks

```bash
# 1. Check for banned IPs
sudo fail2ban-client status sshd

# 2. Check firewall drops
sudo tail -50 /var/log/syslog | grep iptables

# 3. Check SSH attempts
sudo grep "Failed password" /var/log/auth.log | tail -10

# 4. Check open connections
sudo ss -tulpn | grep ESTABLISHED
```

### Weekly Checks

```bash
# 1. Review security updates
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log

# 2. Check user logins
sudo last -a

# 3. Review firewall rules
sudo iptables -L -v -n | head -20

# 4. Check fail2ban log
sudo tail -100 /var/log/fail2ban.log
```

### Monthly Checks

```bash
# 1. Update all packages
sudo apt update && sudo apt upgrade -y

# 2. Review SSH config
sudo nano /etc/ssh/sshd_config

# 3. Backup configurations
sudo tar -czf ~/pod-config-backup-$(date +%Y%m%d).tar.gz \
    /etc/iptables \
    /etc/fail2ban \
    /etc/ssh/sshd_config \
    /etc/netplan \
    /opt/platebridge/docker

# 4. Test firewall
sudo iptables -L -v -n > ~/firewall-audit-$(date +%Y%m%d).txt
```

---

## 🆘 Emergency Procedures

### Lost SSH Access

**Option 1: Physical Access**
```bash
# Connect monitor and keyboard
# Login as user (not root - disabled)
# Fix SSH config
sudo nano /etc/ssh/sshd_config
sudo systemctl restart sshd
```

**Option 2: Cellular Console (if available)**
```bash
# Access through carrier's serial console
# Same as physical access
```

### Firewall Lockout

**If you locked yourself out:**
```bash
# Physical access required
# Flush firewall rules
sudo iptables -F
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Then reconfigure properly
```

### System Compromised

**Immediate Actions:**
```bash
# 1. Disconnect from internet
sudo ip link set enp3s0 down

# 2. Review all users
sudo cat /etc/passwd

# 3. Check for backdoors
sudo netstat -tulpn
sudo ps aux | grep -v "\["

# 4. Review cron jobs
sudo crontab -l
sudo ls -la /etc/cron.*

# 5. Check for suspicious files
sudo find / -mtime -1 -type f 2>/dev/null | grep -v "/proc\|/sys"
```

---

## 📚 Best Practices

### 1. SSH Keys (Highly Recommended)

**Generate SSH key:**
```bash
# On your local machine
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy to POD
ssh-copy-id user@pod-ip
```

**Disable password authentication:**
```bash
# On POD
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart sshd
```

### 2. Change Default SSH Port (Optional)

```bash
sudo nano /etc/ssh/sshd_config
# Change: Port 22 → Port 2222

# Update firewall
sudo iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
sudo iptables -D INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4

# Update fail2ban
sudo nano /etc/fail2ban/jail.local
# Change: port = 2222

sudo systemctl restart sshd
sudo systemctl restart fail2ban
```

### 3. Regular Backups

```bash
# Backup script
#!/bin/bash
BACKUP_DIR="/home/user/backups"
DATE=$(date +%Y%m%d)

mkdir -p $BACKUP_DIR

sudo tar -czf $BACKUP_DIR/pod-config-$DATE.tar.gz \
    /etc/iptables \
    /etc/fail2ban \
    /etc/ssh/sshd_config \
    /etc/netplan \
    /etc/sysctl.d/99-platebridge-security.conf \
    /opt/platebridge/docker/.env

# Keep only last 7 days
find $BACKUP_DIR -name "pod-config-*.tar.gz" -mtime +7 -delete
```

### 4. Monitor Logs

```bash
# Create log monitoring script
#!/bin/bash
echo "=== Failed SSH Attempts (Last 24h) ==="
sudo grep "Failed password" /var/log/auth.log | grep "$(date +%b\ %d)" | wc -l

echo "=== Banned IPs ==="
sudo fail2ban-client status sshd | grep "Banned IP"

echo "=== Firewall Drops (Last Hour) ==="
sudo grep "iptables INPUT denied" /var/log/syslog | grep "$(date +%b\ %d\ %H)" | wc -l

echo "=== Open Connections ==="
sudo ss -tunap | grep ESTABLISHED | wc -l
```

### 5. Document Changes

**Keep a change log:**
```
/opt/platebridge/CHANGELOG.md

# Example:
2025-10-11: Initial POD setup with security hardening
2025-10-12: Changed SSH port to 2222
2025-10-15: Added extra firewall rule for service X
```

---

## 🔗 Quick Reference

### Security Commands

```bash
# Firewall
sudo iptables -L -v -n              # View rules
sudo iptables-save > backup.rules   # Backup
sudo iptables-restore < backup      # Restore

# Fail2Ban
sudo fail2ban-client status         # Status
sudo fail2ban-client set sshd banip <ip>    # Ban IP
sudo fail2ban-client set sshd unbanip <ip>  # Unban IP

# SSH
sudo systemctl restart sshd         # Restart
sudo sshd -t                        # Test config
sudo tail -f /var/log/auth.log      # View logs

# Network
ip addr show                        # View interfaces
sudo ss -tulpn                      # View connections
sudo netplan apply                  # Apply network changes

# Security Updates
sudo apt update && sudo apt upgrade # Manual update
sudo unattended-upgrades --dry-run  # Test auto-updates
```

---

## 📞 Support

**Security Documentation:**
- This guide: `/opt/platebridge/pod-agent/POD_SECURITY_GUIDE.md`
- Network info: `/opt/platebridge/network-info.txt`
- Main docs: `/opt/platebridge/pod-agent/README.md`

**Log Locations:**
- Firewall: `/var/log/syslog`
- SSH: `/var/log/auth.log`
- Fail2Ban: `/var/log/fail2ban.log`
- Security Updates: `/var/log/unattended-upgrades/`

---

## ✅ Security Status Summary

**Your POD is secured with:**

- ✅ Firewall (iptables) with DROP default policy
- ✅ NAT for camera network isolation
- ✅ Anti-spoofing and DDoS protection
- ✅ SSH hardening (root login disabled)
- ✅ fail2ban (auto-ban brute force)
- ✅ Automatic security updates
- ✅ Camera network completely isolated
- ✅ Rate limiting on all services
- ✅ Comprehensive logging

**Your POD acts as a secure router between cellular WAN and camera LAN!** 🔒
