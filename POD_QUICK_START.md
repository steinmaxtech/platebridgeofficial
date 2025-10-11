# 🚀 POD Quick Start Guide

Get your PlateBridge POD running in 30 minutes or less!

---

## 📦 Prerequisites

Before you start, you'll need:

**Hardware:**
- POD device (8GB+ storage, 1GB+ RAM recommended)
- USB camera or IP camera
- Network connection (Ethernet or WiFi)
- For dual-NIC setup: Device with 2 Ethernet ports

**Software:**
- Ubuntu Server 24.04 LTS ([Download](https://ubuntu.com/download/server))
- Internet connection for initial setup

**Portal Account:**
- PlateBridge portal access
- Site created in portal
- Note your portal URL and site ID

---

## 📥 Quick Clone (All Methods)

**Get the PlateBridge software:**

```bash
# Install git
sudo apt update && sudo apt install -y git

# Clone repository
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent

# Make scripts executable
chmod +x *.sh
```

**Or download scripts individually:**
```bash
# Create directory
mkdir -p ~/platebridge/pod-agent && cd ~/platebridge/pod-agent

# Download scripts
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/setup.sh -o setup.sh
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/network-config.sh -o network-config.sh
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/discover-cameras.sh -o discover-cameras.sh
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/config-dual-nic.yaml -o config-dual-nic.yaml

# Make executable
chmod +x *.sh
```

---

## 🎯 Choose Your Path

### **Method 1: Golden Image (Production) - 10 min**
✅ Best for: Multiple PODs, production deployment
✅ Pre-built, tested, ready to flash
✅ Requires: Golden image file + USB drive

### **Method 2: Auto Install Script - 20 min**
✅ Best for: Development, single POD
✅ Fresh Ubuntu install + one command
✅ Requires: Ubuntu 24.04 installed

### **Method 3: Manual Docker - 5 min**
✅ Best for: Quick testing
✅ Existing Ubuntu system
✅ Requires: Docker installed

---

# 🚀 Method 1: Golden Image (Recommended)

## What You Need
- POD hardware (8GB+ storage, 1GB+ RAM)
- Golden image file (`.img.xz` or `.iso`)
- USB drive (4GB+ for config)
- Network connection

## Step 1: Flash Image to POD

**Option A: Direct disk clone (fastest)**
```bash
# Decompress
unxz platebridge-pod-v1.0.0.img.xz

# Flash to POD disk
sudo dd if=platebridge-pod-v1.0.0.img of=/dev/sdX bs=4M status=progress

# Expand to use full disk
sudo growpart /dev/sdX 1
sudo resize2fs /dev/sdX1
```

**Option B: Bootable USB install**
```bash
# Flash ISO to USB
sudo dd if=platebridge-pod-v1.0.0.iso of=/dev/sdX bs=4M

# Or use balenaEtcher (GUI)
```

## Step 2: Create Config USB

**On any computer, create file on USB root:**

`platebridge-config.yaml`:
```yaml
portal_url: https://your-portal.platebridge.io
site_id: abc-123-def-456
```

**Optional settings:**
```yaml
portal_url: https://your-portal.platebridge.io
site_id: abc-123-def-456
timezone: America/New_York
hostname: pod-main-gate
static_ip: 192.168.1.100
gateway: 192.168.1.1
dns: 8.8.8.8
```

## Step 3: Boot POD

1. Insert config USB
2. Connect network cable
3. Power on
4. Wait 2-3 minutes

**What happens automatically:**
- ✅ Reads USB config
- ✅ Registers with portal
- ✅ Downloads docker-compose.yml
- ✅ Starts services
- ✅ Sends heartbeat

## Step 4: Verify in Portal

Navigate to: `https://your-portal.platebridge.io/pods`

You should see:
- 🟢 POD status: Online
- Last seen: "Just now"
- Cameras: 0 (until you add them)

**Done! POD is running! 🎉**

---

# 🛠️ Method 2: Auto Install Script

## Step 1: Install Ubuntu 24.04

1. Download [Ubuntu Server 24.04 LTS](https://ubuntu.com/download/server)
2. Create bootable USB with balenaEtcher
3. Install on POD hardware
4. Enable SSH during install
5. Update system:
```bash
sudo apt update && sudo apt upgrade -y
```

## Step 2: Clone PlateBridge Repository

```bash
# Install git
sudo apt install -y git

# Clone the repository
git clone https://github.com/your-org/platebridge.git
cd platebridge

# Or download the scripts directly
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/setup.sh -o setup.sh
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/network-config.sh -o network-config.sh
curl -fsSL https://raw.githubusercontent.com/your-org/platebridge/main/pod-agent/discover-cameras.sh -o discover-cameras.sh
chmod +x *.sh
```

## Step 3: Run Install Script

**From cloned repository:**
```bash
cd platebridge/pod-agent
sudo ./setup.sh
```

**Or download from portal:**
```bash
curl -fsSL https://your-portal.platebridge.io/install-pod.sh -o install-pod.sh
chmod +x install-pod.sh
sudo ./install-pod.sh
```

**Script will prompt:**
```
Enter Portal URL: https://your-portal.platebridge.io
Enter Site ID: abc-123-def-456
```

**Installation includes:**
- ✅ Docker + Compose
- ✅ PlateBridge directories
- ✅ Auto-registration
- ✅ Service startup
- ✅ Heartbeat setup

**Takes 10-15 minutes**

## Step 4: Verify

```bash
# Check services
cd /opt/platebridge/docker
docker compose ps

# View logs
docker compose logs -f
```

**Check portal:** `https://your-portal.platebridge.io/pods`

**Done! POD is running! 🎉**

---

# 🐳 Method 3: Manual Docker (Quick Test)

## Step 1: Clone Repository

```bash
# Install git and clone repo
sudo apt install -y git
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent
```

## Step 2: Install Docker

```bash
# Quick Docker install
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

## Step 3: Create Docker Compose

**Option A: Use provided config**
```bash
# Copy example config
cp config-dual-nic.yaml /opt/platebridge/config.yaml
nano /opt/platebridge/config.yaml
```

**Option B: Create from scratch**
```bash
mkdir ~/platebridge-pod
cd ~/platebridge-pod
nano docker-compose.yml
```

**Minimal compose file:**
```yaml
version: '3.8'

services:
  agent:
    image: platebridge/pod-agent:latest
    restart: unless-stopped
    privileged: true
    network_mode: host
    volumes:
      - ./data:/data
      - ./recordings:/recordings
      - /dev:/dev
    environment:
      - POD_ID=${POD_ID}
      - API_KEY=${API_KEY}
      - PORTAL_URL=${PORTAL_URL}
    devices:
      - /dev/video0:/dev/video0

  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    restart: unless-stopped
    volumes:
      - ./frigate:/config
      - ./recordings:/media/frigate
    ports:
      - "5000:5000"
      - "8554:8554"
```

## Step 4: Configure

**Create `.env` file:**
```bash
POD_ID=your-pod-uuid
API_KEY=your-api-key
PORTAL_URL=https://your-portal.platebridge.io
```

**Get these values:**
1. Go to portal
2. Navigate to Sites → Your Site
3. Click "Add POD"
4. Copy POD_ID and API_KEY

## Step 5: Start

```bash
docker compose pull
docker compose up -d
docker compose logs -f
```

**Done! POD is running! 🎉**

---

# 📹 Adding Cameras

## USB Camera

1. **Plug in USB camera**
2. **Verify detected:**
```bash
ls -la /dev/video*
```
3. **Auto-configured!** POD detects and sets up automatically

## Network Camera (RTSP)

**Via Portal:**
1. Go to Cameras page
2. Click "Add Camera"
3. Enter: `rtsp://username:password@192.168.1.100:554/stream`
4. Save

**Camera starts streaming immediately!**

---

# 🧪 Test Your POD

## Test 1: Check Status
```bash
# Portal: https://your-portal.platebridge.io/pods
# Should see: 🟢 Online
```

## Test 2: Test Camera
```bash
# Show license plate to camera
# Portal: Navigate to /plates
# Should see new detection appear
```

## Test 3: Remote Command
```bash
# Portal: Open POD detail
# Click "Test Cameras"
# Check Command History tab
# Status: Queued → Completed
```

---

# 🔧 Troubleshooting

## POD Won't Register

**Check network:**
```bash
ping 8.8.8.8
curl https://your-portal.platebridge.io
```

**Check logs:**
```bash
sudo journalctl -u platebridge-init.service -f
```

**Fix:**
- Verify portal URL is correct
- Verify site ID is correct
- Check firewall settings

## POD Shows Offline

**Restart heartbeat:**
```bash
sudo systemctl restart platebridge-heartbeat.timer
```

**Manual test:**
```bash
/opt/platebridge/bin/platebridge-heartbeat.sh
```

## Camera Not Working

**Check USB:**
```bash
lsusb
ls -la /dev/video*
```

**Restart services:**
```bash
cd /opt/platebridge/docker
docker compose restart
```

---

# 📊 Health Check Script

```bash
#!/bin/bash
echo "=== POD Health Check ==="

# Initialized?
[ -f /var/lib/platebridge/initialized ] && echo "✅ Initialized" || echo "❌ Not initialized"

# Docker running?
systemctl is-active docker >/dev/null && echo "✅ Docker running" || echo "❌ Docker down"

# Services running?
cd /opt/platebridge/docker 2>/dev/null
if [ $? -eq 0 ]; then
    docker compose ps
else
    echo "❌ No services found"
fi

# Heartbeat active?
systemctl is-active platebridge-heartbeat.timer >/dev/null && echo "✅ Heartbeat active" || echo "❌ Heartbeat down"

# Cameras?
echo "Cameras: $(ls -1 /dev/video* 2>/dev/null | wc -l)"

# Network?
ping -c 1 8.8.8.8 >/dev/null && echo "✅ Network OK" || echo "❌ Network down"

echo "=== Check Complete ==="
```

---

# 📁 Important Locations

```
/opt/platebridge/
├── bin/
│   ├── platebridge-init.sh      # First boot setup
│   └── platebridge-heartbeat.sh # Status reporting
├── config/
│   └── pod.conf                 # POD settings
├── docker/
│   ├── docker-compose.yml       # Services
│   └── .env                     # Environment
├── logs/
│   └── init.log                 # Init log
└── recordings/                  # Video files
```

---

# 🎯 Quick Commands

```bash
# View logs
sudo journalctl -u platebridge-init.service -f

# Check services
cd /opt/platebridge/docker && docker compose ps

# Restart services
cd /opt/platebridge/docker && docker compose restart

# Update services
cd /opt/platebridge/docker && docker compose pull && docker compose up -d

# Manual heartbeat
/opt/platebridge/bin/platebridge-heartbeat.sh

# Re-initialize
sudo rm /var/lib/platebridge/initialized && sudo reboot
```

---

# 📚 Next Steps

1. ✅ **Add cameras** - USB or network cameras
2. ✅ **Test detection** - Show license plate
3. ✅ **Set up alerts** - Configure notifications
4. ✅ **Monitor health** - Check metrics in portal
5. ✅ **Remote access** - Set up Tailscale (optional)

---

# 🆘 Need Help?

**Repository & Code:**
- GitHub: `https://github.com/your-org/platebridge`
- Clone: `git clone https://github.com/your-org/platebridge.git`
- Issues: `https://github.com/your-org/platebridge/issues`

**Documentation:**
- Full guide: `pod-agent/golden-image/GOLDEN_IMAGE_GUIDE.md`
- Dual-NIC setup: `POD_DUAL_NIC_SETUP.md`
- POD setup: `POD_SETUP_GUIDE.md`
- Portal docs: https://docs.platebridge.io

**Support:**
- Email: support@platebridge.io
- Portal: Click "Help" button
- GitHub Issues: Report bugs and request features

---

# ✅ Summary

**All methods start with:**
```bash
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent
```

**Then choose your path:**

**Method 1: Golden Image (Production)**
1. Flash golden image → 2 min
2. Create config USB → 1 min
3. Boot POD → 3 min
4. Verify in portal → 1 min
**Total: 7 minutes! 🚀**

**Method 2: Auto Install Script (Development)**
1. Clone repo → 1 min
2. Run setup.sh → 15 min
3. Verify → 1 min
**Total: 17 minutes! 🛠️**

**Method 3: Manual Docker (Testing)**
1. Clone repo → 1 min
2. Install Docker → 3 min
3. Configure & start → 1 min
**Total: 5 minutes! 🐳**

Choose your method, follow the steps, and you'll have a POD running in no time!
