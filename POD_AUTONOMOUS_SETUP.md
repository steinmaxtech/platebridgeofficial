# PlateBridge POD - Autonomous Setup Guide

This guide will get your POD running fully autonomously with auto-recovery, health monitoring, and zero-touch operation.

## Quick Start (5 Minutes)

### 1. Run Complete Installation
```bash
# Download and run installation script
curl -fsSL https://platebridge.vercel.app/install-pod.sh | sudo bash

# Or if you have the repo locally:
cd pod-agent
sudo ./install-complete.sh
```

### 2. Fix API Key Issue (CRITICAL)
Your current issue is **401 Unauthorized** - the API key is missing or invalid.

```bash
# Check current API key
docker exec platebridge-pod env | grep POD_API_KEY

# If empty or wrong, generate a new one:
# 1. Go to https://platebridge.vercel.app/pods
# 2. Find your pod
# 3. Click "Generate API Key"
# 4. Copy the key (starts with pbk_)

# Update the key
sudo nano /opt/platebridge/docker/.env
# Set: POD_API_KEY=pbk_your_actual_key_here

# Restart to apply
cd /opt/platebridge/docker
sudo docker compose restart
```

### 3. Verify It's Working
```bash
# Check logs
docker logs -f platebridge-pod --tail 50

# Should see:
# ✓ "Heartbeat sent successfully"
# ✓ "Community ID obtained"
# ✓ No more 401 errors
```

---

## Full Autonomous Setup

### Prerequisites
- Ubuntu 24.04 LTS Server
- 2 network interfaces (WAN + LAN)
- USB storage for recordings (optional)
- Internet connection on WAN interface

### Step 1: Generate Registration Token

Before running installation, generate a registration token:

1. Log into portal: `https://platebridge.vercel.app`
2. Go to **Communities** → Select your community → **Tokens**
3. Click **Generate Registration Token**
4. Copy the token (expires in 24 hours)

### Step 2: Run Automated Installation

```bash
# Download install script
cd ~
wget https://raw.githubusercontent.com/your-repo/platebridge/main/pod-agent/install-complete.sh

# Make executable
chmod +x install-complete.sh

# Run with sudo
sudo ./install-complete.sh
```

**What it does:**
- ✅ Installs Docker, Tailscale, system dependencies
- ✅ Configures dual-NIC network (WAN + LAN)
- ✅ Sets up DHCP server for cameras
- ✅ Configures firewall with security hardening
- ✅ Installs Frigate NVR
- ✅ Installs PlateBridge agent
- ✅ Sets up systemd auto-start
- ✅ Configures fail2ban, auto-updates

### Step 3: Configure Portal Connection

During installation, you'll be prompted:

```
Portal URL: https://platebridge.vercel.app
Registration Token: [paste token from Step 1]
Device Name: Main Gate POD
```

The script will:
- Register the POD with the portal
- Generate and save API key automatically
- Configure all services
- Start Docker containers

### Step 4: Configure Cameras (Optional)

```bash
# Discover cameras on network
sudo /opt/platebridge/discover-cameras.sh

# Edit Frigate config
sudo nano /opt/platebridge/frigate/config/config.yml

# Add your cameras:
cameras:
  gate_camera:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://admin:password@192.168.1.100:554/stream
          roles: [detect, record]
    detect:
      width: 1280
      height: 720
      fps: 5
    objects:
      track:
        - car
        - license_plate

# Restart Frigate
cd /opt/platebridge/docker
sudo docker compose restart frigate
```

### Step 5: Enable Tailscale (Recommended)

```bash
# Connect to Tailscale network
sudo tailscale up

# Get your Tailscale IP
tailscale ip -4

# Enable Tailscale Funnel for public access
sudo tailscale funnel 8000
```

Now your stream is accessible at: `https://pod-name.tailnet.ts.net`

---

## Autonomous Features

### Auto-Start on Boot

The installation creates a systemd service that starts everything automatically:

```bash
# Check status
sudo systemctl status platebridge-pod

# View logs
sudo journalctl -u platebridge-pod -f

# Manual control (not needed, auto-starts)
sudo systemctl start platebridge-pod
sudo systemctl stop platebridge-pod
sudo systemctl restart platebridge-pod
```

### Health Monitoring

