# 🚀 PlateBridge POD Agent - Installation Scripts

## 📋 Available Installation Scripts

### **🎯 install-complete.sh** - Complete Production Setup ⭐ RECOMMENDED

**What it installs:**
- ✅ Docker & Docker Compose
- ✅ Dual-NIC network configuration (WAN + LAN)
- ✅ DHCP server for cameras (dnsmasq)
- ✅ Firewall & NAT (iptables, UFW)
- ✅ Frigate NVR
- ✅ PlateBridge POD agent (Python with venv)
- ✅ Camera discovery tools
- ✅ Systemd auto-start services
- ✅ All directories and configurations

**Use when:**
- 🎯 Setting up a new production POD from scratch
- 🎯 You want everything configured automatically
- 🎯 Using dual-NIC setup with dedicated camera network

**Usage:**
```bash
cd platebridge/pod-agent
sudo ./install-complete.sh
```

**Time:** 15-20 minutes
**Requires:** Ubuntu 24.04, sudo access

---

### **🛠️ setup.sh** - Python Agent Only

**What it installs:**
- ✅ Python agent only
- ✅ Python virtual environment (venv)
- ✅ Python dependencies (no system conflicts!)
- ✅ Interactive configuration wizard
- ✅ Systemd service for agent

**Does NOT install:**
- ❌ Docker
- ❌ Frigate
- ❌ Network configuration
- ❌ DHCP server

**Use when:**
- 🎯 Docker already installed
- 🎯 Network already configured
- 🎯 Only need the Python agent
- 🎯 Development/testing environment

**Usage:**
```bash
cd platebridge/pod-agent
./setup.sh
```

**Time:** 5 minutes
**Requires:** Python 3.7+

---

### **🌐 network-config.sh** - Network Setup Only

**What it configures:**
- ✅ Dual-NIC setup (enp3s0 WAN, enp1s0 LAN)
- ✅ Static IP for camera network (192.168.100.1)
- ✅ DHCP server (dnsmasq)
- ✅ NAT/IP forwarding (iptables)
- ✅ Firewall rules

**Does NOT install:**
- ❌ Docker
- ❌ Frigate
- ❌ Python agent

**Use when:**
- 🎯 Need to configure network separately
- 🎯 Reconfiguring existing network
- 🎯 Manual step-by-step installation

**Usage:**
```bash
cd platebridge/pod-agent
sudo ./network-config.sh
```

**Time:** 5 minutes
**Requires:** sudo access, 2 network interfaces

---

### **📹 discover-cameras.sh** - Find Cameras on Network

**What it does:**
- ✅ Scans camera network with arp-scan
- ✅ Lists DHCP leases
- ✅ Tests common RTSP URLs
- ✅ Saves discovered cameras to file

**Use when:**
- 🎯 Finding cameras after physical connection
- 🎯 Testing camera connectivity
- 🎯 Getting RTSP stream URLs

**Usage:**
```bash
cd platebridge/pod-agent
sudo ./discover-cameras.sh
```

**Time:** 1 minute
**Requires:** sudo access, cameras connected

---

## 🎯 Quick Decision Guide

### **I want to set up a complete production POD**
```bash
sudo ./install-complete.sh
```
→ Installs EVERYTHING (Docker, Frigate, network, agent, etc.)

---

### **I already have Docker, just need network + agent**
```bash
# 1. Configure network
sudo ./network-config.sh

# 2. Set up agent
./setup.sh

# 3. Manually set up Frigate docker-compose
```

---

### **I have everything except the Python agent**
```bash
./setup.sh
```
→ Just installs the agent with virtual environment

---

### **I need to reconfigure network only**
```bash
sudo ./network-config.sh
```
→ Just reconfigures dual-NIC network

---

### **I want to find cameras on my network**
```bash
sudo ./discover-cameras.sh
```
→ Scans and tests camera connections

---

## 📊 Feature Comparison Table

