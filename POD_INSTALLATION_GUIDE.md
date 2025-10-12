# 🚀 PlateBridge POD - Complete Installation Guide

## Overview

This guide walks you through setting up a production PlateBridge POD from scratch using a fresh Ubuntu installation.

**What you'll end up with:**
- ✅ Fully configured dual-NIC router (cellular WAN + camera LAN)
- ✅ DHCP server for automatic camera IP assignment
- ✅ Frigate NVR for license plate detection
- ✅ PlateBridge agent connected to your portal
- ✅ Production-ready security (firewall, fail2ban, auto-updates)
- ✅ Everything auto-starts on boot

**Total Time:** 25-30 minutes

---

## Prerequisites

### Hardware Requirements

**Minimum:**
- Intel NUC or similar x86_64 system
- 2 network interfaces (dual-NIC):
  - **WAN**: Cellular modem or ethernet (internet connection)
  - **LAN**: Ethernet port for cameras
- 8GB RAM minimum (16GB recommended)
- 128GB storage minimum (256GB+ recommended for video recordings)

**Tested Hardware:**
- Intel NUC 11/12/13 series
- Any x86_64 system with dual NICs

### Software Requirements

- USB drive (8GB+) for Ubuntu installation
- Ubuntu 24.04 LTS Server ISO
- Internet connection during installation

### Portal Setup

Before starting, ensure you have:
1. Access to your PlateBridge portal
2. A property/site created in the portal
3. Ability to generate POD registration tokens

---

## Installation Steps

## Step 1: Install Ubuntu 24.04 LTS

### Download Ubuntu

1. Go to: https://ubuntu.com/download/server
2. Download **Ubuntu 24.04 LTS Server**
3. File will be named: `ubuntu-24.04-live-server-amd64.iso`

### Create Bootable USB

**On Windows:**
1. Download Rufus: https://rufus.ie/
2. Insert USB drive (will be erased!)
3. Open Rufus
4. Select the Ubuntu ISO
5. Click "Start"

**On Mac/Linux:**
1. Download Etcher: https://etcher.io/
2. Insert USB drive (will be erased!)
3. Open Etcher
4. Select the Ubuntu ISO
5. Select your USB drive
6. Click "Flash"

### Install Ubuntu

1. **Boot from USB**
   - Insert USB into target POD hardware
   - Boot and press F12/F2/Del to enter boot menu (varies by manufacturer)
   - Select USB drive

