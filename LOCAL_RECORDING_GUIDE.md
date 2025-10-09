# Local Recording Guide - No Cloud Storage

## Overview

PlateBridge PODs store recordings **locally** - no cloud uploads required!

**Architecture:**
- ✅ Recordings saved on POD device
- ✅ Portal tracks metadata only
- ✅ Users stream directly from POD
- ✅ Zero cloud storage costs
- ✅ Full privacy and control

## How It Works

```
┌─────────┐              ┌─────────────────────────┐
│ Browser │──(request)──→│   Portal (Metadata)     │
└─────────┘              └─────────────────────────┘
     │                              ↓
     │                    (generates signed token)
     │                              ↓
     │                   ┌─────────────────────────┐
     └───(direct)───────→│    POD (Video Files)    │
                         │  /recordings/*.mp4      │
                         └─────────────────────────┘
```

### Recording Flow

**1. Detection:**
```
Plate detected → POD records 30s clip → Saves to /recordings/
```

**2. Registration:**
```
POD → Portal: "I have a new recording at /recordings/file.mp4"
Portal: Stores metadata in database (no file upload)
```

**3. Viewing:**
```
User → Portal: "Show me recordings"
Portal: Generates signed token
User → POD: "Give me video (with token)"
POD: Validates token, streams video
```

## POD Configuration

### Update config.yaml

```yaml
# Recording settings
record_on_detection: true
recordings_dir: "/var/lib/platebridge/recordings"
recording_duration: 30
```

### Directory Setup

```bash
# Create persistent storage
sudo mkdir -p /var/lib/platebridge/recordings
sudo chown $USER:$USER /var/lib/platebridge/recordings

# For external drive (optional)
sudo mount /dev/sda1 /mnt/recordings
recordings_dir: "/mnt/recordings"
```

## POD Endpoints

POD serves recordings directly:

- `GET /recording/{id}?token=xxx` - Stream/download recording
- `GET /recordings/list?token=xxx` - List local files
- `GET /thumbnail/{id}?token=xxx` - Get thumbnail
- `GET /health` - Status + recording count

## Portal Workflow

### 1. POD Registers Recording

```python
# POD sends metadata to portal
response = requests.post(
    f"{portal_url}/api/pod/recordings",
    headers={'Authorization': f'Bearer {pod_api_key}'},
    json={
        'camera_id': camera_id,
        'file_path': '/recordings/recording_20251009_120000.mp4',
        'file_size_bytes': 12345678,
        'duration_seconds': 30,
        'event_type': 'plate_detection',
        'plate_number': 'ABC123'
    }
)
```

Portal stores metadata in `camera_recordings` table.

### 2. User Requests Recordings

```
GET /api/pod/recordings?camera_id=xxx
Authorization: Bearer <session-token>
```

Portal response:
```json
{
  "recordings": [
    {
      "id": "recording-uuid",
      "video_url": "https://pod-ip:8000/recording/uuid?token=xxx",
      "recorded_at": "2025-10-09T12:00:00Z",
      "plate_number": "ABC123",
      "expires_in": 3600
    }
  ]
}
```

### 3. Browser Plays Video

Browser uses `video_url` directly - streams from POD, not portal.

## Storage Management

### Auto-Cleanup (Add to POD agent)

```python
def cleanup_old_recordings(self):
    max_recordings = self.config.get('max_recordings', 1000)
    recordings_dir = self.config.get('recordings_dir')

    files = sorted(
        Path(recordings_dir).glob('*.mp4'),
        key=lambda p: p.stat().st_mtime,
        reverse=True
    )

    # Keep only the newest max_recordings files
    for old_file in files[max_recordings:]:
        old_file.unlink()
        logger.info(f"Deleted old recording: {old_file.name}")
```

Call in heartbeat loop:
```python
if current_time - last_cleanup >= 3600:  # Every hour
    self.cleanup_old_recordings()
    last_cleanup = current_time
```

### Manual Cleanup

```bash
# SSH to POD
ssh pi@pod-ip

# Delete recordings older than 30 days
find /var/lib/platebridge/recordings -name "*.mp4" -mtime +30 -delete

# Keep only last 500 recordings
cd /var/lib/platebridge/recordings
ls -t *.mp4 | tail -n +501 | xargs rm -f

# Check disk usage
df -h /var/lib/platebridge/recordings
```

### External Drive (For More Space)

