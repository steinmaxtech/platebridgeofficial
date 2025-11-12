# Golden Image Quick Start Guide

Create a production-ready PlateBridge POD image that can be flashed to any hardware.

---

## What is a Golden Image?

A **Golden Image** is a fully configured OS image containing:
- ✅ Ubuntu 24.04 LTS
- ✅ Docker + Compose
- ✅ PlateBridge agent
- ✅ Frigate NVR
- ✅ Security hardening
- ✅ Auto-provisioning scripts
- ✅ Tailscale for remote access

**Result:** Flash once → POD boots → Auto-registers → Production ready

---

## Quick Start (30 Minutes)

### Step 1: Prepare Base System

Start with a clean Ubuntu 24.04 LTS installation:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install git
sudo apt install -y git

# Clone repo
cd /tmp
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent
```

### Step 2: Run Complete Installation

This installs everything and configures the POD:

```bash
# Run the complete installer
sudo ./install-complete.sh

# When prompted:
# - Enter portal URL: https://platebridge.vercel.app
# - Enter registration token: [from portal]
# - Enter device name: Golden-Master
# - Enter Plate Recognizer credentials

# Wait for installation (~15-20 minutes)
```

### Step 3: Verify Everything Works

```bash
# Check all services are running
cd /opt/platebridge/docker
docker compose ps

# Should show all containers running:
# - platebridge-pod
# - frigate
# - mosquitto
# - platerecognizer

# Test the POD
sudo /opt/platebridge/pod-agent/health-check.sh

# All checks should pass ✓
```

### Step 4: Prepare for Imaging

Clean up system-specific data before creating the image:

```bash
# Stop services
cd /opt/platebridge/docker
sudo docker compose down

# Remove unique identifiers
sudo rm -f /opt/platebridge/docker/.env
sudo rm -f /opt/platebridge/config/config.yaml
sudo rm -f /var/lib/platebridge/pod-id
sudo rm -f /var/lib/dbus/machine-id
sudo rm -f /etc/machine-id

# Clear Tailscale state
sudo tailscale logout

