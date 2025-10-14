# PlateBridge POD Installation Checklist

## Pre-Installation

- [ ] Ubuntu 20.04 or 24.04 LTS installed
- [ ] Two network interfaces available (WAN + LAN)
- [ ] USB drive connected (for recordings)
- [ ] Internet connectivity working
- [ ] Root/sudo access available
- [ ] Registration token from portal ready

## Installation Steps

### 1. Run Main Installation

```bash
cd pod-agent
sudo ./install-complete.sh
```

**During installation you will:**
- [ ] Confirm network interfaces (WAN and LAN)
- [ ] USB drive detected and formatted
- [ ] Portal URL entered
- [ ] Registration token entered
- [ ] POD successfully registered

### 2. Post-Installation Verification

```bash
# Check services are running
cd /opt/platebridge/docker
docker compose ps
```

**Verify:**
- [ ] Frigate container running
- [ ] mosquitto container running
- [ ] platebridge-agent container running

### 3. Network Verification

```bash
# Check DHCP is working
cat /var/lib/misc/dnsmasq.leases

# Check firewall rules
sudo iptables -L -n | grep -E "5000|8554|8555"
```

**Verify:**
- [ ] LAN interface has IP 192.168.100.1
- [ ] DHCP server listening on port 67
- [ ] Firewall rules allow WAN access to Frigate

### 4. Camera Discovery

```bash
# Connect cameras to LAN interface
# Run discovery
/opt/platebridge/discover-cameras.sh
```

**Verify:**
- [ ] Cameras getting DHCP addresses (192.168.100.x)
- [ ] Cameras responding to RTSP probes
- [ ] Camera streams accessible

### 5. Configure Frigate

Edit `/opt/platebridge/frigate/config/config.yml`:

```yaml
cameras:
  camera_1:
    ffmpeg:
      inputs:
        - path: rtsp://admin:password@192.168.100.100:554/
          roles: [detect]
        - path: rtsp://admin:password@192.168.100.100:554/
          roles: [record]
    # ... rest of config
```

**Verify:**
- [ ] Camera credentials correct
- [ ] RTSP paths match camera model
- [ ] Recordings saving to `/media/frigate/recordings`

### 6. Test Remote Access

From a remote machine:

```bash
# Test SSH
ssh user@<pod-wan-ip>

# Test Frigate UI
http://<pod-wan-ip>:5000

# Test RTSP
rtsp://<pod-wan-ip>:8554/camera_1
```

**Verify:**
- [ ] SSH accessible from internet
- [ ] Frigate UI loads from internet
- [ ] RTSP streams accessible from internet
- [ ] WebRTC working (port 8555)

### 7. Portal Integration

Check portal:

**Verify:**
- [ ] POD shows online in portal
- [ ] Heartbeats being received
- [ ] Camera detections appearing
- [ ] Plate reads being logged

### 8. Final Hardening

```bash
# Apply production hardening
sudo ./final-lockdown.sh
```

**Verify:**
- [ ] Kernel parameters hardened
- [ ] Monitoring script created
- [ ] Backup script created
- [ ] All services still running

## Post-Installation Monitoring

### Daily Checks

```bash
# System health
/opt/platebridge/monitor-system.sh

# Service status
cd /opt/platebridge/docker && docker compose ps

# Disk space
df -h /media/frigate
```

### Weekly Checks

```bash
# Backup configuration
/opt/platebridge/backup-config.sh

# Check fail2ban
sudo fail2ban-client status sshd

# Review logs
docker compose logs --tail=100
```

### Monthly Checks

```bash
# Update system
sudo apt update && sudo apt upgrade

# Update Docker images
docker compose pull
docker compose up -d

# Verify backups
ls -lh /opt/platebridge/backups/
```

## Troubleshooting

### Services Not Starting

```bash
# Check Docker
sudo systemctl status docker

# Check logs
journalctl -xe

# Restart services
cd /opt/platebridge/docker
docker compose restart
```

### DHCP Not Working

```bash
# Diagnose
sudo ./utilities/diagnose-dhcp.sh

# Fix
sudo ./utilities/fix-dhcp-simple.sh
```

### No Internet on Cameras

```bash
# Check NAT rules
sudo iptables -t nat -L -n -v

# Check forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1
```

### Recordings Not Saving

```bash
# Check USB mount
df -h /media/frigate

# Check permissions
ls -la /media/frigate/recordings

# Check Frigate logs
docker logs frigate
```

## Success Criteria

Installation is complete when:

- [x] All Docker containers running
- [x] Cameras receiving DHCP and accessible
- [x] Frigate recording to USB drive
- [x] POD online in portal
- [x] Remote access working (SSH + Frigate UI)
- [x] Firewall protecting camera network
- [x] Auto-updates configured
- [x] Monitoring and backup scripts in place

## Support

For issues, check:
1. `utilities/` folder for diagnostic scripts
2. Documentation markdown files
3. Docker logs: `docker compose logs`
4. System logs: `journalctl -xe`
