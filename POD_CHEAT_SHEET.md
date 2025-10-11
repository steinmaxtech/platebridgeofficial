# 🚀 PlateBridge POD - Quick Reference Cheat Sheet

## 📥 Get Started (30 seconds)

```bash
# Clone repo
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent
chmod +x *.sh
```

---

## 🔧 Setup Commands

### **Automated Setup**
```bash
sudo ./setup.sh
```

### **Network Configuration (Dual-NIC)**
```bash
sudo ./network-config.sh
```

### **Camera Discovery**
```bash
sudo ./discover-cameras.sh
```

---

## 📊 Status & Monitoring

```bash
# Network status
ip addr show

# DHCP leases (cameras)
cat /var/lib/misc/dnsmasq.leases

# Scan for cameras
sudo arp-scan --interface=eth1 192.168.100.0/24

# Test RTSP stream
ffplay -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# POD logs
tail -f /opt/platebridge/logs/pod-agent.log

# Docker services
cd /opt/platebridge/docker && docker compose ps
```

---

## 🌐 Default Network Settings

| Item | Value |
|------|-------|
| WAN Interface | eth0 (DHCP) |
| LAN Interface | eth1 (Static) |
| POD LAN IP | 192.168.100.1 |
| Camera Network | 192.168.100.0/24 |
| Camera DHCP | .100 - .200 |
| Gateway | 192.168.100.1 |
| DNS | 8.8.8.8 |

---

## 📹 Common RTSP URLs

```bash
# Try these paths (replace <ip> with camera IP)
rtsp://<ip>:554/stream
rtsp://<ip>:554/h264
rtsp://<ip>:554/live
rtsp://<ip>:554/ch01
rtsp://<ip>:554/Streaming/Channels/101

# With authentication
rtsp://admin:password@<ip>:554/stream
```

---

## 🔧 Quick Fixes

### No Internet
```bash
ping 8.8.8.8
sudo netplan apply
sudo systemctl restart systemd-networkd
```

### Cameras Not Found
```bash
sudo systemctl restart dnsmasq
sudo arp-scan --interface=eth1 192.168.100.0/24
```

### RTSP Not Working
```bash
ffprobe -rtsp_transport tcp rtsp://192.168.100.100:554/stream
# Try different paths: /h264, /live, /ch01
```

### Restart Services
```bash
cd /opt/platebridge/docker
docker compose restart
```

---

## 📁 Important Files

```
/opt/platebridge/config.yaml              # POD config
/opt/platebridge/network-info.txt         # Network summary
/opt/platebridge/camera-urls.txt          # Discovered cameras
/etc/netplan/01-platebridge-network.yaml  # Network config
/etc/dnsmasq.d/platebridge-cameras.conf   # DHCP config
/var/lib/misc/dnsmasq.leases             # DHCP leases
```

---

## 🎯 Configuration Quick Edit

```bash
# Edit POD config
sudo nano /opt/platebridge/config.yaml

# Edit network config
sudo nano /etc/netplan/01-platebridge-network.yaml
sudo netplan apply

# Edit DHCP config
sudo nano /etc/dnsmasq.d/platebridge-cameras.conf
sudo systemctl restart dnsmasq
```

---

## 🔍 Troubleshooting Flow

```
1. POD online?           → ping 8.8.8.8
2. Cameras connected?    → sudo arp-scan --interface=eth1 192.168.100.0/24
3. DHCP working?         → cat /var/lib/misc/dnsmasq.leases
4. Can reach camera?     → ping 192.168.100.100
5. RTSP working?         → ffplay rtsp://192.168.100.100:554/stream
6. Services running?     → docker compose ps
7. Check logs?           → tail -f /opt/platebridge/logs/pod-agent.log
```

---

## 🚀 Quick Deploy

**From scratch to running POD:**
```bash
# 1. Clone (30 sec)
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent

# 2. Network setup (5 min)
sudo ./network-config.sh

# 3. Connect cameras physically

# 4. Discover cameras (1 min)
sudo ./discover-cameras.sh

# 5. Configure (2 min)
sudo cp config-dual-nic.yaml /opt/platebridge/config.yaml
sudo nano /opt/platebridge/config.yaml
# Update: portal_url, pod_api_key, site_id, camera URLs

# 6. Start (30 sec)
cd /opt/platebridge/docker
docker compose up -d

# 7. Verify
docker compose logs -f
```

**Total: ~10 minutes! 🎉**

---

## 🔗 Useful Links

- **Docs**: `POD_QUICK_START.md` - Complete guide
- **Docs**: `POD_DUAL_NIC_SETUP.md` - Dual-NIC details
- **Docs**: `POD_SETUP_GUIDE.md` - Full setup
- **GitHub**: `https://github.com/your-org/platebridge`
- **Portal**: `https://your-portal.vercel.app`

---

## 💡 Pro Tips

✅ Always use `sudo arp-scan` to find cameras after connecting
✅ Test RTSP with `ffplay` before adding to config
✅ Check DHCP leases to see what IPs cameras got
✅ Use `docker compose logs -f` to watch live activity
✅ Keep config.yaml backed up: `cp config.yaml config.yaml.backup`
✅ Restart services after config changes: `docker compose restart`
✅ Check portal for POD status and heartbeat

---

**🎯 Most Common Command:**
```bash
sudo arp-scan --interface=eth1 192.168.100.0/24
```
*Use this to find all cameras on your network!*