2. **Installation Options**
   - Choose: **Ubuntu Server** (minimal installation)
   - Language: English
   - Keyboard: US (or your preference)
   - Network: Let both interfaces get DHCP for now (we'll configure later)
   - Storage: Use entire disk (default is fine)
   - Profile Setup:
     - Your name: `admin` (or your preference)
     - Server name: `platebridge-pod`
     - Username: `admin` (or your preference)
     - Password: **Strong password** (you'll need this for SSH)
   - **IMPORTANT:** Enable OpenSSH server when prompted ✅
   - Featured Server Snaps: **Skip all** (our script installs what we need)

3. **Complete Installation**
   - Installation takes ~5-10 minutes
   - Remove USB when prompted
   - System will reboot
   - Login with the credentials you created

---

## Step 2: Initial System Setup

After Ubuntu boots and you login:

```bash
# 1. Update the system
sudo apt update && sudo apt upgrade -y

# 2. Install git (only package needed before our script)
sudo apt install -y git

# 3. Optional: Check your network interfaces
ip addr show
# You should see your two NICs (e.g., enp3s0, enp1s0)
# Note which is which - you'll need this info during setup
```

---

## Step 3: Clone Repository

```bash
# Navigate to /tmp (temporary location for install)
cd /tmp

# Clone the PlateBridge repository
git clone https://github.com/your-org/platebridge.git

# Navigate to pod-agent directory
cd platebridge/pod-agent

# Make install script executable
chmod +x install-complete.sh

# Verify the script is there
ls -la install-complete.sh
```

---

## Step 4: Run Complete Installation

This single script installs and configures everything:

```bash
sudo ./install-complete.sh
```

### What the Script Does

The script will automatically:
1. ✅ Install Docker & Docker Compose
2. ✅ Install system dependencies (dnsmasq, iptables, ethtool, etc.)
3. ✅ Configure dual-NIC network
4. ✅ Set up DHCP server for cameras
5. ✅ Configure firewall rules (NAT, port forwarding)
6. ✅ Apply security hardening (fail2ban, SSH hardening, auto-updates)
7. ✅ Install Frigate NVR
8. ✅ Install PlateBridge Python agent
9. ✅ Create systemd services for auto-start
10. ✅ Build Docker images

### Interactive Prompts

During installation, you'll be asked:

**1. Confirm Installation**
```
Continue with installation? (y/N):
```
Type: `y` and press Enter

**2. Network Interface Selection**
```
Available interfaces:
enp3s0
enp1s0

WAN interface (internet-facing) [enp3s0]:
```
- Press Enter to use `enp3s0` (cellular/WAN)
- Or type the correct WAN interface name

```
LAN interface (camera-facing) [enp1s0]:
```
- Press Enter to use `enp1s0` (cameras)
- Or type the correct LAN interface name

**3. Portal Configuration** (optional during install)
```
Configure portal connection now? (y/N):
```
- Type `y` if you have a registration token ready
- Type `n` to configure manually later

**If you choose `y`:**
```
Portal URL (e.g., https://platebridge.vercel.app):
```
Enter your portal URL

```
Registration Token (from portal):
```
Enter the token you generated in portal (Properties > Generate POD Registration Token)

The script will:
- Register the POD with your portal
- Receive and save API key
- Configure `.env` file automatically
- Start all services

---

## Step 5: Generate Registration Token (If Needed)

If you didn't configure portal during install, generate a token now:

1. **In Portal:**
   - Go to: **Properties** page
   - Select your property/site
   - Click: **Generate POD Registration Token**
   - Copy the token (valid for 24 hours)

2. **On POD:**
```bash
# Edit the .env file
sudo nano /opt/platebridge/docker/.env

# Set these values:
PORTAL_URL=https://your-portal.vercel.app
POD_API_KEY=your-api-key-here
POD_ID=your-pod-id-here

# Save and exit (Ctrl+X, Y, Enter)

# Restart services to apply changes
cd /opt/platebridge/docker
sudo docker compose restart
```

---

## Step 6: Connect Cameras

### Physical Connection

1. **Connect cameras to LAN interface**
   - Use the interface you selected as "LAN" (usually enp1s0)
   - Connect via ethernet switch if you have multiple cameras
   - Cameras will automatically:
     - Get IP via DHCP (192.168.100.100-200 range)
     - Get gateway: 192.168.100.1 (the POD)
     - Get DNS: 8.8.8.8, 8.8.4.4

2. **Wait 30-60 seconds**
   - Cameras need time to boot and request DHCP

### Discover Cameras

```bash
# Run the discovery script
sudo /opt/platebridge/discover-cameras.sh
```

**Expected Output:**
```
Scanning for cameras on 192.168.100.0/24...

192.168.100.101	00:12:34:56:78:9a	Camera_Manufacturer

DHCP leases:
1234567890 00:12:34:56:78:9a 192.168.100.101 Camera-ABC *

Testing RTSP streams (common URLs)...
Testing 192.168.100.101...
  ✓ rtsp://192.168.100.101:554/stream
  ✓ rtsp://192.168.100.101:554/h264
```

**Take note of:**
- Camera IP addresses (e.g., 192.168.100.101)
- Working RTSP URLs (e.g., `/stream` or `/h264`)

---

## Step 7: Configure Frigate

Add your discovered cameras to Frigate:

```bash
# Edit Frigate configuration
sudo nano /opt/platebridge/frigate/config/config.yml
```

**Add cameras to the `cameras:` section:**

```yaml
cameras:
  front_gate:
    ffmpeg:
      inputs:
        - path: rtsp://192.168.100.101:554/stream
          roles:
            - detect
            - record
    detect:
      width: 1280
      height: 720
      fps: 5
    record:
      enabled: true
      retain:
        days: 7
    snapshots:
      enabled: true
      retain:
        default: 14

  back_entrance:
    ffmpeg:
      inputs:
        - path: rtsp://192.168.100.102:554/stream
          roles:
            - detect
            - record
    detect:
      width: 1280
      height: 720
      fps: 5
    record:
      enabled: true
    snapshots:
      enabled: true
```

**Save and exit:** Ctrl+X, Y, Enter

### Restart Services

```bash
cd /opt/platebridge/docker
sudo docker compose restart
```

Wait ~30 seconds for services to restart.

---

## Step 8: Verify Installation

### Check Docker Services

```bash
cd /opt/platebridge/docker
sudo docker compose ps
```

**Expected output:**
```
NAME                    STATUS
frigate                 Up
mqtt                    Up
platebridge-agent       Up
```

All three should show "Up"

### Check Frigate Web UI

1. **Get POD IP address:**
```bash
ip addr show enp3s0 | grep "inet "
```
Example output: `inet 10.20.30.40/24`

2. **Open browser:**
```
http://10.20.30.40:5000
```

3. **Verify:**
   - You can see Frigate dashboard
   - Your cameras appear in the list
   - Live feeds are working

### Check Portal Connection

1. **In Portal:**
   - Go to: **PODs** page
   - Find your POD
   - Status should show: **Online** (green)
   - Last heartbeat should be recent

2. **Check logs:**
```bash
cd /opt/platebridge/docker
sudo docker compose logs platebridge-agent | grep -i "connected\|registered"
```

Should see messages like:
```
Connected to portal successfully
POD registered with ID: pod-xxxxx
Heartbeat sent successfully
```

---

## Verification Checklist

✅ **Network:**
- [ ] WAN interface has IP from cellular/internet
- [ ] LAN interface has IP 192.168.100.1
- [ ] Can ping 8.8.8.8 from POD

✅ **DHCP:**
- [ ] dnsmasq service is running: `sudo systemctl status dnsmasq`
- [ ] Cameras received IPs: `cat /var/lib/misc/dnsmasq.leases`
- [ ] Can ping camera IPs: `ping 192.168.100.101`

✅ **Docker:**
- [ ] Docker service running: `sudo systemctl status docker`
- [ ] All containers up: `docker compose ps`
- [ ] No container errors: `docker compose logs`

✅ **Frigate:**
- [ ] Web UI accessible at http://<pod-ip>:5000
- [ ] Cameras showing live feeds
- [ ] Detections working (test by driving a car past)

✅ **Portal:**
- [ ] POD shows "Online" in portal
- [ ] Recent heartbeat timestamp
- [ ] Detections appearing in portal

---

## Common Issues & Solutions

### Issue: Cameras not getting IPs

**Check DHCP server:**
```bash
# Is dnsmasq running?
sudo systemctl status dnsmasq

# View DHCP logs
sudo journalctl -u dnsmasq -f

# Check for DHCP packets
sudo tcpdump -i enp1s0 -n port 67 or port 68
```

**Fix:**
```bash
# Restart dnsmasq
sudo systemctl restart dnsmasq

# Check rp_filter is disabled (should be 0)
sudo sysctl net.ipv4.conf.enp1s0.rp_filter

# If not 0, fix it:
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.enp1s0.rp_filter=0
```

### Issue: Docker containers won't start

**Check Docker:**
```bash
sudo systemctl status docker
sudo journalctl -u docker -n 50
```

**Fix:**
```bash
# Restart Docker
sudo systemctl restart docker

# Rebuild containers
cd /opt/platebridge/docker
sudo docker compose down
sudo docker compose up -d
```

### Issue: Frigate can't connect to cameras

**Test RTSP stream manually:**
```bash
# Install ffmpeg if not present
sudo apt install -y ffmpeg

# Test stream
ffplay -rtsp_transport tcp rtsp://192.168.100.101:554/stream
```

**Common fixes:**
- Wrong RTSP path (try /stream, /h264, /live, /ch01)
- Camera requires authentication (add user:pass@ to URL)
- Wrong port (try 554, 8554)

### Issue: POD not connecting to portal

**Check .env configuration:**
```bash
cat /opt/platebridge/docker/.env
```

Verify:
- PORTAL_URL is correct
- POD_API_KEY is set
- POD_ID is set

**Test portal connectivity:**
```bash
curl -v https://your-portal.vercel.app/api/gatewise/health
```

**Check agent logs:**
```bash
docker compose logs platebridge-agent | tail -50
```

---

## What Gets Installed

### Directories Created

```
/opt/platebridge/
├── docker/              # Docker Compose files
│   ├── .env            # Portal credentials
│   └── docker-compose.yml
├── frigate/
│   ├── config/         # Frigate configuration
│   └── storage/        # Video recordings
├── logs/               # Agent logs
├── recordings/         # Local backups
└── network-info.txt    # Network reference guide
```

### Services Installed

```bash
# Docker containers (auto-start on boot)
- frigate               # License plate detection
- mqtt                  # Message broker
- platebridge-agent     # Portal communication

# System services
- dnsmasq              # DHCP + DNS server
- docker               # Container runtime
- fail2ban             # Brute-force protection
- unattended-upgrades  # Automatic security updates
```

### Network Configuration

```
WAN (enp3s0):    DHCP from cellular/internet
LAN (enp1s0):    192.168.100.1/24 (static)
Camera Range:    192.168.100.100-200 (DHCP)
DNS:             8.8.8.8, 8.8.4.4
Gateway:         192.168.100.1 (this POD)
```

---

## Useful Commands

### View Logs

```bash
# All services
cd /opt/platebridge/docker && sudo docker compose logs -f

# Specific service
sudo docker compose logs -f frigate
sudo docker compose logs -f platebridge-agent

# DHCP server
sudo journalctl -u dnsmasq -f
```

### Restart Services

```bash
# All services
cd /opt/platebridge/docker
sudo docker compose restart

# Specific service
sudo docker compose restart frigate

# DHCP server
sudo systemctl restart dnsmasq
```

### Network Status

```bash
# View network configuration
cat /opt/platebridge/network-info.txt

# Check interfaces
ip addr show

# DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Scan camera network
sudo arp-scan --interface=enp1s0 192.168.100.0/24
```

---

## Security Features Enabled

The installation automatically enables:

- ✅ **Firewall:** iptables with default DROP policy
- ✅ **NAT:** Camera network isolated from internet
- ✅ **fail2ban:** Automatic IP banning after 3 failed SSH attempts
- ✅ **SSH Hardening:** Root login disabled, timeout settings
- ✅ **Auto-Updates:** Automatic security updates enabled
- ✅ **Rate Limiting:** SSH connection rate limiting
- ✅ **Port Protection:** Only necessary ports exposed
- ✅ **Camera Isolation:** Cameras cannot be accessed from internet

---

## Next Steps

After successful installation:

1. **Configure Access Control**
   - Add vehicles/plates to portal
   - Set access permissions
   - Test gate opening

2. **Monitor System**
   - Check logs regularly
   - Monitor disk space (recordings grow large!)
   - Verify heartbeats in portal

3. **Optimize Frigate**
   - Adjust detection zones
   - Tune detection sensitivity
   - Configure retention periods

---

## Support

**Documentation:**
- Complete guide: `/opt/platebridge/network-info.txt`
- Script details: `pod-agent/DHCP_FIXES_APPLIED.md`
- Quick reference: `pod-agent/README.md`

**Logs to check:**
```bash
# Docker services
cd /opt/platebridge/docker && sudo docker compose logs -f

# System services
sudo journalctl -u dnsmasq -f
sudo journalctl -u docker -f

# Security logs
sudo tail -f /var/log/auth.log
```

---

## Success!

Your PlateBridge POD is now:
- ✅ Online and connected to portal
- ✅ Detecting license plates
- ✅ Ready to control gates
- ✅ Auto-starting on boot
- ✅ Secured with firewall and monitoring

**Access Frigate:** http://<your-pod-ip>:5000
**Monitor in Portal:** https://your-portal.vercel.app/pods
