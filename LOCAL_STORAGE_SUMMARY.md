# Local Storage Implementation - Summary

## What Changed

Switched from **cloud upload** to **local storage** for recordings.

### Before (Cloud Storage)
- POD uploads videos to Supabase Storage
- Large bandwidth usage
- Monthly storage costs
- Privacy concerns

### After (Local Storage)
- POD stores videos locally
- Only metadata uploaded
- Zero bandwidth costs
- Full privacy control

## Architecture

```
POD Device:
├── /recordings/*.mp4         (video files stored here)
├── complete_pod_agent.py     (serves videos + metadata)
└── Flask endpoints:
    ├── GET /recording/{id}   (serve video with token)
    ├── GET /recordings/list  (list local files)
    └── GET /thumbnail/{id}   (thumbnails)

Portal:
├── Database: camera_recordings (metadata only)
└── APIs:
    ├── POST /api/pod/recordings     (POD registers recording)
    └── GET /api/pod/recordings      (Users get signed URLs)

User Browser:
└── Connects directly to POD for video playback
```

## Key Changes

### 1. Removed Files
- ❌ `upload-url/route.ts` (no upload URLs needed)
- ❌ `confirm/route.ts` (no upload confirmation)
- ❌ `recording_uploader.py` (no cloud upload)
- ❌ Migration for Supabase Storage bucket

### 2. Updated Files

**POD Agent (`complete_pod_agent.py`):**
- Changed: `upload_recording()` → `register_recording()`
- No file upload, just POST metadata to portal
- Added: `/recording/{id}` endpoint to serve videos
- Added: `/recordings/list` endpoint
- Added: Token validation for all recording endpoints

**Portal API (`/api/pod/recordings/route.ts`):**
- Added: `POST` handler for POD to register recordings
- Updated: `GET` handler generates POD URLs instead of Supabase URLs
- URLs format: `https://pod-ip:8000/recording/{id}?token=xxx`

**Database:**
- Table `camera_recordings` stores metadata only
- `file_path` is local POD path (e.g., `/recordings/file.mp4`)
- No files in Supabase Storage

### 3. New Files
- ✅ `LOCAL_RECORDING_GUIDE.md` - Complete guide
- ✅ `LOCAL_STORAGE_SUMMARY.md` - This file

## How It Works Now

### Recording Flow

1. **POD detects plate:**
   ```python
   clip_path = self.record_clip(duration=30)
   # Saves to /recordings/recording_20251009_120000.mp4
   ```

2. **POD registers with portal:**
   ```python
   await self.register_recording(clip_path, plate_number)
   # POST /api/pod/recordings
   # Sends: file_path, size, plate_number, etc.
   ```

3. **Portal stores metadata:**
   ```sql
   INSERT INTO camera_recordings (
     camera_id, file_path, plate_number, ...
   )
   ```

4. **User views recordings:**
   ```
   Browser → Portal: GET /api/pod/recordings?camera_id=xxx
   Portal → Browser: [
     {video_url: "https://pod:8000/recording/id?token=xxx"}
   ]
   Browser → POD: GET /recording/id?token=xxx
   POD: Validates token, streams video file
   ```

## Configuration

### POD config.yaml

```yaml
# Recording settings
record_on_detection: true
recordings_dir: "/var/lib/platebridge/recordings"  # Local storage
recording_duration: 30

# No upload settings needed!
```

### Portal Environment Variables

Same as before:
```bash
NEXT_PUBLIC_SUPABASE_URL=xxx
NEXT_PUBLIC_SUPABASE_ANON_KEY=xxx
SUPABASE_SERVICE_ROLE_KEY=xxx
POD_STREAM_SECRET=xxx  # Shared secret for tokens
```

No Supabase Storage configuration needed!

## Benefits

### 1. Cost Savings
- ❌ No cloud storage fees
- ❌ No upload bandwidth costs
- ✅ Only metadata traffic (KB not GB)

### 2. Privacy
- ✅ Videos never leave premises
- ✅ Meets data residency requirements
- ✅ Full control over footage

