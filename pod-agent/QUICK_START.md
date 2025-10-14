# PlateBridge POD - Quick Start Guide

## Overview

Single-command installation for PlateBridge POD devices.

## What You Need

- Ubuntu 20.04 or 24.04 LTS
- Two network interfaces (cellular WAN + camera LAN)
- USB drive (960GB recommended for recordings)
- Portal registration token

## Installation

### Step 1: Download and Run

```bash
cd pod-agent
sudo ./install-complete.sh
```

### Step 2: Follow Prompts

The installer will ask for:
1. **WAN interface** (cellular/internet) - default: enp3s0
2. **LAN interface** (camera network) - default: enp1s0
3. **Portal URL** - your PlateBridge portal
4. **Registration token** - from portal's Properties page

### Step 3: Wait for Completion

Installation takes 5-10 minutes:
- Installs Docker + all dependencies
- Configures network and firewall
- Mounts USB drive for recordings
- Sets up Frigate NVR
- Registers POD with portal

## After Installation

### Verify Services

```bash
cd /opt/platebridge/docker
docker compose ps
```

All three containers should show "Up":
- frigate
- mosquitto  
- platebridge-agent

### Connect Cameras

1. Plug cameras into LAN interface
2. Cameras get DHCP addresses (192.168.100.x)
3. Discover cameras:

```bash
/opt/platebridge/discover-cameras.sh
```

### Configure Frigate

Edit camera config:

```bash
sudo nano /opt/platebridge/frigate/config/config.yml
```

Add your cameras:

```yaml
cameras:
  front_gate:
    ffmpeg:
      inputs:
        - path: rtsp://admin:password@192.168.100.100:554/
          roles: [detect]
        - path: rtsp://admin:password@192.168.100.100:554/
          roles: [record]
    detect:
      width: 640
      height: 360
      fps: 5
```

Restart Frigate:

```bash
cd /opt/platebridge/docker
docker compose restart frigate
```

### Access Frigate

From any device on internet:

```
http://<your-pod-wan-ip>:5000
```

## Final Hardening (Optional)

After testing everything works:

```bash
sudo ./final-lockdown.sh
```

This applies production security hardening.

## Common Commands

```bash
# Check system health
/opt/platebridge/monitor-system.sh

# Backup configuration
/opt/platebridge/backup-config.sh

# View logs
cd /opt/platebridge/docker
docker compose logs -f

# Restart services
docker compose restart

# Discover cameras
/opt/platebridge/discover-cameras.sh

# Check firewall
sudo iptables -L -n

# View DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

## Troubleshooting

### Services won't start
```bash
docker compose logs
sudo systemctl status docker
```

### DHCP not working
```bash
sudo ./utilities/diagnose-dhcp.sh
sudo ./utilities/fix-dhcp-simple.sh
```

### Can't access Frigate remotely
```bash
# Check firewall allows port 5000
sudo iptables -L -n | grep 5000

# Check WAN IP
ip addr show | grep "inet "
```

## Default Network Setup

- **WAN Interface**: Gets IP from cellular carrier (DHCP)
- **LAN Interface**: 192.168.100.1/24
- **Camera DHCP Range**: 192.168.100.100-200
- **Cameras**: Isolated from internet, NAT through POD

## Firewall (WAN Access)

- SSH: Port 22
- Frigate UI: Port 5000
- RTSP Streams: Port 8554
- WebRTC: Port 8555
- Stream API: Port 8000

## Storage

- **Recordings**: `/media/frigate/recordings` (USB drive)
- **Clips**: `/media/frigate/clips`
- **Snapshots**: `/media/frigate/snapshots`
- **Database**: `/media/frigate/frigate.db`

## That's It!

Your POD is now:
- ✓ Routing camera traffic through cellular
- ✓ Recording to USB drive
- ✓ Sending detections to portal
- ✓ Accessible remotely via WAN
- ✓ Secured with firewall
- ✓ Auto-updating

## Need Help?

Check these files:
- `README.md` - Full documentation
- `INSTALLATION_CHECKLIST.md` - Verification steps
- `utilities/README.md` - Troubleshooting tools