The pod agent sends heartbeats every 60 seconds with:
- System status (CPU, memory, disk, temperature)
- Camera status
- Connection status
- Tailscale info

**View health:**
```bash
# Check pod logs
docker logs platebridge-pod --tail 50

# Check all services
cd /opt/platebridge/docker
docker compose ps

# Individual service logs
docker logs frigate --tail 50
docker logs mosquitto --tail 50
```

### Auto-Recovery

**Docker Compose** with `restart: unless-stopped` automatically restarts crashed containers:

```yaml
services:
  platebridge-agent:
    restart: unless-stopped  # Auto-restart on crash
```

**Systemd service** starts all containers on boot:
```bash
# Auto-starts after:
# - Power loss
# - System reboot
# - Manual shutdown
```

**Network resilience:**
- Handles WAN connection drops
- Reconnects automatically when network returns
- Queues detections during offline periods

### Automatic Updates

**Security updates** are installed automatically:
```bash
# Check update logs
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log

# Manual security update
sudo unattended-upgrade -d
```

**Docker updates** (manual):
```bash
cd /opt/platebridge/docker
sudo docker compose pull
sudo docker compose up -d
```

---

## Troubleshooting

### Issue: Heartbeat 401 Errors

**Problem:** API key is invalid or missing

**Solution:**
```bash
# 1. Generate new API key from portal
# 2. Update .env file
sudo nano /opt/platebridge/docker/.env
# Set: POD_API_KEY=pbk_new_key_here

# 3. Restart
cd /opt/platebridge/docker
sudo docker compose restart platebridge-pod
```

### Issue: No Community ID

**Problem:** Pod not registered properly

**Solution:**
```bash
# Re-register pod
# 1. Generate new registration token from portal
# 2. Update .env with token
# 3. Restart agent

# Or manually set community_id in config:
sudo nano /opt/platebridge/docker/config.yaml
# Add: community_id: "your-community-id"

# Restart
docker compose restart
```

### Issue: Cameras Not Detected

**Problem:** DHCP not working or cameras on wrong network

**Solution:**
```bash
# 1. Check DHCP server
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50

# 2. Check network interface
ip addr show enp1s0  # or your LAN interface

# 3. Monitor DHCP requests
sudo tcpdump -i enp1s0 -n port 67 or port 68

# 4. Check hardware offload is disabled
sudo ethtool -k enp1s0 | grep offload

# 5. Scan for cameras
sudo arp-scan --interface=enp1s0 192.168.1.0/24

# 6. Check DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

### Issue: Docker Won't Start

**Problem:** Network or DNS issues

**Solution:**
```bash
# Check Docker DNS
cat /etc/docker/daemon.json

# Should contain:
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}

# Test Docker network
docker run --rm alpine ping -c 3 google.com

# If fails, restart Docker with proper DNS
sudo systemctl restart docker
```

### Issue: Stream Not Accessible

**Problem:** Tailscale Funnel not enabled or firewall blocking

**Solution:**
```bash
# Enable Tailscale Funnel
sudo tailscale funnel 8000

# Check if port is open
sudo ss -tulpn | grep 8000

# Check firewall
sudo iptables -L -n | grep 8000

# Test stream locally
curl http://localhost:8000/health
```

---

## Monitoring & Maintenance

### Daily Health Check (Automated)

The POD sends heartbeat every 60 seconds. View in portal:
1. Go to **Pods** page
2. Click on your pod
3. View **Last Heartbeat**, **Status**, **System Stats**

### Manual Diagnostics

```bash
# Quick status check
cd /opt/platebridge/docker
docker compose ps

# View all logs
docker compose logs -f

# Check specific service
docker logs platebridge-pod --tail 100
docker logs frigate --tail 100

# System resources
htop
df -h
free -h

# Network status
ip addr show
sudo iptables -L -v -n
```

### Backup Configuration

```bash
# Backup essential configs
sudo tar -czf pod-backup-$(date +%Y%m%d).tar.gz \
  /opt/platebridge/docker/.env \
  /opt/platebridge/docker/config.yaml \
  /opt/platebridge/frigate/config/config.yml \
  /etc/netplan/01-platebridge-network.yaml

# Copy to safe location
scp pod-backup-*.tar.gz user@backup-server:/backups/
```

---

## Performance Optimization

### USB Storage for Recordings

If you have USB storage connected:
```bash
# Check if mounted
df -h | grep frigate

