# How PODs Connect and Serve Camera Feeds - Simple Version

## The Big Picture

Your POD is a device at your gate running `complete_pod_agent.py`. It does 4 things:

1. **Listens** for plate detections (from Frigate)
2. **Streams** live video (via HLS)
3. **Records** clips when plates are detected
4. **Uploads** clips to cloud storage

## Simple Setup (3 Steps)

### Step 1: Portal Setup
```
1. Login to portal
2. Create: Company → Community → Site → Camera
3. Generate POD API key
4. Copy: Camera ID, Site ID, Company ID, API Key
```

### Step 2: POD Installation
```bash
# On your POD device:
ssh pi@pod-ip

# Download agent
curl -O https://github.com/yourrepo/platebridge/pod-agent/complete_pod_agent.py
curl -O https://github.com/yourrepo/platebridge/pod-agent/config.example.yaml
curl -O https://github.com/yourrepo/platebridge/pod-agent/requirements.txt

# Install
sudo pip3 install -r requirements.txt

# Configure
cp config.example.yaml config.yaml
nano config.yaml
```

### Step 3: Edit config.yaml
```yaml
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_your_key_here"
camera_id: "your-camera-uuid"
camera_rtsp_url: "rtsp://192.168.1.100:554/stream"
stream_secret: "same-as-portal-env-var"
```

Start it:
```bash
sudo python3 complete_pod_agent.py config.yaml
```

Done! Check portal → Cameras → Should show "Active"

## How Streaming Works

**User clicks "View Live Stream":**

1. Portal creates a signed token (expires in 10 min)
2. Token includes: user_id, camera_id, expiration
3. User's browser gets: `https://pod-ip:8000/stream?token=xxx`
4. POD validates token and serves HLS video
5. Browser plays video

**Security:** Token expires in 10 minutes. POD validates signature before serving.

## How Recording Works

**POD detects a plate:**

1. POD records 30-second clip
2. POD asks portal for upload URL
3. Portal creates signed URL (expires in 1 hour)
4. POD uploads directly to Supabase Storage
5. POD confirms upload, portal creates database record
6. POD deletes local file

**User views recordings:**

1. Portal checks user has access (RLS)
2. Portal generates signed download URLs
3. User's browser plays video from cloud

## Network Setup

### Option A: Open Port (Simple)
```
Open port 8000 on your router
Point it to POD IP
Users connect directly to POD for streams
```

### Option B: VPN (Recommended)
```
Install Tailscale on POD
Portal uses VPN IP for streams
No port forwarding needed
More secure
```

### Option C: No Streaming (Recordings Only)
```yaml
# In config.yaml:
enable_streaming: false
```
Users can only view recorded clips, no live streams.

## Files on POD

```
/opt/platebridge-pod/
├── complete_pod_agent.py    # Main agent (all-in-one)
├── config.yaml              # Your configuration
├── requirements.txt         # Python dependencies
└── whitelist_cache.json     # Cached plates (auto-created)

/tmp/
├── hls_output/             # HLS stream files
│   ├── stream.m3u8
│   └── segment_*.ts
└── recordings/             # Temporary recordings
    └── recording_*.mp4
```

## What POD Does Automatically

**Every 60 seconds:**
- Sends heartbeat to portal
- Updates stream URL
- Portal shows camera as "Active"

**Every 5 minutes:**
- Downloads whitelist from portal
- Caches locally
- Works offline if portal is down

**On plate detection:**
- Checks local whitelist cache
- Sends detection to portal
- Portal logs to audit
- Portal opens gate if allowed
- Records 30-second clip
- Uploads to cloud
- Deletes local file

## Monitoring

**Check if POD is running:**
```bash
sudo systemctl status platebridge-pod
```

**View logs:**
```bash
sudo journalctl -u platebridge-pod -f
```

**Check stream:**
```bash
curl http://localhost:8000/health
```

**Test from portal:**
- Pods page → Should show "Online"
- Cameras page → Should show "Active"
- Click "View Live Stream" → Should see video
- Click "View Recordings" → Should see clips

## Quick Fixes

**POD offline?**
```bash
sudo systemctl restart platebridge-pod
```

**Stream not working?**
```bash
# Check FFmpeg is running:
ps aux | grep ffmpeg

# Restart stream:
sudo systemctl restart platebridge-pod
```

**Recordings not uploading?**
```bash
# Check storage bucket exists:
# Login to Supabase → Storage → camera-recordings

# Check API key:
cat config.yaml | grep pod_api_key
```

## Environment Variables (Portal)

Set in Vercel:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJxxx
SUPABASE_SERVICE_ROLE_KEY=eyJxxx
POD_STREAM_SECRET=same-as-pod-config
```

## That's It!

Your POD is now:
- ✅ Detecting plates
- ✅ Streaming live video
- ✅ Recording clips
- ✅ Uploading to cloud
- ✅ Opening gates automatically

**To add more PODs:** Repeat steps 2-3 with different `pod_id` values.

**To add more cameras:** Create new camera in portal, run new agent instance with different `camera_id`.
