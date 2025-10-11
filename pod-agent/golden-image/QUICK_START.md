# 🚀 Golden Image Quick Start

## One-Command Build

```bash
# Download and run
curl -fsSL https://portal.platebridge.io/scripts/build-golden-image.sh | sudo bash
```

---

## Manual Build (Recommended)

### Step 1: Build Golden Image
```bash
sudo ./build-golden-image.sh
# Takes 10-30 minutes
# Creates production-ready system
```

### Step 2: Test the Image
```bash
sudo ./test-golden-image.sh
# Validates all components
# Must pass before deployment
```

### Step 3: Create Deployment Images
```bash
sudo ./create-disk-image.sh
# Creates 3 formats:
# - .img.xz (raw disk)
# - .iso (bootable USB)
# - .tar.gz (VM/container)
```

---

## What Gets Installed

✅ Ubuntu 22.04 LTS
✅ Docker + Compose v2
✅ PlateBridge auto-provisioning
✅ Security hardening (UFW, fail2ban)
✅ Tailscale (optional remote access)
✅ Systemd services (auto-start)

---

## Quick Deploy to USB

```bash
# Find USB device
lsblk

# Flash image (replace /dev/sdX)
sudo dd if=platebridge-pod-v1.0.0.img.xz | unxz | sudo dd of=/dev/sdX bs=4M status=progress
```

---

## First Boot Configuration

### Option 1: USB Config (Easiest)
```yaml
# Create: platebridge-config.yaml on USB root
portal_url: https://portal.platebridge.io
site_id: your-site-uuid-here
```

### Option 2: Environment Variables
```bash
export PLATEBRIDGE_PORTAL_URL="https://portal.platebridge.io"
export PLATEBRIDGE_SITE_ID="your-site-uuid"
```

---

## Verify Deployment

```bash
# Check registration
sudo journalctl -u platebridge-init.service

# Check heartbeat
sudo systemctl status platebridge-heartbeat.timer

# Check Docker services
cd /opt/platebridge/docker && docker compose ps
```

---

## Troubleshooting

**Won't register:**
```bash
sudo journalctl -u platebridge-init.service -f
```

**Reset POD:**
```bash
sudo rm /var/lib/platebridge/initialized
sudo reboot
```

---

## Files Created

```
/opt/platebridge-images/
├── platebridge-pod-v1.0.0-YYYYMMDD.img.xz  ← Flash to disk
├── platebridge-pod-v1.0.0-YYYYMMDD.iso     ← Bootable USB
├── platebridge-pod-v1.0.0-YYYYMMDD.tar.gz  ← VM/Container
├── SHA256SUMS.txt                           ← Checksums
└── DEPLOYMENT.md                            ← Full guide
```

---

## Support

📚 Full docs: `GOLDEN_IMAGE_GUIDE.md`
🔧 Portal: https://portal.platebridge.io
📧 Email: support@platebridge.io

---

**Build time:** ~20 minutes
**Image size:** ~2-4GB (compressed)
**Boot time:** ~60 seconds
**Auto-provision:** ~2 minutes

✅ **Ready for production deployment!**