| Feature | install-complete.sh | setup.sh | network-config.sh | discover-cameras.sh |
|---------|---------------------|----------|-------------------|---------------------|
| **Docker** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Frigate** | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Dual-NIC Network** | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **DHCP Server** | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **Firewall/NAT** | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| **Python Agent** | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| **Virtual Env** | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| **Systemd Service** | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| **Camera Discovery** | ✅ Yes | ❌ No | ❌ No | ✅ Yes |
| **Interactive Config** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Requires sudo** | ✅ Yes | Partial | ✅ Yes | ✅ Yes |
| **Time Required** | 15-20 min | 5 min | 5 min | 1 min |
| **Best For** | Production | Dev/Test | Manual Setup | Finding Cameras |

---

## 🚀 Recommended Installation Path

### **For Production POD (Most Common) - Fresh Install:**

**Step 1: Install Ubuntu 24.04 LTS**
```bash
# 1. Download Ubuntu 24.04 LTS Server
# https://ubuntu.com/download/server

# 2. Create bootable USB with Rufus (Windows) or Etcher (Mac/Linux)
# https://rufus.ie/ or https://etcher.io/

# 3. Boot from USB and install Ubuntu
#    - Choose "Ubuntu Server" (minimal installation)
#    - Set hostname: platebridge-pod
#    - Create admin user (you'll need this for SSH)
#    - Enable OpenSSH server when prompted
#    - No additional packages needed (script installs everything)

# 4. After installation, reboot and login
```

**Step 2: Clone Repository & Install**
```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install git
sudo apt install -y git

# 3. Clone repository
cd /tmp
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent

# 4. Make script executable
chmod +x install-complete.sh

# 5. Run complete installer (installs everything!)
sudo ./install-complete.sh
# This will:
#   - Install Docker, Frigate, dnsmasq, iptables
#   - Configure dual-NIC network
#   - Set up DHCP server for cameras
#   - Configure firewall and security
#   - Install Python agent
#   - Set up auto-start services
```

**Step 3: Configure Portal Connection**
```bash
# During installation, you'll be prompted to:
# 1. Select WAN interface (cellular/internet) - usually enp3s0
# 2. Select LAN interface (cameras) - usually enp1s0
# 3. Enter portal URL: https://your-portal.vercel.app
# 4. Enter registration token from portal (generate in Properties > POD Tokens)
#
# Script will automatically register POD and configure .env file
```

**Step 4: Connect Cameras & Discover**
```bash
# 1. Connect cameras physically to LAN interface (enp1s0)
#    Cameras will automatically get IPs via DHCP (192.168.100.100-200)

# 2. Wait 30 seconds for cameras to boot

# 3. Discover cameras
sudo /opt/platebridge/discover-cameras.sh
# This will show:
#   - Camera IP addresses
#   - DHCP leases
#   - Working RTSP URLs
```

**Step 5: Configure Frigate**
```bash
# 1. Edit Frigate config with discovered camera URLs
sudo nano /opt/platebridge/frigate/config/config.yml

# 2. Add cameras (example):
# cameras:
#   front_gate:
#     ffmpeg:
#       inputs:
#         - path: rtsp://192.168.100.100:554/stream
#           roles:
#             - detect
#             - record

# 3. Save and exit (Ctrl+X, Y, Enter)

# 4. Restart services
cd /opt/platebridge/docker
sudo docker compose restart
```

**Step 6: Verify Everything Works**
```bash
# 1. Check all services are running
cd /opt/platebridge/docker
sudo docker compose ps
# Should show: frigate, mqtt, platebridge-agent (all "Up")

# 2. Access Frigate web UI
# Open browser: http://<pod-ip>:5000
# (Use the IP from WAN interface - enp3s0)

# 3. Check POD is online in portal
# Portal > PODs > Your POD should show "Online" status

# Done! ✅
```

**Total time: ~25 minutes** (including Ubuntu install)

---

### **For Development/Testing:**

```bash
# 1. Install Docker manually
curl -fsSL https://get.docker.com | sudo sh

# 2. Clone repository
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent

# 3. Install agent only (without Docker/Frigate)
./setup.sh

# 4. Set up Frigate manually (create docker-compose.yml)

# Done! ✅
```

---

