# 🔌 PlateBridge POD - Dual NIC Setup Guide

Complete guide for setting up your POD with two network interfaces: one for internet and one for cameras.

---

## 🎯 Overview

**Network Architecture:**
```
                    ┌─────────────┐
                    │  Internet   │
                    └──────┬──────┘
                           │
                      WAN (enp3s0)
                           │
                    ┌──────┴──────┐
                    │  POD Device │
                    │             │
                    │  Ubuntu     │
                    │  24.04 LTS  │
                    └──────┬──────┘
                           │
                      LAN (enp1s0)
                    192.168.100.1
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    Camera 1          Camera 2          Camera 3
192.168.100.100   192.168.100.101   192.168.100.102
```

**Why Dual NIC?**
- ✅ **Security**: Cameras isolated from internet
- ✅ **Performance**: Dedicated bandwidth for video streams
- ✅ **Reliability**: Camera network failures don't affect internet
- ✅ **Control**: Full DHCP and network management for cameras

---

## 📋 Prerequisites

### Hardware
- POD device with **2 Ethernet ports** (or 1 Ethernet + USB-Ethernet adapter)
- Cameras with Ethernet connection
- Network switch for multiple cameras (if needed)
- Internet connection (WAN)

### Software
- Ubuntu Server 24.04 LTS installed
- Root/sudo access

---

## 🚀 Quick Start (5 Steps)

### **Step 1: Identify Your Network Interfaces**

```bash
# List all network interfaces
ip addr show

# You should see something like:
# 1: lo: ...
# 2: enp3s0: ...  <- WAN (Internet)
# 3: enp1s0: ...  <- LAN (Cameras)
```

**Common interface names:**
- `enp3s0`, `enp1s0` (older naming)
- `enp0s3`, `enp0s8` (PCI bus naming)
- `ens3`, `ens4` (systemd naming)

### **Step 2: Run Network Configuration Script**

```bash
cd /path/to/platebridge/pod-agent
chmod +x network-config.sh
sudo ./network-config.sh
```

**The script will:**
1. ✅ Detect your network interfaces
2. ✅ Configure WAN (DHCP or static IP)
3. ✅ Configure LAN (192.168.100.1/24)
4. ✅ Set up DHCP server for cameras
5. ✅ Configure firewall
6. ✅ Enable IP forwarding (optional)

**Script prompts:**
```
WAN Interface: enp3s0 (Internet)
LAN Interface: enp1s0 (Cameras)
Is this correct? yes

Use DHCP for WAN? yes

Camera network subnet [192.168.100]: <Enter>

Apply this configuration? yes

Allow cameras to access internet via NAT? no
```

**What gets configured:**
- **WAN**: Internet connection (DHCP or static)
- **LAN**: POD IP = 192.168.100.1
- **DHCP**: Cameras get IPs 192.168.100.100 - 192.168.100.200
- **DNS**: POD relays DNS for cameras
- **Firewall**: Cameras can access POD, but not internet (unless NAT enabled)

### **Step 3: Connect Cameras**

**Physical connection:**
```
1. Plug camera Ethernet cables into LAN switch
2. Connect LAN switch to POD's LAN interface (enp1s0)
3. Power on cameras
```

**Camera should:**
- ✅ Get DHCP IP automatically (192.168.100.100+)
- ✅ Be accessible from POD at 192.168.100.x

### **Step 4: Discover Cameras**

```bash
cd /path/to/platebridge/pod-agent
chmod +x discover-cameras.sh
sudo ./discover-cameras.sh
```

**What it does:**
1. Scans camera network (192.168.100.0/24)
2. Finds devices with RTSP ports open
3. Tests common RTSP stream paths
4. Saves working URLs to `/opt/platebridge/camera-urls.txt`

**Output example:**
```
Found devices on network:
192.168.100.100  00:11:22:33:44:55  Camera-1
192.168.100.101  00:11:22:33:44:66  Camera-2

Testing 192.168.100.100...
  RTSP port 554 open
  ✓ Found working RTSP stream: rtsp://192.168.100.100:554/stream

Camera URLs saved to: /opt/platebridge/camera-urls.txt
```

### **Step 5: Configure POD**

```bash
# Copy dual-NIC config template
sudo cp /path/to/pod-agent/config-dual-nic.yaml /opt/platebridge/config.yaml

# Edit with your settings
sudo nano /opt/platebridge/config.yaml
```

**Update these sections:**

