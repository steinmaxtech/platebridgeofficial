# 🎯 PlateBridge Golden Image - Complete Guide

## Overview

This guide walks through creating, testing, and deploying the PlateBridge POD Golden Base Image - a production-ready OS image that can be flashed to all POD hardware.

---

## 📦 What's Included

### Base System
- **OS:** Ubuntu 24.04 LTS (64-bit)
- **Kernel:** Latest stable Linux kernel
- **Init:** systemd

### Core Software
- **Docker:** Latest stable (CE)
- **Docker Compose:** v2.x
- **Python:** 3.10+
- **System tools:** curl, wget, jq, net-tools, etc.

### PlateBridge Components
- **platebridge-init.sh** - First-boot configuration & registration
- **platebridge-heartbeat.sh** - Periodic status reporting
- **systemd services** - Auto-start on boot
- **Directory structure** - Pre-configured paths

### Security
- **UFW firewall** - Pre-configured rules
- **Fail2ban** - SSH brute-force protection
- **Secure permissions** - Hardened file access
- **SELinux/AppArmor** - Optional security modules

### Remote Access (Optional)
- **Tailscale** - Zero-config VPN for maintenance
- **SSH** - Secure remote access

---

## 🔨 Building the Golden Image

### Prerequisites

**Hardware Requirements:**
- Clean Ubuntu 24.04 LTS installation
- Minimum 16GB disk space (recommended: 32GB+)
- 2GB+ RAM
- Network connectivity

**Software Requirements:**
- Root/sudo access
- Internet connection
- Basic Linux knowledge

### Step 1: Prepare Base System

```bash
# Install Ubuntu 24.04 LTS
# Use minimal server installation
# Configure network (DHCP recommended)
# Update system
sudo apt update && sudo apt upgrade -y
```

### Step 2: Run Golden Image Builder

```bash
# Clone or download scripts
cd /tmp
wget https://portal.platebridge.io/scripts/build-golden-image.sh
chmod +x build-golden-image.sh

# Run builder (takes 10-30 minutes)
sudo ./build-golden-image.sh

# Wait for completion
# The script will:
# - Install Docker + Compose
# - Set up PlateBridge system
# - Configure security
# - Install Tailscale
# - Optimize system
# - Clean up
```

### Step 3: Test the Image

```bash
# Run comprehensive tests
wget https://portal.platebridge.io/scripts/test-golden-image.sh
chmod +x test-golden-image.sh
sudo ./test-golden-image.sh

# Review test results
# All tests should pass before proceeding
```

### Step 4: Create Distributable Images

```bash
# Create deployment images
wget https://portal.platebridge.io/scripts/create-disk-image.sh
chmod +x create-disk-image.sh
sudo ./create-disk-image.sh

# This creates three formats:
# 1. Raw disk image (.img.xz) - for cloning
# 2. Bootable ISO (.iso) - for USB/CD
# 3. Tar archive (.tar.gz) - for VM/container
```

---

## 🧪 Testing Workflow

### Test 1: Virtual Machine Test

```bash
# Import image into VirtualBox/VMware
# Configure:
# - 2GB RAM minimum
# - 16GB disk minimum
# - Bridged networking
# - No USB config file (test prompt)

# Boot VM
# Expected behavior:
# 1. System boots to login
# 2. platebridge-init.service waits for config
# 3. No errors in logs
```

### Test 2: USB Configuration Test

```bash
# Create test config on USB drive
cat > /media/usb/platebridge-config.yaml <<EOF
portal_url: https://staging.platebridge.io
site_id: test-site-uuid-12345
EOF

# Insert USB and reboot
# Expected behavior:
# 1. System reads USB config
# 2. Registers with portal
# 3. Downloads docker-compose.yml
# 4. Starts services
# 5. Sends first heartbeat
```

### Test 3: Hardware Deployment Test

```bash
# Flash image to spare POD hardware
# Boot without configuration
# Connect to WiFi setup (if implemented)
# Or provide USB config
# Verify full functionality
```

### Test 4: Network Isolation Test

```bash
# Boot POD without network
# Expected behavior:
# 1. Boot completes successfully
# 2. Init service times out gracefully
# 3. System remains stable
# 4. Retries when network available
```

---

## 📀 Deployment Methods

### Method 1: Direct Disk Clone (Fastest)

**Use case:** Factory pre-loading, bulk production

```bash
# From golden master to target disk
sudo dd if=/dev/sda of=/dev/sdb bs=4M status=progress

# Or from image file
sudo dd if=platebridge-pod-v1.0.0.img of=/dev/sdb bs=4M status=progress

# Expand partition to fill disk
sudo growpart /dev/sdb 1
sudo resize2fs /dev/sdb1
```