## 📁 What Gets Installed & Created

### **After Complete Installation:**

```
/opt/platebridge/
├── venv/                          # Python virtual environment
│   ├── bin/python                # Isolated Python
│   └── lib/python3.X/...         # Agent dependencies
├── config/                        # Agent configuration files
├── docker/
│   ├── docker-compose.yml        # Frigate + MQTT + Agent services
│   ├── .env                      # Portal credentials (YOU CONFIGURE)
│   └── .env.example              # Configuration template
├── frigate/
│   ├── config/
│   │   └── config.yml           # Frigate camera configuration
│   ├── storage/                 # Video recordings (grows large!)
│   └── media/                   # Frigate snapshots
├── logs/                         # Agent logs
├── recordings/                   # Local backup recordings
├── agent.py                      # Python POD agent
├── requirements.txt              # Python dependencies
├── discover-cameras.sh           # Camera discovery script
└── network-info.txt              # Network config summary

/etc/netplan/
└── 01-platebridge-network.yaml   # Network configuration

/etc/dnsmasq.d/
└── platebridge-cameras.conf      # DHCP server config

/etc/systemd/system/
└── platebridge-pod.service       # Auto-start service
```

---

## 🔧 Post-Installation Configuration

### **1. Access Frigate Web UI:**
```
http://<pod-ip>:5000
```
*Use your POD's IP address from enp3s0 (WAN interface)*

### **2. Configure Portal Connection:**

Edit the environment file:
```bash
sudo nano /opt/platebridge/docker/.env
```

```ini
PORTAL_URL=https://your-portal.platebridge.io
POD_API_KEY=your-api-key-from-portal
SITE_ID=your-site-id-from-portal
```

### **3. Add Cameras to Frigate:**

```bash
sudo nano /opt/platebridge/frigate/config/config.yml
```

Example camera configuration:
```yaml
cameras:
  front_gate:
    ffmpeg:
      inputs:
        - path: rtsp://192.168.100.100:554/stream
          roles:
            - detect
            - record
    detect:
      width: 1280
      height: 720
    record:
      enabled: true
    snapshots:
      enabled: true
```

### **4. Restart Services:**
```bash
cd /opt/platebridge/docker
docker compose restart
```

---

## 🛠️ Common Operations

### **View Logs:**
```bash
# All Docker services
cd /opt/platebridge/docker
docker compose logs -f

# Frigate only
docker compose logs -f frigate

# Agent only
docker compose logs -f platebridge-agent

# System service
sudo journalctl -u platebridge-pod -f
```

### **Discover Cameras:**
```bash
sudo /opt/platebridge/discover-cameras.sh
```

### **Check Network Status:**
```bash
# View saved network configuration
cat /opt/platebridge/network-info.txt

# Check network interfaces
ip addr show

# View DHCP leases (what IPs cameras got)
cat /var/lib/misc/dnsmasq.leases

# Scan camera network manually
sudo arp-scan --interface=enp1s0 192.168.100.0/24
```

### **Restart Services:**
```bash
# Restart all services
cd /opt/platebridge/docker
docker compose restart

# Restart specific service
docker compose restart frigate
docker compose restart platebridge-agent

# Restart DHCP server
sudo systemctl restart dnsmasq
```

### **Check Service Status:**
```bash
# Docker services
cd /opt/platebridge/docker
docker compose ps

# Docker daemon
sudo systemctl status docker

# DHCP server
sudo systemctl status dnsmasq

# POD startup service
sudo systemctl status platebridge-pod
```

---

## 🆘 Troubleshooting

### **Docker not starting:**
```bash
sudo systemctl status docker
sudo systemctl start docker
sudo journalctl -u docker -n 50
```

### **Network issues (cameras not getting IPs):**
```bash
# Check interfaces are up
ip addr show

# Reapply network config
sudo netplan apply

# Check DHCP server
sudo systemctl status dnsmasq
sudo systemctl restart dnsmasq

# View DHCP logs
sudo journalctl -u dnsmasq -f
```

