# 🎯 PlateBridge POD Golden Base Image

## Overview

This directory contains everything needed to create, test, and deploy the **PlateBridge POD Golden Base Image** - a production-ready operating system image that can be flashed to all POD hardware for rapid deployment.

---

## 📦 What's Included

### Scripts

| Script | Purpose | Runtime |
|--------|---------|---------|
| `build-golden-image.sh` | Builds the golden image from scratch | 10-30 min |
| `test-golden-image.sh` | Validates all components | 2-5 min |
| `create-disk-image.sh` | Creates deployable image files | 10-60 min |

### Documentation

| Document | Description |
|----------|-------------|
| `QUICK_START.md` | Get started in 5 minutes |
| `GOLDEN_IMAGE_GUIDE.md` | Complete reference guide |
| `DEPLOYMENT.md` | Deployment instructions (auto-generated) |

---

## 🚀 Quick Start

### TL;DR

```bash
# 1. Build
sudo ./build-golden-image.sh

# 2. Test
sudo ./test-golden-image.sh

# 3. Create images
sudo ./create-disk-image.sh

# 4. Deploy
sudo dd if=output/platebridge-pod-v1.0.0.img of=/dev/sdX bs=4M status=progress
```

---

## 📋 Prerequisites

**System Requirements:**
- Ubuntu 22.04 LTS (clean installation)
- 16GB+ disk space (32GB recommended)
- 2GB+ RAM
- Root/sudo access
- Internet connectivity

**Target Hardware:**
- x86_64 architecture
- 8GB+ storage
- 1GB+ RAM
- Network interface (Ethernet or WiFi)

---

## 🔨 Build Process

### Step 1: Prepare Base System

Start with a clean Ubuntu 22.04 LTS installation:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Clone or download scripts
git clone https://github.com/platebridge/golden-image.git
cd golden-image
```

### Step 2: Run Builder

```bash
# Make scripts executable (if needed)
chmod +x *.sh

# Run golden image builder
sudo ./build-golden-image.sh
```

**What it does:**
1. ✅ Installs Docker + Compose v2
2. ✅ Sets up PlateBridge system directories
3. ✅ Installs auto-provisioning scripts
4. ✅ Creates systemd services
5. ✅ Configures security (firewall, fail2ban)
6. ✅ Installs Tailscale for remote access
7. ✅ Optimizes system parameters
8. ✅ Cleans up and finalizes

**Expected output:**
```
[INFO] Starting PlateBridge Golden Image Build
[INFO] PHASE 1: Setting up base OS
[INFO] PHASE 2: Installing Docker + Compose v2
[INFO] PHASE 3: Installing PlateBridge system files
[INFO] PHASE 4: Security hardening
[INFO] PHASE 5: Setting up remote access
[INFO] PHASE 6: System optimization
[INFO] PHASE 7: Cleanup and finalization
[SUCCESS] Golden Image Build Complete!
```

### Step 3: Validate

```bash
# Run comprehensive test suite
sudo ./test-golden-image.sh
```

**What it tests:**
- ✅ System requirements (Ubuntu 22.04, 64-bit, systemd)
- ✅ Docker installation and configuration
- ✅ PlateBridge system files and directories
- ✅ Systemd services (init, heartbeat)
- ✅ Security configuration (UFW, fail2ban)
- ✅ Network tools (curl, wget, jq, dig)
- ✅ Remote access (Tailscale)
- ✅ System optimization
- ✅ Functional tests (Docker pull, networking, DNS)
- ✅ Disk space analysis
- ✅ Performance metrics

**Expected output:**
```
✅ All tests passed! Golden image is ready for production.
```

### Step 4: Create Deployment Images

```bash
# Generate distributable image files
sudo ./create-disk-image.sh
```

**Creates three formats:**

1. **Raw Disk Image** (`.img.xz`)
   - For direct disk cloning
   - Exact replica of golden system
   - ~2-4GB compressed

2. **Bootable ISO** (`.iso`)
   - For USB/CD installation
   - Bootable on any compatible hardware
   - ~2-3GB

3. **Tar Archive** (`.tar.gz`)
   - For VM/container deployment
   - Portable filesystem archive
   - ~2-3GB

**Output location:** `/opt/platebridge-images/`

---

## 📀 Deployment

### Quick Deploy to USB/Disk

```bash
# Find target device
lsblk

# Flash image (replace /dev/sdX with your device)
# WARNING: This will erase all data on the target device!
sudo unxz -c platebridge-pod-v1.0.0.img.xz | sudo dd of=/dev/sdX bs=4M status=progress

# Or for uncompressed image
sudo dd if=platebridge-pod-v1.0.0.img of=/dev/sdX bs=4M status=progress

# Expand partition (if target disk is larger)
sudo growpart /dev/sdX 1
sudo resize2fs /dev/sdX1
```

### Create Bootable USB Installer

```bash
# Using ISO file
sudo dd if=platebridge-pod-v1.0.0.iso of=/dev/sdX bs=4M status=progress

# Or use GUI tools:
# - Rufus (Windows)
# - Etcher (Mac/Linux)
# - UNetbootin (cross-platform)
```

---

## ⚙️ First Boot Configuration

The POD needs configuration to register with the portal. Choose one method:

### Method 1: USB Configuration File (Recommended)

**Create config file on USB drive:**

```yaml
# File: platebridge-config.yaml (USB root)
portal_url: https://portal.platebridge.io
site_id: abc-123-def-456-uuid-from-portal