**Pros:** Fastest, exact clone
**Cons:** Requires identical or larger disk

---

### Method 2: USB Bootable Installation

**Use case:** Field installation, non-standard hardware

```bash
# Create bootable USB from ISO
sudo dd if=platebridge-pod-v1.0.0.iso of=/dev/sdb bs=4M status=progress

# Or use Rufus (Windows) / Etcher (Mac/Linux)

# Boot from USB
# Follow installation prompts
# Remove USB and reboot
```

**Pros:** Works on any hardware, user-friendly
**Cons:** Slower, requires interaction

---

### Method 3: Network PXE Boot

**Use case:** Large-scale deployment, datacenter

```bash
# Set up PXE server
# Place golden image on TFTP server
# Configure DHCP for PXE boot
# PODs boot from network and auto-install
```

**Pros:** Zero-touch deployment at scale
**Cons:** Requires PXE infrastructure

---

### Method 4: Container/VM Import

**Use case:** Cloud deployment, testing

```bash
# Import tar archive
sudo tar -xzf platebridge-pod-v1.0.0.tar.gz -C /

# Or create Docker image
docker import platebridge-pod-v1.0.0.tar.gz platebridge/pod:1.0.0
```

**Pros:** Flexible, portable
**Cons:** Not for bare-metal production

---

## 🔧 Configuration Methods

### Method 1: USB Configuration File (Recommended)

**Create configuration file:**

```yaml
# platebridge-config.yaml
portal_url: https://portal.platebridge.io
site_id: abc-123-def-456-uuid

# Optional settings
timezone: America/New_York
hostname: pod-main-gate
static_ip: 192.168.1.100
gateway: 192.168.1.1
dns: 8.8.8.8
```

**Deploy:**
1. Copy file to USB drive root
2. Insert USB before first boot
3. POD auto-configures

---

### Method 2: Environment Variables

**Set before first boot:**

```bash
# In /etc/environment or systemd override
PLATEBRIDGE_PORTAL_URL=https://portal.platebridge.io
PLATEBRIDGE_SITE_ID=abc-123-def-456
```

---

### Method 3: Interactive Setup (WiFi AP)

**POD creates setup hotspot:**
1. Connect to "PlateBridge-Setup-XXXX"
2. Browser opens http://192.168.4.1
3. Enter portal URL and site ID
4. Click "Register"

*(Requires WiFi AP implementation)*

---

### Method 4: Pre-Provisioned Cloud Config

**For cloud deployments:**

```bash
# cloud-init config
cat > /etc/cloud/cloud.cfg.d/99-platebridge.cfg <<EOF
runcmd:
  - export PLATEBRIDGE_PORTAL_URL=https://portal.platebridge.io
  - export PLATEBRIDGE_SITE_ID=abc-123-def-456
  - /opt/platebridge/bin/platebridge-init.sh
EOF
```

---

## 📊 Validation Checklist

Before deploying to production, verify:

### Build Validation
- [ ] Golden image builds without errors
- [ ] All packages installed successfully
- [ ] Docker and Compose working
- [ ] PlateBridge scripts executable
- [ ] Systemd services enabled
- [ ] Security hardening applied
- [ ] Documentation included

### Functional Testing
- [ ] System boots successfully
- [ ] Network connectivity works (DHCP/Static)
- [ ] USB config detected and applied
- [ ] POD registers with portal
- [ ] Docker Compose downloads and runs
- [ ] Heartbeat service sends updates
- [ ] Cameras connect and stream
- [ ] Plate detection uploads
- [ ] Remote commands execute

### Security Testing
- [ ] Firewall rules active
- [ ] Fail2ban protecting SSH
- [ ] File permissions secure
- [ ] No default passwords
- [ ] SSH keys only (no password auth)
- [ ] Non-root user for services
- [ ] SELinux/AppArmor enforcing (optional)

### Performance Testing
- [ ] Boot time < 60 seconds
- [ ] CPU usage < 20% idle
- [ ] Memory usage < 500MB idle
- [ ] Disk I/O acceptable
- [ ] Network latency < 100ms
- [ ] Docker containers start quickly

### Recovery Testing
- [ ] Graceful shutdown/reboot
- [ ] Power loss recovery
- [ ] Network outage handling
- [ ] Disk full protection
- [ ] Service auto-restart
- [ ] Rollback mechanism

---

## 🗂️ Image Library Structure

Store golden images in organized library:

