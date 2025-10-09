# Complete POD Connection Guide

## Overview

This guide explains how PODs connect to your PlateBridge portal and serve camera feeds. Everything is designed to be secure, automated, and easy to deploy.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   POD DEVICE                        │
│                                                     │
│  ┌────────────┐      ┌──────────────────┐         │
│  │  Camera    │─RTSP→│  complete_pod_   │         │
│  │  (RTSP)    │      │     agent.py     │         │
│  └────────────┘      └──────────────────┘         │
│                             │                       │
│                             ├─→ FFmpeg (streaming) │
│                             ├─→ MQTT Listener      │
│                             ├─→ Plate Detection    │
│                             ├─→ Recording          │
│                             └─→ Upload Manager     │
│                                                     │
│  Port 8000: Stream Server (HLS)                    │
└─────────────────────────────────────────────────────┘
                     ↓ HTTPS
        ┌───────────────────────────┐
        │  Your Portal (Vercel)     │
        │                           │
        │  APIs:                    │
        │  - /api/pod/detect        │
        │  - /api/pod/heartbeat     │
        │  - /api/pod/stream-token  │
        │  - /api/pod/recordings/*  │
        └───────────────────────────┘
                     ↓
        ┌───────────────────────────┐
        │  Supabase                 │
        │  - Database (RLS)         │
        │  - Storage (recordings)   │
        └───────────────────────────┘
                     ↓
        ┌───────────────────────────┐
        │  Users (Web Browser)      │
        │  - View live streams      │
        │  - Access recordings      │
        │  - Manage whitelist       │
        └───────────────────────────┘
```

## How PODs Connect and Serve

### 1. Initial Setup (One-Time)

**User Actions:**

1. **Create infrastructure in portal:**
   - Create Company
   - Create Community
   - Create Site
   - Create Camera entry
   - Generate POD API key

2. **Install agent on POD device:**
   ```bash
   # SSH into POD
   ssh pi@pod-ip

   # Download and run installer
   curl -o install-pod.sh https://your-portal.vercel.app/install-pod.sh
   chmod +x install-pod.sh
   sudo ./install-pod.sh
   ```

3. **Configure POD:**
   - Enter portal URL
   - Enter POD API key
   - Enter Camera ID
   - Enter RTSP camera URL
   - Set stream secret

### 2. POD Startup Sequence

When the POD agent starts:

```python
# 1. Load configuration
config = load_config('config.yaml')

# 2. Connect to portal and fetch whitelist
whitelist = fetch_from_portal('/api/plates')
cache_locally(whitelist)  # Works offline!

# 3. Start FFmpeg for streaming
ffmpeg_process = start_stream(
    rtsp_url='rtsp://camera:554/stream',
    output='/tmp/hls_output/stream.m3u8'
)

# 4. Start Flask stream server on port 8000
app.run(host='0.0.0.0', port=8000)

# 5. Connect to MQTT (Frigate)
mqtt_client.connect('localhost', 1883)
mqtt_client.subscribe('frigate/events')

# 6. Start heartbeat loop (every 60 seconds)
while True:
    send_heartbeat_to_portal()
    refresh_whitelist_if_needed()
    sleep(60)
```

### 3. Live Stream Flow

**User clicks "View Live Stream":**

```
1. Browser → Portal: Request stream for Camera X
   POST /api/pod/stream-token
   Authorization: Bearer <user-session-token>
   Body: { "camera_id": "xxx" }

2. Portal validates:
   - User has session
   - User has access to camera (via company membership)
   - Camera exists and is online

3. Portal generates signed token:
   token = {
     "user_id": "xxx",
     "camera_id": "xxx",
     "pod_id": "xxx",
     "exp": now + 10 minutes
   }
   signature = sha256(json(token) + secret)
   signed_token = base64(token) + "." + signature

4. Portal returns:
   {
     "stream_url": "https://pod-ip:8000/stream?token=xxx",
     "expires_in": 600
   }

5. Browser → POD: Request HLS stream
   GET https://pod-ip:8000/stream?token=xxx

6. POD validates token:
   - Decode and verify signature
   - Check expiration (10 min)
   - Check camera_id matches

7. POD serves HLS playlist:
   - Returns stream.m3u8
   - Browser requests segments
   - POD serves segment_001.ts, segment_002.ts, etc.

8. Browser plays video using HLS.js or native
```

**Security:**
- Tokens expire in 10 minutes
- Each token tied to specific user and camera
- POD validates signature before serving
- Works even if POD has no database access

### 4. Recording Flow

**POD detects a plate:**

```
1. Camera → Frigate: Video feed
2. Frigate → MQTT: Publishes plate detection event
3. POD MQTT Listener: Receives event
   {
     "type": "new",
     "after": {
       "label": "license_plate",
       "sub_label": "ABC123",
       "score": 0.95
     }
   }

4. POD checks local whitelist cache:
   if plate in whitelist:
       decision = "allow"
   else:
       decision = "deny"

5. POD → Portal: Send detection
   POST /api/pod/detect
   Authorization: Bearer <pod-api-key>
   Body: {
     "site_id": "xxx",
     "plate": "ABC123",
     "camera": "camera-1",
     "pod_name": "main-gate-pod"
   }

6. Portal validates:
   - POD API key is valid
   - Site exists
   - Logs to audit table
   - Opens gate via Gatewise if allowed

7. POD records clip (if configured):
   ffmpeg -i rtsp://camera -t 30 -c copy /tmp/recording.mp4

8. POD → Portal: Request upload URL
   POST /api/pod/recordings/upload-url
   Authorization: Bearer <pod-api-key>
   Body: {
     "camera_id": "xxx",
     "filename": "recording_20251009_120000.mp4"
   }

9. Portal generates signed upload URL:
   - Verifies POD owns camera
   - Creates signed URL for Supabase Storage
   - URL expires in 1 hour

10. POD → Supabase Storage: Upload file directly
    PUT <signed-url>
    Body: <video-file-bytes>

11. POD → Portal: Confirm upload
    POST /api/pod/recordings/confirm
    Body: {
      "camera_id": "xxx",
      "file_path": "recordings/community/camera/file.mp4",
      "duration_seconds": 30,
      "event_type": "plate_detection",
      "plate_number": "ABC123"
    }

12. Portal creates database record:
    INSERT INTO camera_recordings (...)

13. POD deletes local file (cleanup)

14. User views recordings:
    - Browser → Portal: GET /api/pod/recordings?camera_id=xxx
    - Portal validates user access (RLS)
    - Portal generates signed download URLs
    - Browser plays video from Supabase Storage
```

### 5. Heartbeat System

POD sends heartbeat every 60 seconds:

```python
POST /api/pod/heartbeat
Authorization: Bearer <pod-api-key>
Body: {
  "pod_id": "main-gate-pod",
  "camera_id": "xxx",
  "stream_url": "https://public-ip:8000/stream",
  "status": "online"
}
```

**Portal updates:**
- `cameras.stream_url` - For users to access stream
- `cameras.status` - Shows as "active"
- `cameras.updated_at` - Tracks last seen

**If heartbeat stops:**
- Camera status becomes "inactive" after 5 minutes
- Portal shows "Offline" in UI
- Alerts can be triggered

### 6. Whitelist Synchronization

POD refreshes whitelist every 5 minutes:

```python
GET /api/plates?site=main-gate&company_id=xxx

Response:
{
  "config_version": 42,
  "entries": [
    {
      "plate": "ABC123",
      "unit": "101",
      "tenant": "John Doe",
      "enabled": true,
      "starts": "2025-01-01",
      "ends": "2026-01-01"
    }
  ]
}
```

**POD behavior:**
- Compares `config_version` with cached version
- If different, updates local cache
- Saves to `/tmp/whitelist_cache.json`
- Works offline if portal is unreachable

**Manual sync trigger:**
```bash
POST /api/nudge
Body: { "property": "main-gate", "reason": "Added new plate" }
```

This increments `config_version`, forcing PODs to refresh immediately.

## Network Requirements

### POD → Internet (Outbound)

Required for POD to function:

- **HTTPS (443)** to your portal domain
  - Used for: API calls, heartbeats, uploads
  - Frequency: Continuous (heartbeat every 60s)

- **HTTPS (443)** to Supabase
  - Used for: Recording uploads
  - Frequency: As needed (when plates detected)

### Internet → POD (Inbound)

**Option A: Direct Access (Simple but requires port forwarding)**

- **Port 8000** open for streaming
- Users connect directly: `https://pod-public-ip:8000/stream?token=xxx`
- Pros: Low latency, simple
- Cons: Requires public IP and port forwarding

**Option B: VPN/Tailscale (Recommended for production)**

- POD joins VPN network (Tailscale)
- Portal also joins VPN network
- Portal proxies streams through VPN
- Users never directly access POD
- Pros: Secure, no port forwarding
- Cons: Adds VPN setup step

**Option C: No Inbound (Recordings Only)**

- Disable live streaming
- Only recordings uploaded to cloud
- Users view historical footage only
- Pros: No network config needed
- Cons: No live streams

## Configuration Files

### POD Side: `config.yaml`

```yaml
# Portal connection
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_xxxxxxxxx"

# Identification
pod_id: "main-gate-pod"
camera_id: "camera-uuid"
site_id: "site-uuid"
company_id: "company-uuid"

# Camera
camera_rtsp_url: "rtsp://192.168.1.100:554/stream"
min_confidence: 0.75

# Streaming
enable_streaming: true
stream_port: 8000
stream_secret: "shared-secret"
public_ip: "auto"

# Recording
record_on_detection: true
recordings_dir: "/tmp/recordings"

# MQTT
enable_mqtt: true
mqtt_host: "localhost"
mqtt_port: 1883

# Intervals
whitelist_refresh_interval: 300
heartbeat_interval: 60
```

### Portal Side: Environment Variables (Vercel)

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJxxx
SUPABASE_SERVICE_ROLE_KEY=eyJxxx

# Streaming (must match POD config)
POD_STREAM_SECRET=shared-secret

# Optional
GATEWISE_API_KEY=your-gatewise-key
```

## Complete Deployment Steps

### 1. Portal Setup

```bash
# Deploy to Vercel
vercel deploy

# Set environment variables
vercel env add NEXT_PUBLIC_SUPABASE_URL
vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY
vercel env add SUPABASE_SERVICE_ROLE_KEY
vercel env add POD_STREAM_SECRET

# Create Supabase storage bucket
# Go to Supabase Dashboard → Storage
# Create bucket: "camera-recordings" (Private)
```

### 2. Portal Configuration

```bash
# Login to portal
open https://your-portal.vercel.app

# Create structure:
1. Companies → Add Company
2. Communities → Add Community
3. Sites → Add Site
4. Cameras → Add Camera
5. Pods → Generate API Key
```

### 3. POD Installation

```bash
# SSH to POD
ssh pi@pod-ip

# Install agent
curl -o install.sh https://your-portal.vercel.app/install-pod.sh
chmod +x install.sh
sudo ./install.sh

# Or manually:
cd /opt
sudo git clone https://github.com/your-repo/platebridge-pod
cd platebridge-pod
sudo pip3 install -r requirements.txt
sudo cp config.example.yaml config.yaml
sudo nano config.yaml  # Edit with your values

# Start agent
sudo python3 complete_pod_agent.py config.yaml

# Create service
sudo cp platebridge-pod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable platebridge-pod
sudo systemctl start platebridge-pod
```

### 4. Verification

```bash
# Check POD logs
sudo journalctl -u platebridge-pod -f

# Check portal
# Pods page → Should show "Online"
# Cameras page → Should show "Active"
# Click "View Live Stream" → Should see video

# Test detection
curl -X POST https://your-portal.vercel.app/api/pod/detect \
  -H "Authorization: Bearer pbk_xxx" \
  -H "Content-Type: application/json" \
  -d '{"site_id":"xxx","plate":"TEST123","camera":"camera-1","pod_name":"main-gate-pod"}'

# Check audit logs
# Portal → Audit page → Should see detection
```

## Troubleshooting

### POD Shows Offline

```bash
# Check service
sudo systemctl status platebridge-pod

# Check logs
sudo journalctl -u platebridge-pod -n 50

# Check network
ping your-portal.vercel.app

# Test API
curl https://your-portal.vercel.app/api/health
```

### Stream Not Working

```bash
# Check FFmpeg
ps aux | grep ffmpeg

# Check stream files
ls -la /tmp/hls_output/

# Check stream server
curl http://localhost:8000/health

# Test RTSP
ffplay rtsp://camera-ip:554/stream
```

### Recordings Not Uploading

```bash
# Check recordings directory
ls -la /tmp/recordings/

# Test upload API
curl -X POST https://your-portal.vercel.app/api/pod/recordings/upload-url \
  -H "Authorization: Bearer pbk_xxx" \
  -H "Content-Type: application/json" \
  -d '{"camera_id":"xxx","filename":"test.mp4"}'

# Check Supabase Storage
# Login to Supabase → Storage → camera-recordings
```

## Security Checklist

- [ ] POD API keys generated and secured
- [ ] Stream secret configured (matches portal)
- [ ] Tokens expire (10 min for streams, 1 hour for uploads)
- [ ] RLS policies enabled on all tables
- [ ] Supabase storage bucket is private
- [ ] POD firewall configured
- [ ] HTTPS only (no HTTP)
- [ ] POD config.yaml not in git
- [ ] Regular key rotation schedule

## Performance Tips

**Low Bandwidth:**
```yaml
# Reduce stream quality
# Edit FFmpeg command in complete_pod_agent.py:
ffmpeg -i rtsp://... -c:v libx264 -preset ultrafast -b:v 500k ...
```

**Multiple Cameras:**
```bash
# Run multiple instances
python3 complete_pod_agent.py config_camera1.yaml &
python3 complete_pod_agent.py config_camera2.yaml &
```

**Reduce Storage:**
```yaml
# Shorter recordings
recording_duration: 15

# Lower refresh rate
whitelist_refresh_interval: 600
heartbeat_interval: 120
```

That's it! Your PODs are now connected and serving camera feeds securely to your portal.