```bash
# Format external drive
sudo mkfs.ext4 /dev/sda1

# Create mount point
sudo mkdir -p /mnt/recordings

# Mount
sudo mount /dev/sda1 /mnt/recordings
sudo chown pi:pi /mnt/recordings

# Auto-mount on boot
echo "/dev/sda1 /mnt/recordings ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Update config.yaml
recordings_dir: "/mnt/recordings"

# Restart POD agent
sudo systemctl restart platebridge-pod
```

## Security

### Token Validation

PODs validate signed tokens before serving videos:

```python
def validate_stream_token(token):
    payload_b64, signature = token.split('.')
    payload = json.loads(base64.b64decode(payload_b64))

    # Check signature
    expected = sha256(payload + secret)
    if signature != expected:
        return False

    # Check expiration (1 hour)
    if payload['exp'] < time.time():
        return False

    return True
```

### Network Security

**Option A: Local Network Only**
```bash
# Firewall: Allow only local network
sudo ufw allow from 192.168.1.0/24 to any port 8000
```

**Option B: VPN Access**
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# POD accessible via Tailscale IP only
# Update portal with Tailscale IP in heartbeat
```

## Advantages

### 1. Zero Cloud Costs
- No upload bandwidth used
- No cloud storage fees
- Only metadata synced

### 2. Privacy & Compliance
- Video never leaves premises
- Meets data residency requirements
- Full control over footage

### 3. Fast Access
- Direct POD connection
- LAN speeds if on same network
- No cloud latency

### 4. Unlimited Storage
- Limited only by disk size
- Add external drives as needed
- No per-GB pricing

### 5. Works Offline
- Recordings saved even without internet
- Metadata syncs when back online
- Critical for security systems

## Troubleshooting

### Recordings Not Listed

**Check POD logs:**
```bash
sudo journalctl -u platebridge-pod -f | grep -i record
```

**Verify files exist:**
```bash
ls -lh /var/lib/platebridge/recordings/
```

**Test registration:**
```bash
curl -X POST https://portal/api/pod/recordings \
  -H "Authorization: Bearer pbk_xxx" \
  -H "Content-Type: application/json" \
  -d '{"camera_id":"xxx","file_path":"/recordings/test.mp4","duration_seconds":30}'
```

### Can't Play Video

**Check POD is reachable:**
```bash
curl https://pod-ip:8000/health
```

**Check token not expired:**
- Tokens valid for 1 hour
- Refresh recording list to get new tokens

**Check file exists on POD:**
```bash
ssh pi@pod-ip
ls -la /var/lib/platebridge/recordings/
```

### Disk Full

**Check space:**
```bash
df -h /var/lib/platebridge/recordings
```

**Free space:**
```bash
# Delete old recordings
find /var/lib/platebridge/recordings -mtime +7 -delete

# Or add external drive (see above)
```

## Complete Example

### POD Side (complete_pod_agent.py)

Already implemented! The agent:
1. Records clips when plates detected
2. Registers metadata with portal
3. Serves videos via `/recording/{id}` endpoint
4. Validates tokens before serving

### Portal Side

Database stores only metadata:
```sql
camera_recordings:
  - id (uuid)
  - camera_id (uuid)
  - file_path (text) -- Path on POD
  - recorded_at (timestamp)
  - plate_number (text)
  - duration_seconds (int)
  - file_size_bytes (bigint)
```

No video files in Supabase Storage!

### User Experience

1. User opens portal → Cameras → View Recordings
2. Portal fetches metadata from database
3. Portal generates signed tokens
4. Browser connects directly to POD
5. Video plays from POD storage

**No cloud involved in video delivery!**

## Migration from Cloud Storage

If you were using cloud storage before:

1. **Disable uploads** in POD config:
   ```yaml
   # Remove these (if present):
   # upload_to_cloud: false
   ```

2. **Keep recordings local:**
   ```yaml
   record_on_detection: true
   recordings_dir: "/var/lib/platebridge/recordings"
   ```

3. **Update pod agent:** Use `complete_pod_agent.py` which registers (not uploads)

4. **Old recordings:** Keep in Supabase or migrate to POD

## Summary

✅ **Videos stored locally on POD**
✅ **Only metadata in database**
✅ **Direct browser → POD streaming**
✅ **Signed tokens for security**
✅ **Zero cloud storage costs**

Perfect for:
- Privacy-sensitive installations
- Limited bandwidth locations
- Cost optimization
- Offline capability
- Data residency compliance
