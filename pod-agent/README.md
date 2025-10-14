# PlateBridge POD Installation

Complete installation package for PlateBridge POD devices.

## Main Installation Scripts

### `install-complete.sh` - Complete Automated Installation
**Primary installation script** - Run this on a fresh Ubuntu system to set up everything.

**What it does:**
- Installs Docker & Docker Compose
- Configures dual-NIC network (WAN cellular + LAN cameras)
- Sets up DHCP server for camera network
- Configures firewall with production security
- Installs Frigate NVR with MQTT
- Auto-detects and mounts USB storage for recordings
- Installs PlateBridge POD agent
- Configures systemd services for auto-start
- Hardens system security (fail2ban, auto-updates, SSH)

**Usage:**
```bash
sudo ./install-complete.sh
```

**Requirements:**
- Ubuntu 20.04 or 24.04 LTS
- Two network interfaces (WAN and LAN)
- USB drive for recordings (optional but recommended)
- Internet connectivity

### `final-lockdown.sh` - Production Hardening
Run this **after** installation is tested and working.

**What it does:**
- Additional kernel hardening
- Creates monitoring scripts
- Sets up automated config backups
- Final security lockdown

**Usage:**
```bash
sudo ./final-lockdown.sh
```

## Support Scripts

### `install-python-agent.sh`
Installs Python POD agent standalone (without Docker).

### Python Agents
- `complete_pod_agent.py` - Full POD agent with all features
- `agent.py` - Simplified agent
- `stream_server.py` - Streaming server

## Configuration Files

### `config.example.yaml`
Example POD agent configuration.

### `config-dual-nic.yaml`
Example dual-NIC network configuration.

### `docker-compose.yml`
Docker services: Frigate, MQTT, POD agent.

### `Dockerfile`
POD agent container build.

## Utilities Folder

See `utilities/README.md` for troubleshooting and diagnostic scripts.

## Golden Image

See `golden-image/` folder for disk imaging tools.

## Quick Start

### 1. Fresh Installation

```bash
# Download and run complete installation
sudo ./install-complete.sh

# Follow prompts to configure:
# - Network interfaces (WAN and LAN)
# - Portal registration token
```

### 2. After Installation

```bash
# Check services
cd /opt/platebridge/docker && docker compose ps

# View logs
docker compose logs -f

# Discover cameras
/opt/platebridge/discover-cameras.sh

# Monitor system
/opt/platebridge/monitor-system.sh
```

### 3. Production Hardening

```bash
# After testing, apply final lockdown
sudo ./final-lockdown.sh
```

## Network Architecture

```
Internet (Cellular)
       |
   [WAN NIC] - DHCP from carrier
       |
   [POD Device] - Router/Firewall
       |
   [LAN NIC] - 192.168.100.1/24
       |
   [IP Cameras] - DHCP 192.168.100.100-200
```

**Security:**
- Cameras isolated from internet
- NAT/Masquerade for camera traffic
- Firewall drops all by default
- SSH rate limiting + fail2ban
- Automatic security updates

## Accessing Services

### From WAN (Internet):
- SSH: `ssh user@<pod-ip>` (port 22)
- Frigate UI: `http://<pod-ip>:5000`
- RTSP Stream: `rtsp://<pod-ip>:8554`
- WebRTC: `http://<pod-ip>:8555`

### From LAN (Cameras):
- POD Gateway: `192.168.100.1`
- All POD services accessible

## Troubleshooting

### DHCP Issues
```bash
sudo ./utilities/diagnose-dhcp.sh
sudo ./utilities/fix-dhcp-simple.sh
```

### Camera Discovery
```bash
sudo ./utilities/discover-cameras.sh
```

### Network Issues
```bash
sudo ./utilities/basic-network-test.sh
```

### View Logs
```bash
# System logs
journalctl -xe

# DHCP logs
journalctl -u dnsmasq -f

# Docker logs
cd /opt/platebridge/docker
docker compose logs -f
```

## Configuration Locations

- Network: `/etc/netplan/01-platebridge-network.yaml`
- DHCP: `/etc/dnsmasq.d/platebridge-cameras.conf`
- Firewall: `/etc/iptables/rules.v4`
- Docker: `/opt/platebridge/docker/docker-compose.yml`
- Frigate: `/opt/platebridge/frigate/config/config.yml`
- Portal: `/opt/platebridge/docker/.env`
- Recordings: `/media/frigate/`

## Support & Documentation

See individual markdown files for detailed guides:
- `COMPLETE_POD_CONNECTION_GUIDE.md` - Step-by-step setup
- `POD_SECURITY_GUIDE.md` - Security hardening details
- `INSTALLATION_SUMMARY.md` - Installation overview
- `DHCP_FIXES_APPLIED.md` - DHCP troubleshooting

## License

Copyright © 2025 PlateBridge