# Should see: /media/frigate

# Verify ownership
ls -la /media/frigate

# Should be: drwxr-xr-x 1000 1000
```

### CPU vs GPU Detection

**For better performance**, use hardware acceleration in Frigate:

```yaml
# Edit frigate config
sudo nano /opt/platebridge/frigate/config/config.yml

# For Intel GPU
ffmpeg:
  hwaccel_args:
    - -hwaccel
    - vaapi
    - -hwaccel_device
    - /dev/dri/renderD128

# For NVIDIA GPU
ffmpeg:
  hwaccel_args:
    - -hwaccel
    - cuda
    - -hwaccel_output_format
    - cuda
```

### Reduce CPU Usage

```yaml
# Lower detection FPS
detect:
  fps: 5  # Lower = less CPU

# Reduce stream quality
cameras:
  front_gate:
    ffmpeg:
      inputs:
        - path: rtsp://camera/substream  # Use substream, not main
          roles: [detect]
```

---

## Security Best Practices

### 1. Change Default Passwords

```bash
# SSH keys (recommended over passwords)
ssh-keygen -t ed25519
ssh-copy-id user@pod-ip

# Disable password auth
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

### 2. Firewall Monitoring

```bash
# View blocked attempts
sudo tail -f /var/log/syslog | grep "iptables.*denied"

# Check fail2ban
sudo fail2ban-client status sshd
```

### 3. Regular Updates

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Update Docker images
cd /opt/platebridge/docker
sudo docker compose pull
sudo docker compose up -d
```

---

## Advanced Configuration

### Custom Stream Port

```bash
# Edit config
sudo nano /opt/platebridge/docker/config.yaml
# Change: stream_port: 8000  # to your preferred port

# Update firewall
sudo iptables -A INPUT -p tcp --dport YOUR_PORT -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4

# Restart
docker compose restart
```

### Multiple Cameras

```yaml
# Edit agent config
sudo nano /opt/platebridge/docker/config.yaml

# Add cameras as array
cameras:
  - camera_id: "camera_1"
    name: "Front Gate"
    rtsp_url: "rtsp://192.168.1.100:554/stream"
    position: "entrance"

  - camera_id: "camera_2"
    name: "Exit Gate"
    rtsp_url: "rtsp://192.168.1.101:554/stream"
    position: "exit"
```

### Custom Detection Rules

```bash
# Edit Frigate config
sudo nano /opt/platebridge/frigate/config/config.yml

# Add custom zones
cameras:
  gate:
    zones:
      entry_zone:
        coordinates: 100,100,200,100,200,200,100,200
        objects:
          - car
          - license_plate
```

---

## Support

**Logs for support:**
```bash
# Collect all logs
cd /opt/platebridge/docker
docker compose logs > pod-logs-$(date +%Y%m%d).txt

# System info
sudo /opt/platebridge/discover-cameras.sh > camera-scan.txt
ip addr show > network-info.txt
sudo iptables -L -v -n > firewall-rules.txt

# Tar everything
tar -czf pod-support-$(date +%Y%m%d).tar.gz *.txt
```

**Common commands:**
```bash
# Full restart
cd /opt/platebridge/docker && sudo docker compose restart

# View live logs
docker logs -f platebridge-pod

# Check system status
sudo systemctl status platebridge-pod

# Test heartbeat manually
curl -X POST https://platebridge.vercel.app/api/pod/heartbeat \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"pod_id":"YOUR_POD_ID","status":"online"}'
```

---

## Success Checklist

- [ ] Installation completed without errors
- [ ] API key configured (no 401 errors)
- [ ] Heartbeat shows "success" in logs
- [ ] Community ID obtained
- [ ] Cameras discovered and added to Frigate
- [ ] Tailscale connected (optional)
- [ ] Services auto-start on boot
- [ ] Portal shows POD online
- [ ] Can view live stream
- [ ] Plate detections appear in portal

**Your POD is now fully autonomous!** 🎉

It will:
- ✅ Auto-start on boot
- ✅ Auto-recover from crashes
- ✅ Send heartbeats to portal
- ✅ Detect license plates
- ✅ Control gates automatically
- ✅ Apply security updates
- ✅ Run 24/7 unattended
