# Connect Your First POD - Quick Start Guide

Get your PlateBridge POD up and running in 10 minutes!

## What is a POD?

A POD is a device (Raspberry Pi, NUC, or any Linux box) at your gate that:
- Connects to IP cameras with license plate detection
- Streams live video to your portal
- Records clips when plates are detected
- Auto-reports detections to portal
- Auto-registers itself and cameras
- Communicates with your cloud portal for access control

## Quick Setup (3 Steps)

### Step 1: Get Your Credentials from Portal

1. **Login to your PlateBridge portal**
   - Go to https://your-portal.vercel.app

2. **Create/Find Your Site**
   - Navigate to "Properties" or "Sites"
   - Create a new site or select existing one
   - Copy the **Site ID** (UUID format)

3. **Create/Find Your Camera**
   - Navigate to "Cameras"
   - Create a new camera or select existing
   - Copy the **Camera ID** (UUID format)

4. **Generate POD API Key**
   - Navigate to "Pods" page
   - Click "Generate API Key"
   - Copy the key (starts with `pbk_`)
   - **Save it now - you won't see it again!**

5. **Get Your Company ID**
   - Navigate to "Companies"
   - Copy your **Company ID** (UUID format)

### Step 2: Install on Your POD Device

**SSH into your POD:**
```bash
ssh pi@your-pod-ip
# or ssh ubuntu@your-pod-ip
```

**Download and run the installer:**
```bash
curl -o install-pod.sh https://your-portal.vercel.app/install-pod.sh
chmod +x install-pod.sh
sudo ./install-pod.sh
```

**Or manual installation:**
```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y python3 python3-pip ffmpeg

# Create directory
sudo mkdir -p /opt/platebridge-pod
cd /opt/platebridge-pod

# Download files (copy from your portal's pod-agent folder)
# Copy: complete_pod_agent.py, config.example.yaml, requirements.txt

# Install Python packages
sudo pip3 install -r requirements.txt

# Create config
sudo cp config.example.yaml config.yaml
sudo nano config.yaml  # Edit with your values
```

### Step 3: Configure and Start

**Edit config.yaml:**
```yaml
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_xxxxx"  # From Step 1
pod_id: "main-gate-pod"
camera_id: "your-camera-uuid"  # From Step 1
site_id: "your-site-uuid"  # From Step 1
company_id: "your-company-uuid"  # From Step 1
camera_rtsp_url: "rtsp://192.168.1.100:554/stream"
```

**Start the POD agent:**
```bash
# Test run first
sudo python3 complete_pod_agent.py config.yaml

# If it works, create systemd service:
sudo nano /etc/systemd/system/platebridge-pod.service
```

**Service file content:**
```ini
[Unit]
Description=PlateBridge Pod Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/platebridge-pod
ExecStart=/usr/bin/python3 /opt/platebridge-pod/complete_pod_agent.py /opt/platebridge-pod/config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable and start:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable platebridge-pod
sudo systemctl start platebridge-pod
sudo systemctl status platebridge-pod
```

## Verify It's Working

### 1. Check Logs
```bash
sudo journalctl -u platebridge-pod -f
```

You should see:
```
PlateBridge Complete Pod Agent
Portal: https://your-portal.vercel.app
Pod ID: main-gate-pod
Whitelist refreshed: X plates
Connected to MQTT broker
Stream started successfully
Starting stream server on port 8000
Heartbeat sent
```

### 2. Check Portal

**Go to portal → Pods page:**
- Your POD should show as "Online"
- Last heartbeat should be recent

**Go to portal → Cameras page:**
- Your camera should show as "Active"
- Click "View Live Stream" - you should see video

### 3. Test Detection

**Manually trigger a detection:**
```bash
curl -X POST "https://your-portal.vercel.app/api/pod/detect" \
  -H "Authorization: Bearer pbk_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{
    "site_id": "your-site-id",
    "plate": "TEST123",
    "camera": "camera-1",
    "pod_name": "main-gate-pod"
  }'
```

Check portal's Audit Logs - you should see the detection.

## Common Issues

### POD Shows Offline

**Check service is running:**
```bash
sudo systemctl status platebridge-pod
```

**Check network connectivity:**
```bash
ping your-portal.vercel.app
```

**Check API key:**
```bash
# Make sure pod_api_key in config.yaml is correct
cat /opt/platebridge-pod/config.yaml | grep pod_api_key
```

### Stream Not Working

**Check FFmpeg is running:**
```bash
ps aux | grep ffmpeg
```

**Check RTSP URL:**
```bash
ffplay rtsp://your-camera-ip:554/stream
# Press Q to quit
```

**Check stream files:**
```bash
ls -la /tmp/hls_output/
# Should see stream.m3u8 and segment files
```