# Optional settings
timezone: America/New_York
hostname: pod-main-entrance
static_ip: 192.168.1.100
gateway: 192.168.1.1
dns: 8.8.8.8
```

**Usage:**
1. Create file on USB drive
2. Insert USB before POD first boot
3. POD auto-detects and configures
4. Remove USB after registration complete

### Method 2: Environment Variables

```bash
# Set before first boot
export PLATEBRIDGE_PORTAL_URL="https://portal.platebridge.io"
export PLATEBRIDGE_SITE_ID="abc-123-def-456"
```

### Method 3: QR Code (Requires Camera)

1. Admin generates QR code in portal
2. Show QR code to POD camera during setup
3. POD scans and auto-configures

### Method 4: WiFi Setup Interface

1. POD creates WiFi hotspot: `PlateBridge-Setup-XXXX`
2. Connect with phone/laptop
3. Browser opens setup page
4. Enter portal URL and site ID
5. POD registers automatically

---

## 🔍 Verification

### Check Registration Status

```bash
# View initialization logs
sudo journalctl -u platebridge-init.service -f

# Check if POD is initialized
cat /var/lib/platebridge/initialized

# View configuration
sudo cat /opt/platebridge/config/pod.conf
```

### Check Services

```bash
# Heartbeat service
sudo systemctl status platebridge-heartbeat.timer

# Docker services
cd /opt/platebridge/docker
docker compose ps
```

### Check Portal

1. Navigate to portal: https://portal.platebridge.io/pods
2. Find your POD by serial number
3. Verify status shows "Online"
4. Check metrics are updating

---

## 📊 System Layout

```
/opt/platebridge/
├── bin/
│   ├── platebridge-init.sh          ← First-boot registration
│   └── platebridge-heartbeat.sh     ← Periodic status updates
├── config/
│   └── pod.conf                     ← POD configuration (after init)
├── docker/
│   ├── docker-compose.yml           ← Downloaded from portal
│   └── .env                         ← Environment variables
├── logs/
│   └── init.log                     ← Initialization logs
├── recordings/                      ← Video recordings
├── data/                            ← Application data
├── VERSION                          ← Image version info
└── README.md                        ← System documentation

/var/lib/platebridge/
└── initialized                      ← Marker file (init complete)

/etc/systemd/system/
├── platebridge-init.service         ← One-time registration
├── platebridge-heartbeat.service    ← Status reporting
└── platebridge-heartbeat.timer      ← Runs every 60 seconds
```

---

## 🔧 Maintenance

### Update Golden Image

```bash
# Apply system updates
sudo apt update && sudo apt upgrade -y

# Update PlateBridge scripts
sudo wget -O /opt/platebridge/bin/platebridge-init.sh \
  https://portal.platebridge.io/scripts/platebridge-init.sh

# Rebuild image
sudo ./build-golden-image.sh
```

### Reset POD

```bash
# Clear initialization state
sudo rm /var/lib/platebridge/initialized

# Clear configuration
sudo rm /opt/platebridge/config/pod.conf

# Reboot
sudo reboot
```

### Backup Configuration

```bash
# Backup POD config
sudo tar -czf pod-backup.tar.gz /opt/platebridge/config

# Restore
sudo tar -xzf pod-backup.tar.gz -C /
```

---

## 🚨 Troubleshooting

### Issue: POD won't register

```bash
# Check logs
sudo journalctl -u platebridge-init.service -f

# Common causes:
# - No network connectivity: ping 8.8.8.8
# - Wrong portal URL: check config
# - Invalid site ID: verify in portal
# - Firewall blocking: sudo ufw status
```

### Issue: Docker won't start

```bash
# Check Docker
sudo systemctl status docker

# View logs
sudo journalctl -u docker -f

# Restart Docker
sudo systemctl restart docker
```

### Issue: Services keep crashing

```bash
# Check Docker Compose
cd /opt/platebridge/docker
docker compose logs

# Check resources
free -h
df -h
docker stats
```

---

## 📈 Production Checklist

Before deploying to production:

- [ ] Golden image builds successfully
- [ ] All tests pass (test-golden-image.sh)
- [ ] Deployment images created
- [ ] Test deployment on spare hardware
- [ ] USB configuration works
- [ ] POD registers with portal
- [ ] Services start automatically
- [ ] Heartbeat updates visible in portal
- [ ] Remote access configured
- [ ] Rollback procedure documented
- [ ] Technician training completed
- [ ] Image stored in library

---

## 📚 Additional Resources

- **Full Guide:** [GOLDEN_IMAGE_GUIDE.md](./GOLDEN_IMAGE_GUIDE.md)
- **Quick Start:** [QUICK_START.md](./QUICK_START.md)
- **POD Registration:** [../POD_REGISTRATION_GUIDE.md](../POD_REGISTRATION_GUIDE.md)
- **Portal Documentation:** https://docs.platebridge.io

---

## 🎯 Deliverable Summary

✅ **One tested Golden Image** ready for production
✅ **Three deployment formats** (IMG, ISO, TAR)
✅ **Auto-provisioning script** (platebridge-init.sh)
✅ **Comprehensive test suite** (validates all components)
✅ **Complete documentation** (deployment guides)
✅ **Version management** (stored in internal library)

---

## 📞 Support

- **Email:** support@platebridge.io
- **Portal:** https://portal.platebridge.io
- **Documentation:** https://docs.platebridge.io
- **GitHub:** https://github.com/platebridge/pod

---

## 📄 License

Copyright © 2025 PlateBridge. All rights reserved.

---

**Version:** 1.0.0
**Last Updated:** October 2025
**Status:** ✅ Production Ready