```yaml
# Portal connection
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_your_actual_key"
site_id: "your-site-uuid"

# Network interfaces (from Step 1)
wan_interface: "enp3s0"
lan_interface: "enp1s0"

# Cameras (from Step 4)
cameras:
  - id: "gate-camera-1"
    name: "Main Gate"
    rtsp_url: "rtsp://192.168.100.100:554/stream"
```

**Save and start POD agent!**

---

## 🔧 Detailed Configuration

### Network Configuration Files

**Netplan (`/etc/netplan/01-platebridge-network.yaml`):**
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:  # WAN
      dhcp4: true
    enp1s0:  # LAN
      dhcp4: false
      addresses:
        - 192.168.100.1/24
```

**DHCP Server (`/etc/dnsmasq.d/platebridge-cameras.conf`):**
```
interface=enp1s0
bind-interfaces
dhcp-range=192.168.100.100,192.168.100.200,24h
dhcp-option=option:dns-server,192.168.100.1
domain=cameras.local
```

**Firewall Rules:**
```bash
# View firewall status
sudo ufw status verbose

# Allow from camera network
sudo ufw allow from 192.168.100.0/24
```

---

## 📹 Camera Setup

### Supported Camera Types

**1. IP Cameras with RTSP**
- Any camera with RTSP stream support
- Common brands: Hikvision, Dahua, Reolink, Amcrest, etc.

**2. USB Cameras**
- Plug into POD USB port
- Shows as `/dev/video0`, `/dev/video1`, etc.
- Use `v4l2-rtsp` to create RTSP stream

**3. Analog Cameras (via encoder)**
- Use HDMI/SDI to IP encoder
- Encoder provides RTSP stream

### Camera Configuration

**Set camera to DHCP mode:**
1. Access camera web interface (may need direct connection initially)
2. Network settings → DHCP
3. Save and reboot camera
4. Connect to POD LAN network
5. Camera gets IP from 192.168.100.100-200 range

**Or set static IP:**
1. IP: 192.168.100.x (where x = 100-200)
2. Netmask: 255.255.255.0
3. Gateway: 192.168.100.1
4. DNS: 192.168.100.1

### Finding RTSP URLs

**Common RTSP URL formats:**
```
rtsp://<ip>:554/stream
rtsp://<ip>:554/h264
rtsp://<ip>:554/Streaming/Channels/101
rtsp://<ip>:554/live
rtsp://<ip>:554/cam/realmonitor?channel=1&subtype=0
```

**Test RTSP stream:**
```bash
# Using ffplay
ffplay -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# Using VLC
vlc rtsp://192.168.100.100:554/stream

# Using ffprobe (get stream info)
ffprobe -rtsp_transport tcp rtsp://192.168.100.100:554/stream
```

---

## 🛠️ Troubleshooting

### No Internet on POD

```bash
# Check WAN interface
ip addr show enp3s0

# Should show IP address
# If not:
sudo netplan apply
sudo systemctl restart systemd-networkd

# Test connectivity
ping 8.8.8.8
```

### Cameras Not Getting DHCP

```bash
# Check DHCP server
sudo systemctl status dnsmasq

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Restart DHCP
sudo systemctl restart dnsmasq

# Check if camera is seen on network
sudo arp-scan --interface=enp1s0 192.168.100.0/24
```

### Can't Access Camera Web Interface

```bash
# From POD, test camera HTTP
curl http://192.168.100.100

# If timeout, check:
# 1. Camera is powered on
# 2. Camera is connected to correct network
# 3. Camera has IP (check DHCP leases)

# Scan for open ports
sudo nmap 192.168.100.100
```

### RTSP Stream Not Working

```bash
# Test with ffprobe
ffprobe -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# Common issues:
# 1. Wrong RTSP path - check camera manual
# 2. Authentication required - add username:password
#    rtsp://admin:password@192.168.100.100:554/stream
# 3. Camera RTSP disabled - enable in camera settings
# 4. Firewall blocking - check UFW rules
```

### Cameras Can't Reach Internet (and need to)

```bash
# Enable NAT
sudo nano /etc/ufw/before.rules

# Add at the end:
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.100.0/24 -o enp3s0 -j MASQUERADE
COMMIT

# Reload firewall
sudo ufw disable && sudo ufw enable

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-forward.conf
sudo sysctl -p /etc/sysctl.d/99-forward.conf
```

---

## 📊 Network Monitoring

### View Network Status

```bash
# All interfaces
ip addr show

# Routing table
ip route show

# Active connections
sudo netstat -tulpn

