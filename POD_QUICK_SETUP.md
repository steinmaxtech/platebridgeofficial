# 🚀 POD Quick Setup - Dual NIC Configuration

## ⚡ 5-Minute Setup

### **Step 1: Configure Network**
```bash
cd /path/to/platebridge/pod-agent
sudo ./network-config.sh
```
- Detects 2 NICs automatically
- Sets up WAN (internet) + LAN (cameras)
- Configures DHCP for cameras (192.168.100.100-200)

### **Step 2: Connect Cameras**
```
1. Plug cameras into LAN switch
2. Connect switch to POD's LAN port (eth1)
3. Power on cameras
4. Cameras auto-get IPs via DHCP
```

### **Step 3: Discover Cameras**
```bash
sudo ./discover-cameras.sh
```
- Scans camera network
- Tests RTSP streams
- Saves working URLs to `/opt/platebridge/camera-urls.txt`

### **Step 4: Configure POD**
```bash
sudo cp config-dual-nic.yaml /opt/platebridge/config.yaml
sudo nano /opt/platebridge/config.yaml
```

Update:
```yaml
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_your_key"
site_id: "your-site-id"

cameras:
  - id: "gate-camera-1"
    rtsp_url: "rtsp://192.168.100.100:554/stream"
```

### **Step 5: Start POD Agent**
```bash
cd /opt/platebridge
sudo docker compose up -d
# or
sudo python3 agent.py
```

---

## 📊 Network Architecture

```
Internet ──▶ WAN (eth0) ──▶ POD (192.168.100.1) ──▶ LAN (eth1) ──▶ Cameras
                                                          │
                                                          ├─ Camera 1: .100
                                                          ├─ Camera 2: .101
                                                          └─ Camera 3: .102
```

---

## 🔧 Quick Troubleshooting

### No Internet?
```bash
ping 8.8.8.8
sudo netplan apply
```

### Cameras Not Found?
```bash
sudo arp-scan --interface=eth1 192.168.100.0/24
cat /var/lib/misc/dnsmasq.leases
sudo systemctl restart dnsmasq
```

### RTSP Not Working?
```bash
# Test stream
ffplay -rtsp_transport tcp rtsp://192.168.100.100:554/stream

# Common paths to try:
# /stream, /h264, /live, /ch01, /Streaming/Channels/101
```

---

## 📁 Key Files

```
/etc/netplan/01-platebridge-network.yaml  ← Network config
/etc/dnsmasq.d/platebridge-cameras.conf   ← DHCP config
/opt/platebridge/config.yaml              ← POD config
/opt/platebridge/camera-urls.txt          ← Discovered cameras
```

---

## ✅ Verification

```bash
# 1. Check interfaces
ip addr show

# 2. Check DHCP leases
cat /var/lib/misc/dnsmasq.leases

# 3. Scan cameras
sudo arp-scan --interface=eth1 192.168.100.0/24

# 4. Test RTSP
ffprobe rtsp://192.168.100.100:554/stream

# 5. Check POD agent
tail -f /opt/platebridge/logs/pod-agent.log
```

---

## 🎯 Default Network Settings

| Setting | Value |
|---------|-------|
| WAN Interface | eth0 (DHCP) |
| LAN Interface | eth1 (Static) |
| POD LAN IP | 192.168.100.1 |
| Camera Network | 192.168.100.0/24 |
| DHCP Range | .100 - .200 |
| Gateway | 192.168.100.1 |
| DNS | 8.8.8.8, 8.8.4.4 |

---

**Full guide: `POD_DUAL_NIC_SETUP.md`**