### 3. Performance
- ✅ Direct POD access (fast)
- ✅ LAN speeds on same network
- ✅ No cloud latency

### 4. Reliability
- ✅ Works offline
- ✅ No dependency on cloud availability
- ✅ Recordings saved even without internet

### 5. Simplicity
- ✅ No Supabase Storage setup
- ✅ Fewer moving parts
- ✅ Easier to troubleshoot

## Storage Management

### Automatic (Add to POD)

```python
# In config.yaml
max_recordings: 1000

# In agent, call periodically:
def cleanup_old_recordings(self):
    files = sorted(Path(recordings_dir).glob('*.mp4'),
                   key=lambda p: p.stat().st_mtime,
                   reverse=True)

    for old_file in files[max_recordings:]:
        old_file.unlink()
```

### Manual

```bash
# Delete recordings older than 30 days
find /recordings -name "*.mp4" -mtime +30 -delete

# Check disk usage
df -h /var/lib/platebridge/recordings
```

### External Storage

```bash
# Mount external drive
sudo mount /dev/sda1 /mnt/recordings

# Update config
recordings_dir: "/mnt/recordings"
```

## Network Requirements

### For Live Streaming
- Inbound: Port 8000 (or VPN access)
- Tokens expire in 10 minutes

### For Recordings
- Same port 8000
- Tokens expire in 1 hour
- Direct browser → POD connection

### Options
1. **Port Forward:** Simple but less secure
2. **VPN (Tailscale):** Recommended for production
3. **Reverse Proxy:** Most flexible

## Security

### Token-Based Access
- All recording access requires valid signed token
- Tokens include user_id, recording_id, expiration
- POD validates signature before serving

### Token Expiration
- Live streams: 10 minutes
- Recordings: 1 hour
- Portal generates new tokens as needed

### Network Isolation
- POD can be on private network
- VPN for external access
- No public exposure required

## Testing

### 1. Record Clip
```bash
# On POD, manually trigger:
python3 -c "
from complete_pod_agent import CompletePodAgent
agent = CompletePodAgent('config.yaml')
clip = agent.record_clip(10)
print(f'Recorded: {clip}')
"
```

### 2. Register with Portal
```bash
curl -X POST https://portal/api/pod/recordings \
  -H "Authorization: Bearer pbk_xxx" \
  -H "Content-Type: application/json" \
  -d '{
    "camera_id": "xxx",
    "file_path": "/recordings/test.mp4",
    "duration_seconds": 10,
    "event_type": "manual"
  }'
```

### 3. View in Portal
- Login to portal
- Go to Cameras → Select camera → View Recordings
- Should see recording with playback option

### 4. Direct Access
```bash
# Get token from portal API response, then:
curl -v "https://pod-ip:8000/recording/{id}?token=xxx"
```

## Migration Path

If you need to migrate existing cloud recordings to local:

1. **Download from Supabase Storage** (if you have old recordings)
2. **Copy to POD** local storage directory
3. **Update database** `file_path` to local paths
4. **Update POD config** to use local storage
5. **Restart POD agent**

## Troubleshooting

### Recordings Not Showing
1. Check POD logs: `sudo journalctl -u platebridge-pod -f`
2. Verify files exist: `ls /recordings/`
3. Test registration API
4. Check database has records

### Can't Play Video
1. Check POD is reachable: `curl https://pod:8000/health`
2. Verify token not expired (get fresh list)
3. Check file exists on POD
4. Verify firewall allows port 8000

### Disk Full
1. Check space: `df -h`
2. Delete old recordings: `find /recordings -mtime +7 -delete`
3. Add external drive for more space

## Summary

✅ **Recordings stored locally on POD**
✅ **Only metadata in database**
✅ **Direct browser → POD streaming**
✅ **Signed tokens for security**
✅ **Zero cloud costs**
✅ **Full privacy control**

Perfect for privacy-focused, cost-conscious, or offline-capable deployments!