# Bandwidth usage
sudo iftop -i enp1s0  # Camera network traffic
```

### View Connected Cameras

```bash
# ARP scan (fast)
sudo arp-scan --interface=enp1s0 192.168.100.0/24

# NMAP scan (detailed)
sudo nmap -sn 192.168.100.0/24

# DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

### Monitor RTSP Streams

```bash
# Stream statistics
ffprobe -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# Continuous monitoring
watch -n 5 'cat /var/lib/misc/dnsmasq.leases'
```

---

## 🔐 Security Best Practices

### 1. **Isolate Camera Network**
✅ Cameras on separate network (192.168.100.0/24)
✅ No direct internet access (unless needed)
✅ Firewall rules restrict access

### 2. **Change Default Passwords**
```bash
# Always change:
# - Camera admin passwords
# - RTSP authentication
# - POD SSH password
```

### 3. **Enable Camera Authentication**
```yaml
# In config.yaml, use authenticated RTSP URLs:
rtsp_url: "rtsp://admin:SecurePass123@192.168.100.100:554/stream"
```

### 4. **Firewall Rules**
```bash
# Only allow necessary ports
sudo ufw allow from 192.168.100.0/24 to any port 554  # RTSP
sudo ufw allow from 192.168.100.0/24 to any port 80   # HTTP (web UI)
sudo ufw deny from 192.168.100.0/24 to any port 22    # Block SSH from cameras
```

### 5. **Regular Updates**
```bash
# Update POD system
sudo apt update && sudo apt upgrade -y

# Update camera firmware (via camera web UI)
```

---

## 📁 Important Files

```
/etc/netplan/01-platebridge-network.yaml  # Network config
/etc/dnsmasq.d/platebridge-cameras.conf   # DHCP config
/opt/platebridge/config.yaml              # POD config
/opt/platebridge/network-info.txt         # Network summary
/opt/platebridge/camera-urls.txt          # Discovered cameras
/var/lib/misc/dnsmasq.leases             # DHCP leases
```

---

## 🎯 Quick Reference

### Common Commands

```bash
# Network status
ip addr show

# Restart network
sudo netplan apply

# Restart DHCP
sudo systemctl restart dnsmasq

# Scan for cameras
sudo arp-scan --interface=enp1s0 192.168.100.0/24

# Test RTSP
ffplay -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# View logs
sudo journalctl -u dnsmasq -f
sudo journalctl -u systemd-networkd -f

# Firewall status
sudo ufw status verbose
```

### Network Troubleshooting Flow

```
1. Is POD online?
   → ping 8.8.8.8

2. Are cameras connected?
   → sudo arp-scan --interface=enp1s0 192.168.100.0/24

3. Did cameras get DHCP?
   → cat /var/lib/misc/dnsmasq.leases

4. Can POD reach camera?
   → ping 192.168.100.100

5. Is RTSP working?
   → ffplay rtsp://192.168.100.100:554/stream
```

---

## ✅ Setup Checklist

- [ ] **Hardware Connected**
  - [ ] WAN cable to internet
  - [ ] LAN cable(s) to cameras
  - [ ] Cameras powered on

- [ ] **Network Configured**
  - [ ] Interfaces detected
  - [ ] WAN has internet
  - [ ] LAN has IP 192.168.100.1
  - [ ] DHCP server running

- [ ] **Cameras Discovered**
  - [ ] Cameras found on network
  - [ ] RTSP URLs tested
  - [ ] URLs saved to config

- [ ] **POD Configured**
  - [ ] config.yaml created
  - [ ] Portal URL set
  - [ ] API key set
  - [ ] Camera URLs added

- [ ] **POD Agent Running**
  - [ ] Service started
  - [ ] Heartbeat to portal
  - [ ] Detections working

---

## 🆘 Getting Help

**Check logs:**
```bash
# Network
sudo journalctl -u systemd-networkd -f

# DHCP
sudo journalctl -u dnsmasq -f

# POD Agent
tail -f /opt/platebridge/logs/pod-agent.log
```

**Network info:**
```bash
cat /opt/platebridge/network-info.txt
```

**Support:**
- Documentation: `/pod-agent/README.md`
- Issues: Check firewall and DHCP logs
- Portal: https://your-portal.vercel.app

---

## 🎉 Success!

**Once configured, you'll have:**
- ✅ POD with internet connection (WAN)
- ✅ Isolated camera network (LAN)
- ✅ Automatic camera DHCP
- ✅ RTSP streams accessible
- ✅ Secure and reliable setup

**Your POD is ready to detect plates! 🚗📹**