### **Cameras not found on network:**
```bash
# Check DHCP is running
sudo systemctl status dnsmasq

# Check DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Scan manually
sudo arp-scan --interface=enp1s0 192.168.100.0/24

# Check if LAN interface has IP
ip addr show enp1s0

# Ping camera network gateway
ping 192.168.100.1
```

### **Agent not connecting to portal:**
```bash
# Check .env configuration
cat /opt/platebridge/docker/.env

# Test portal connectivity
curl -v https://your-portal.platebridge.io/api/gatewise/health

# Check agent logs
docker compose logs platebridge-agent

# Verify portal credentials in portal UI
```

### **Frigate not detecting plates:**
```bash
# Check Frigate is running
docker compose ps

# View Frigate logs
docker compose logs frigate

# Access Frigate UI
# http://<pod-ip>:5000

# Test camera RTSP stream
ffplay -rtsp_transport tcp rtsp://192.168.100.100:554/stream
```

### **Python package conflicts:**
See `PYTHON_PACKAGE_FIX.md` for complete guide on virtual environments.

---

## 📚 Additional Documentation

- **Quick Start Guide:** `../POD_QUICK_START.md`
- **Dual-NIC Setup Details:** `../POD_DUAL_NIC_SETUP.md`
- **Complete POD Guide:** `../POD_SETUP_GUIDE.md`
- **Python Package Issues:** `PYTHON_PACKAGE_FIX.md`
- **Network Config (after install):** `/opt/platebridge/network-info.txt`
- **Cheat Sheet:** `../POD_CHEAT_SHEET.md`

---

## 🎯 Quick Reference

### **Installation Scripts:**

| Script | Does Everything? | Use Case |
|--------|------------------|----------|
| `install-complete.sh` | ✅ YES | Production POD from scratch |
| `setup.sh` | ❌ Agent only | Have Docker already |
| `network-config.sh` | ❌ Network only | Manual setup |
| `discover-cameras.sh` | ❌ Scan only | Find cameras |

### **Answer: Does setup.sh install everything?**

**NO** - `setup.sh` only installs the Python agent.

**YES** - `install-complete.sh` installs EVERYTHING:
- Docker ✅
- Frigate ✅
- Network (dual-NIC) ✅
- DHCP ✅
- Firewall ✅
- Agent ✅
- Camera discovery ✅

---

## 🎉 Summary

**Quick Answer to Your Question:**

> **Does setup.sh install everything (Docker, Frigate, network, etc.)?**

**NO.** `setup.sh` only installs the Python agent with virtual environment.

**For everything, use:** `sudo ./install-complete.sh`

**What each script does:**
- `install-complete.sh` = **Everything** (Docker + Frigate + Network + Agent)
- `setup.sh` = **Agent only** (Python + venv + systemd)
- `network-config.sh` = **Network only** (Dual-NIC + DHCP + NAT)
- `discover-cameras.sh` = **Camera scanning** (arp-scan + RTSP test)

**For production POD:** Use `install-complete.sh` - it's your all-in-one solution! 🚀

---

## 💡 What This Agent Does

Once installed, the PlateBridge POD agent:

- ✅ Watches Frigate for license plate detections
- ✅ Sends detections to your PlateBridge portal
- ✅ Receives allow/deny decisions from portal
- ✅ Triggers gate opening for authorized plates
- ✅ Caches whitelist locally for offline operation
- ✅ Auto-reconnects if network drops
- ✅ Provides heartbeat monitoring
- ✅ Handles camera streaming via portal

---

## 📞 Support

**Check logs first:**
```bash
# Docker logs
cd /opt/platebridge/docker && docker compose logs -f

# System logs
sudo journalctl -u platebridge-pod -f
```

**Look for:**
- "Connected to Frigate MQTT broker" - MQTT working ✅
- "License plate detected" - Frigate sending events ✅
- "Portal response" - Portal communication working ✅
- "GATE OPENED" - Gate control working ✅

**Still stuck?**
- Documentation: `../POD_QUICK_START.md`
- Cheat sheet: `../POD_CHEAT_SHEET.md`
- Network config: `/opt/platebridge/network-info.txt`