**Check stream port is open:**
```bash
curl http://localhost:8000/health
# Should return: {"status":"ok","pod_id":"...","streaming":true}
```

### Recordings Not Uploading

**Check recordings directory:**
```bash
ls -la /tmp/recordings/
```

**Check portal API:**
```bash
curl "https://your-portal.vercel.app/api/pod/recordings/upload-url" \
  -H "Authorization: Bearer pbk_your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"camera_id":"your-camera-id","filename":"test.mp4"}'
```

**Check Supabase Storage:**
- Login to Supabase dashboard
- Go to Storage
- Check "camera-recordings" bucket exists

## Environment Variables (Portal Side)

Set these in Vercel:

**Required:**
- `NEXT_PUBLIC_SUPABASE_URL` - Your Supabase project URL
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` - Your Supabase anon key
- `SUPABASE_SERVICE_ROLE_KEY` - Your Supabase service role key

**For Streaming:**
- `POD_STREAM_SECRET` - Shared secret for stream tokens (same as in config.yaml)

## Configuration Options

### Enable/Disable Features

```yaml
# In config.yaml:

enable_streaming: false  # Disable live streaming
enable_mqtt: false  # Disable Frigate integration
record_on_detection: false  # Disable auto-recording
```

### Adjust Performance

```yaml
# Lower quality for slower networks:
stream_quality: "low"  # Options: low, medium, high

# Record shorter clips:
recording_duration: 15  # Seconds

# Reduce refresh frequency:
whitelist_refresh_interval: 600  # 10 minutes
heartbeat_interval: 120  # 2 minutes
```

### Multiple Cameras

If you have multiple cameras on one POD:

1. Create separate camera entries in portal
2. Run multiple agent instances with different configs:

```bash
# Camera 1
python3 complete_pod_agent.py config_camera1.yaml &

# Camera 2
python3 complete_pod_agent.py config_camera2.yaml &
```

Or use a process manager like supervisor.

## Network Requirements

**Outbound (POD → Internet):**
- HTTPS (443) to your portal domain
- HTTPS (443) to Supabase (for uploads)

**Inbound (Internet → POD) - Optional for streaming:**
- Port 8000 (or custom stream_port)
- Only needed if you want portal users to access live streams
- Can use VPN/Tailscale instead of opening ports

## Security Best Practices

1. **API Key Security:**
   - Never commit config.yaml to git
   - Rotate keys regularly in portal
   - Each POD should have unique API key

2. **Network Security:**
   - Use firewall to restrict outbound traffic
   - Consider VPN for stream access
   - Keep POD device updated

3. **Stream Security:**
   - Tokens expire in 10 minutes
   - Use same `stream_secret` in config and portal
   - Never expose stream port without token validation

## Production Checklist

- [ ] POD shows online in portal
- [ ] Live stream accessible from portal
- [ ] Test detection logged in audit
- [ ] Recording uploads working
- [ ] Heartbeat every 60 seconds
- [ ] Whitelist refreshing every 5 minutes
- [ ] Service auto-starts on boot
- [ ] Logs being monitored
- [ ] API key backed up securely
- [ ] Firewall rules configured

## Next Steps

1. **Add plates to whitelist** in portal
2. **Test gate integration** if using Gatewise
3. **Set up monitoring** (check logs daily)
4. **Configure alerts** for POD offline
5. **Review recordings** periodically

## Support

**Check logs first:**
```bash
sudo journalctl -u platebridge-pod -f
```

**Common log messages:**

✅ Good:
- "Whitelist refreshed: X plates"
- "Heartbeat sent"
- "Stream started successfully"
- "Portal response: action=allow, gate_opened=true"

❌ Problems:
- "Failed to fetch whitelist" - Check portal URL and API key
- "MQTT connection failed" - Check MQTT settings
- "Upload failed" - Check Supabase config
- "Invalid token" - Check stream_secret matches portal

**Test endpoints:**
```bash
# Health check
curl http://localhost:8000/health

# Portal connectivity
curl https://your-portal.vercel.app/api/health
```

## Architecture Overview

```
[Camera] → RTSP → [POD Device]
                      ↓
    ┌─────────────────┴─────────────────┐
    │                                   │
    ▼                                   ▼
[FFmpeg]                         [Agent Process]
    │                                   │
    ├─ HLS Streaming                   ├─ MQTT Listener
    ├─ Recording                        ├─ Plate Detection
    └─ Port 8000                        ├─ Whitelist Cache
                                        ├─ Heartbeat
                                        └─ Upload Manager
                                              │
                                              ▼
                                    [Portal + Supabase]
                                              │
                                              ▼
                                    [Users via Web Browser]
```

That's it! Your POD is now connected and serving camera feeds to your portal.