# Clear logs
sudo journalctl --vacuum-time=1s
sudo rm -rf /var/log/*.log
sudo rm -rf /tmp/*

# Clear bash history
history -c
sudo rm -f ~/.bash_history
sudo rm -f /root/.bash_history

# Create placeholder for first-boot config
sudo mkdir -p /opt/platebridge/config
sudo touch /opt/platebridge/config/FIRST_BOOT_CONFIG_REQUIRED
```

### Step 5: Create Disk Images

Now create the distributable images:

```bash
# Go to golden image directory
cd /tmp/platebridge/pod-agent/golden-image

# Run image creator
sudo ./create-disk-image.sh

# This creates:
# 1. Raw disk image (.img.xz) - for dd cloning
# 2. Bootable ISO (.iso) - for USB installation
# 3. Tar archive (.tar.gz) - for VM/container

# Wait for completion (~20-30 minutes)
```

### Step 6: Collect Your Images

Images are created in `/opt/platebridge-images/`:

```bash
cd /opt/platebridge-images
ls -lh

# You should see:
# platebridge-pod-v1.0.0-20251112.img.xz  (~2-4GB)
# platebridge-pod-v1.0.0-20251112.iso     (~2-3GB)
# platebridge-pod-v1.0.0-20251112.tar.gz  (~2-3GB)
# SHA256SUMS.txt
# DEPLOYMENT.md

# Verify checksums
sha256sum -c SHA256SUMS.txt
```

---

## Deployment Methods

### Method 1: Flash to Hardware (Fastest)

**For production PODs - direct disk clone:**

```bash
# On a different machine with the target disk connected:

# Extract image
unxz platebridge-pod-v1.0.0-20251112.img.xz

# Flash to disk (REPLACE /dev/sdX WITH YOUR TARGET DISK!)
sudo dd if=platebridge-pod-v1.0.0-20251112.img of=/dev/sdX bs=4M status=progress

# Expand partition to fill disk
sudo growpart /dev/sdX 1
sudo resize2fs /dev/sdX1

# Done! Remove disk and install in POD
```

### Method 2: Create Bootable USB

**For field installation:**

```bash
# Flash ISO to USB drive (REPLACE /dev/sdX WITH YOUR USB!)
sudo dd if=platebridge-pod-v1.0.0-20251112.iso of=/dev/sdX bs=4M status=progress

# Or use balenaEtcher (GUI, cross-platform):
# https://www.balena.io/etcher/

# Boot POD from USB, follow prompts, remove USB when done
```

### Method 3: Virtual Machine

**For testing:**

```bash
# Import into VirtualBox/VMware
# - Create new Ubuntu 64-bit VM
# - Use the .img or .iso file
# - 2GB RAM minimum
# - Bridge network adapter

# Or import tar archive:
sudo tar -xzf platebridge-pod-v1.0.0-20251112.tar.gz -C /target
```

---

## First Boot Configuration

After flashing, PODs need to be configured on first boot.

### Option 1: USB Configuration File (Recommended)

**Most reliable for field deployment:**

1. **Create config file on USB drive:**

```yaml
# Save as: platebridge-config.yaml (on USB root)
portal_url: https://platebridge.vercel.app
community_id: your-community-uuid-here

# Optional
timezone: America/New_York
hostname: pod-main-gate
```

2. **Insert USB before first boot**
3. **POD auto-configures and registers**
4. **Remove USB after "Registration successful" message**

### Option 2: Generate Registration Token

**For hands-off deployment:**

```bash
# 1. Generate token from portal:
#    Go to: Communities → Your Community → Tokens
#    Click: "Generate Registration Token"
#    Copy the token

# 2. Add to USB config:
portal_url: https://platebridge.vercel.app
registration_token: pbr_1234567890abcdef

# 3. POD auto-registers with token
```

### Option 3: Pre-Provision (Advanced)

**For cloud/VM deployments:**

```bash
# Set environment variables before first boot
sudo tee -a /etc/environment << EOF
PLATEBRIDGE_PORTAL_URL=https://platebridge.vercel.app
PLATEBRIDGE_COMMUNITY_ID=your-community-uuid
EOF
```

---

## Testing Your Golden Image

Before mass deployment, test thoroughly:

### Test 1: Fresh Install Test

```bash
# Flash image to test hardware
# Boot without configuration
# Expected: POD waits for config, shows setup instructions
```

### Test 2: USB Config Test

```bash
# Create USB config file
# Insert USB and boot
# Expected:
# - POD reads config
# - Registers with portal
# - Starts services
# - Sends first heartbeat
```

### Test 3: Network Test

```bash
# Boot POD with WAN connected
# Check portal shows POD online
# Access Frigate at: http://<pod-ip>:5000
# Check Tailscale: tailscale status
```

### Test 4: Camera Test

```bash
# Connect camera to LAN port
# Camera should get DHCP IP
# Run discovery: sudo /opt/platebridge/discover-cameras.sh
# Add camera to Frigate config
# Verify stream works
```

---

## What Gets Pre-Configured

When you create a golden image from a working POD, it includes:

✅ **System:**
- Ubuntu 24.04 LTS fully updated
- Dual-NIC network configuration
- Firewall with security rules
- Automatic security updates
- SSH hardening

✅ **Docker:**
- Docker Engine latest
- Docker Compose v2
- Pre-pulled images (Frigate, Mosquitto, etc.)

✅ **PlateBridge:**
- POD agent installed
- Auto-start systemd services
- Directory structure created
- Configuration templates

✅ **Security:**
- fail2ban configured
- iptables firewall rules
- Non-root service user
- Secure permissions

✅ **Remote Access:**
- Tailscale installed
- Auto-enable on first boot

✅ **Scripts:**
- Camera discovery
- Health check
- Network diagnostics
- DHCP troubleshooting

---

## What Gets Configured Per-POD

Each POD needs unique configuration:

🔧 **Required:**
- Portal URL
- Community ID or Registration Token
- API Key (auto-generated on registration)

🔧 **Optional:**
- Hostname
- Static IP (default: DHCP)
- Timezone
- Tailscale auth key

---

## Mass Deployment Workflow

For deploying 10, 100, or 1000 PODs:

### Factory Pre-Loading

```bash
# 1. Create golden image once
# 2. Mass-produce disks with dd cloning
# 3. Generate registration tokens in bulk
# 4. Create USB config files per site
# 5. Ship POD + USB config
```

### Field Installation

```bash
# Technician process:
# 1. Install POD hardware
# 2. Connect WAN (cellular/ethernet)
# 3. Connect LAN (cameras)
# 4. Insert USB config
# 5. Power on
# 6. Wait for green light / online status
# 7. Remove USB
# 8. Done!
```

### Portal Management

```bash
# Admin monitors:
# 1. POD registration (real-time)
# 2. First heartbeat received
# 3. Services online
# 4. Cameras detected
# 5. Plates being detected
```

---

## Storage Requirements

### Golden Image Creation:

- **Temporary space:** ~30GB (during build)
- **Final images:** ~10GB total
  - .img.xz: ~2-4GB
  - .iso: ~2-3GB
  - .tar.gz: ~2-3GB

### Per-POD Storage:

- **OS + Software:** ~8GB
- **Docker images:** ~4GB
- **Recordings:** Depends on USB size
- **Total system disk:** 16GB minimum (32GB+ recommended)

---

## Version Management

Maintain multiple versions:

```
/opt/platebridge-images/
├── v1.0.0/
│   ├── platebridge-pod-v1.0.0-20251112.img.xz
│   ├── platebridge-pod-v1.0.0-20251112.iso
│   ├── platebridge-pod-v1.0.0-20251112.tar.gz
│   ├── SHA256SUMS.txt
│   ├── DEPLOYMENT.md
│   └── CHANGELOG.md
├── v1.0.1/
│   └── [security patch images]
├── v1.1.0/
│   └── [feature release images]
└── latest -> v1.0.0
```

**Best practices:**
- Keep at least 2 versions
- Document changes in CHANGELOG.md
- Test thoroughly before release
- Symlink `latest` to current stable

---

## Update Strategy

### Minor Updates (Over-the-Air)

For small changes, update via portal:

```bash
# Portal sends update command
# POD pulls new docker-compose.yml
# Containers restart with new config
# No reimaging needed
```

### Major Updates (New Golden Image)

For OS upgrades or major changes:

```bash
# Create new golden image (v2.0.0)
# Test thoroughly
# Schedule maintenance windows
# Flash new image to PODs
```

---

## Troubleshooting

### Image Won't Boot

```bash
# Check boot sector
sudo dd if=/dev/sdX bs=512 count=1 | hexdump -C

# Verify image integrity
sha256sum platebridge-pod-v1.0.0-20251112.img.xz
```

### POD Won't Register

```bash
# Check init logs
sudo journalctl -u platebridge-init.service -f

# Common issues:
# - No network connectivity
# - Wrong portal URL
# - Invalid token
# - USB config not found
```

### Services Won't Start

```bash
# Check Docker
sudo systemctl status docker
docker ps

# Check compose
cd /opt/platebridge/docker
docker compose logs

# Restart everything
docker compose restart
```

---

## Support & Resources

**Documentation:**
- Full guide: `pod-agent/golden-image/GOLDEN_IMAGE_GUIDE.md`
- Deployment: `/opt/platebridge-images/DEPLOYMENT.md`
- POD setup: `POD_AUTONOMOUS_SETUP.md`

**Scripts:**
- Build: `pod-agent/golden-image/build-golden-image.sh` (not in repo)
- Test: `pod-agent/golden-image/test-golden-image.sh`
- Create: `pod-agent/golden-image/create-disk-image.sh`

**Commands:**
```bash
# Create images
cd /tmp/platebridge/pod-agent/golden-image
sudo ./create-disk-image.sh

# Test health
sudo /opt/platebridge/pod-agent/health-check.sh

# View logs
sudo journalctl -u platebridge-init.service -f
```

---

## Success Checklist

Before deploying to production:

- [ ] Golden image builds successfully
- [ ] All services start on boot
- [ ] USB config auto-detected
- [ ] POD registers with portal
- [ ] Heartbeat sends successfully
- [ ] Docker containers running
- [ ] Cameras get DHCP leases
- [ ] Frigate streams work
- [ ] Plate detection uploads
- [ ] Tailscale connects
- [ ] Security hardening applied
- [ ] Checksums verified
- [ ] Documentation complete

---

## Quick Commands Reference

```bash
# Create golden image
cd /tmp/platebridge/pod-agent/golden-image
sudo ./create-disk-image.sh

# Flash to disk
sudo dd if=image.img of=/dev/sdX bs=4M status=progress

# Create USB config
cat > /media/usb/platebridge-config.yaml <<EOF
portal_url: https://platebridge.vercel.app
registration_token: pbr_your_token_here
EOF

# Check POD status
sudo systemctl status platebridge-init.service
docker ps
sudo /opt/platebridge/pod-agent/health-check.sh

# View logs
sudo journalctl -u platebridge-init.service -f
docker logs platebridge-pod -f

# Reset POD for reimaging
sudo rm /var/lib/platebridge/initialized
sudo reboot
```

---

## You're Ready! 🚀

Your golden image workflow:

1. ✅ Install Ubuntu on master system
2. ✅ Run `install-complete.sh` to set everything up
3. ✅ Test thoroughly
4. ✅ Clean system-specific data
5. ✅ Run `create-disk-image.sh` to create images
6. ✅ Flash to production hardware
7. ✅ Deploy with USB config
8. ✅ Monitor via portal

**Golden images enable zero-touch POD deployment at any scale!**