```
/opt/platebridge-images/
├── v1.0.0/
│   ├── platebridge-pod-v1.0.0-20251011.img.xz
│   ├── platebridge-pod-v1.0.0-20251011.iso
│   ├── platebridge-pod-v1.0.0-20251011.tar.gz
│   ├── SHA256SUMS.txt
│   ├── DEPLOYMENT.md
│   └── CHANGELOG.md
├── v1.0.1/
│   └── ...
└── latest -> v1.0.0
```

**Best practices:**
- Version each build (semantic versioning)
- Include build date in filename
- Generate checksums (SHA256)
- Document changes
- Keep at least 2 versions
- Symlink `latest` to current production version

---

## 🔄 Update Strategy

### Minor Updates (1.0.0 → 1.0.1)
- Security patches
- Bug fixes
- Configuration changes

**Deployment:** Over-the-air update via Docker Compose

```bash
# Portal sends update command
# POD pulls new compose file
# Services restart with new config
```

### Major Updates (1.0.0 → 2.0.0)
- OS upgrades
- Major feature changes
- Breaking changes

**Deployment:** New golden image

```bash
# Create new image v2.0.0
# Test thoroughly
# Schedule maintenance window
# Flash new image to PODs
```

---

## 🚨 Troubleshooting

### Issue: POD won't register

**Check:**
```bash
# View init logs
sudo journalctl -u platebridge-init.service -f

# Common causes:
# - No network connectivity
# - Wrong portal URL
# - Invalid site ID
# - Firewall blocking
```

### Issue: Docker won't start

**Check:**
```bash
# Docker status
sudo systemctl status docker

# Docker logs
sudo journalctl -u docker -f

# Common causes:
# - Disk full
# - Permission issues
# - Corrupted images
```

### Issue: Services crash on boot

**Check:**
```bash
# Service status
sudo systemctl status platebridge-*

# Container logs
cd /opt/platebridge/docker
docker compose logs

# Common causes:
# - Missing environment variables
# - Port conflicts
# - Resource constraints
```

---

## 📈 Monitoring & Maintenance

### Key Metrics to Monitor

1. **System Health**
   - CPU usage
   - Memory usage
   - Disk usage
   - Temperature

2. **Network Health**
   - Connectivity uptime
   - Latency
   - Bandwidth usage

3. **Service Health**
   - Docker container status
   - Heartbeat frequency
   - Detection upload rate

4. **Security Events**
   - Failed login attempts
   - Firewall blocks
   - Unusual traffic patterns

### Maintenance Schedule

**Daily:**
- Review heartbeat logs
- Check for failed services
- Monitor disk usage

**Weekly:**
- Review security logs
- Update Docker images
- Clean old recordings

**Monthly:**
- Apply security patches
- Review configurations
- Test backup/restore

**Quarterly:**
- Major version updates
- Hardware health check
- Performance optimization

---

## 📚 Additional Resources

### Documentation
- [POD Registration Guide](./POD_REGISTRATION_GUIDE.md)
- [Cloud Control API](./CLOUD_CONTROL_IMPLEMENTATION.md)
- [Deployment Verification](./DELIVERABLES_VERIFICATION.md)

### Scripts
- `build-golden-image.sh` - Build golden image
- `test-golden-image.sh` - Validate image
- `create-disk-image.sh` - Create deployable images

### Support
- Email: support@platebridge.io
- Portal: https://portal.platebridge.io
- Docs: https://docs.platebridge.io

---

## ✅ Deliverable Checklist

### Golden Image Package Should Include:

- [x] **Base OS:** Ubuntu 24.04 LTS
- [x] **Docker + Compose v2:** Latest stable
- [x] **platebridge-init.sh:** Auto-provisioning script
- [x] **systemd services:** Auto-start configuration
- [x] **Security hardening:** Firewall, fail2ban, permissions
- [x] **Remote access:** Tailscale pre-installed
- [x] **Documentation:** README, VERSION, deployment guide
- [x] **Test suite:** Comprehensive validation scripts
- [x] **Three image formats:** IMG, ISO, TAR
- [x] **Checksums:** SHA256 verification

### Storage Requirements:

- **Raw image (uncompressed):** ~8-12GB
- **Compressed image (.xz):** ~2-4GB
- **ISO image:** ~2-3GB
- **Tar archive:** ~2-3GB
- **Total storage needed:** ~10-15GB per version

---

## 🎉 Ready for Production!

Your golden image is now complete and ready for deployment!

**Next Steps:**
1. ✅ Store images in secure location
2. ✅ Document deployment procedures
3. ✅ Train installation technicians
4. ✅ Set up image version tracking
5. ✅ Create rollback plan
6. ✅ Begin production deployments

**The golden image is production-ready! 🚀**
