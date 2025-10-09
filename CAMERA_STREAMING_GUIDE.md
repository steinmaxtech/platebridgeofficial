# Camera Streaming & Recording Security Guide

## Overview

PlateBridge uses a secure hybrid approach for camera feeds:
- **Live Streams**: Time-limited signed tokens with direct POD access
- **Recordings**: Supabase Storage with RLS policies

## Architecture

```
┌─────────────┐      Signed Token      ┌──────────┐
│   Portal    │ ◄──────────────────────► │   POD    │
│   (Web UI)  │   (10 min expiry)       │  Stream  │
└─────────────┘                         │  Server  │
      ▲                                 └──────────┘
      │                                       │
      │   Upload Recordings                  │
      │   (Signed URLs)                      │
      ▼                                       ▼
┌─────────────────────────────────────────────────┐
│         Supabase Storage + Database             │
│  - camera_recordings table                      │
│  - camera-recordings bucket                     │
│  - RLS policies for access control              │
└─────────────────────────────────────────────────┘
```

## Security Implementation

### 1. Live Stream Security (Signed Tokens)

#### How It Works

1. User clicks "View Live Stream" in portal
2. Portal generates signed token valid for 10 minutes
3. Token includes: user_id, camera_id, pod_id, expiration
4. POD validates token signature before serving stream
5. Stream only accessible with valid token

#### Token Format

```
base64(payload) + "." + sha256(payload + secret)
```

Example:
```json
{
  "user_id": "uuid",
  "camera_id": "uuid",
  "pod_id": "uuid",
  "exp": 1696800000
}
```

#### POD Stream Server Setup

**Requirements:**
- FFmpeg installed
- Python 3.8+
- Flask, PyJWT

**Installation:**
```bash
cd pod-agent
pip install flask pyjwt requests

# Set environment variables
export POD_STREAM_SECRET="your-shared-secret-here"
export CAMERA_RTSP_URL="rtsp://camera-ip:554/stream"

# Run stream server
python stream_server.py
```

The server will:
- Convert RTSP to HLS
- Validate tokens on each stream request
- Serve HLS playlist and segments
- Auto-restart FFmpeg if it crashes

**Endpoints:**
- `GET /stream?token=xxx` - HLS playlist (validates token)
- `GET /stream/segment/<filename>` - HLS segments
- `GET /health` - Health check
- `GET /restart` - Restart FFmpeg

#### Portal Configuration

Update camera's `stream_url` in database:
```sql
UPDATE cameras
SET stream_url = 'https://pod-ip:8000/stream'
WHERE id = 'camera-uuid';
```

Or set in POD heartbeat:
```python
# In pod heartbeat script
heartbeat_data = {
    'pod_id': 'your-pod-id',
    'stream_url': 'https://10.0.0.5:8000/stream',
    # ... other data
}
```

### 2. Recording Security (Supabase Storage)

#### How It Works

1. POD detects event (plate, motion, manual)
2. POD records video clip locally
3. POD requests signed upload URL from portal (POD API key auth)
4. Portal validates POD owns the camera
5. Portal generates signed upload URL (1 hour expiry)
6. POD uploads directly to Supabase Storage
7. POD confirms upload, portal creates database record
8. Users request recordings through portal
9. Portal validates user has access via RLS
10. Portal generates signed download URLs (1 hour expiry)

#### POD Recording Setup

**Installation:**
```bash
cd pod-agent
pip install requests

# Set environment variables
export PORTAL_URL="https://your-portal.vercel.app"
export POD_API_KEY="pbk_your_api_key_here"
export CAMERA_ID="camera-uuid"
export CAMERA_RTSP_URL="rtsp://camera-ip:554/stream"

# Run uploader
python recording_uploader.py
```

**Upload Workflow:**
```python
from recording_uploader import RecordingUploader

uploader = RecordingUploader(PORTAL_URL, POD_API_KEY)

# Upload a clip
uploader.upload_recording(
    local_file_path='/tmp/recording.mp4',
    camera_id='camera-uuid',
    event_type='plate_detection',  # or 'motion', 'manual'
    plate_number='ABC123',
    duration_seconds=30,
    metadata={'confidence': 0.95}
)
```

#### Supabase Storage Setup

**Create Storage Bucket:**

1. Go to Supabase Dashboard → Storage
2. Create new bucket: `camera-recordings`
3. Set bucket to **Private** (not public)
4. RLS policies handle access control

**RLS Policies (Already Applied):**

```sql
-- Users can only view recordings from their company's cameras
CREATE POLICY "users_view_company_recordings"
  ON camera_recordings FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM cameras c
      JOIN pods p ON p.id = c.pod_id
      JOIN sites s ON s.id = p.site_id
      JOIN communities com ON com.id = s.community_id
      JOIN memberships m ON m.company_id = com.company_id
      WHERE c.id = camera_recordings.camera_id
      AND m.user_id = auth.uid()
    )
  );
```

### 3. API Endpoints

#### Stream Token Generation
```
POST /api/pod/stream-token
Authorization: Bearer <user-session-token>
Content-Type: application/json

{
  "camera_id": "uuid"
}

Response:
{
  "success": true,
  "token": "eyJ1c2VyX2lk...",
  "stream_url": "https://pod-ip:8000/stream?token=...",
  "expires_at": 1696800000,
  "expires_in": 600
}
```

#### Request Upload URL
```
POST /api/pod/recordings/upload-url
Authorization: Bearer <pod-api-key>
Content-Type: application/json

{
  "camera_id": "uuid",
  "filename": "recording.mp4"
}

Response:
{
  "success": true,
  "signed_url": "https://supabase.co/storage/...",
  "file_path": "recordings/community-id/camera-id/timestamp_recording.mp4",
  "expires_in": 3600
}
```

#### Confirm Upload
```
POST /api/pod/recordings/confirm
Authorization: Bearer <pod-api-key>
Content-Type: application/json

{
  "camera_id": "uuid",
  "file_path": "recordings/...",
  "file_size_bytes": 12345678,
  "duration_seconds": 30,
  "event_type": "plate_detection",
  "plate_number": "ABC123"
}

Response:
{
  "success": true,
  "recording": {
    "id": "uuid",
    "camera_id": "uuid",
    "recorded_at": "2025-10-09T12:00:00Z",
    "duration_seconds": 30,
    "event_type": "plate_detection"
  }
}
```

#### Fetch Recordings
```
GET /api/pod/recordings?camera_id=uuid&limit=50
Authorization: Bearer <user-session-token>

Response:
{
  "success": true,
  "recordings": [
    {
      "id": "uuid",
      "camera_id": "uuid",
      "camera_name": "Main Gate Camera",
      "recorded_at": "2025-10-09T12:00:00Z",
      "duration_seconds": 30,
      "event_type": "plate_detection",
      "plate_number": "ABC123",
      "video_url": "https://supabase.co/storage/...",
      "thumbnail_url": "https://supabase.co/storage/...",
      "expires_in": 3600
    }
  ],
  "count": 1
}
```

## Security Best Practices

### For PODs

1. **Keep API Keys Secret**: Never log or expose POD API keys
2. **Validate All Tokens**: Always check expiration and signature
3. **Use HTTPS**: Never serve streams over plain HTTP
4. **Limit Stream Duration**: Tokens expire in 10 minutes
5. **Clean Up Recordings**: Delete local files after upload
6. **Network Security**: Use firewall rules to limit access

### For Portal

1. **Short Token Expiry**: 10 minutes for streams, 1 hour for uploads
2. **RLS Always On**: Never disable Row Level Security
3. **Verify Ownership**: Check user/POD owns camera before access
4. **Signed URLs Only**: Never expose direct storage URLs
5. **Rate Limiting**: Implement rate limits on API endpoints
6. **Audit Logs**: Log all camera access attempts

### For Users

1. **Session Management**: Tokens tied to user sessions
2. **Company Isolation**: Users only see their company's cameras
3. **Role-Based Access**: Admins can delete, viewers can only watch
4. **Token Refresh**: Get new token when stream expires

## Troubleshooting

### Stream Not Loading

1. Check POD stream server is running: `curl http://pod-ip:8000/health`
2. Verify token is valid (not expired)
3. Check FFmpeg is running on POD
4. Verify camera RTSP URL is correct
5. Check firewall allows connections

### Recording Upload Fails

1. Verify POD API key is valid and not revoked
2. Check POD owns the camera
3. Verify Supabase Storage bucket exists
4. Check signed URL hasn't expired
5. Verify file size isn't too large

### User Can't View Recordings

1. Check user has membership to camera's company
2. Verify RLS policies are enabled
3. Check recording exists in database
4. Verify file exists in Supabase Storage

## Production Deployment

### POD Setup

1. **Use systemd service:**
```ini
[Unit]
Description=POD Stream Server
After=network.target

[Service]
Type=simple
User=pod
WorkingDirectory=/opt/pod-agent
Environment="POD_STREAM_SECRET=production-secret"
Environment="CAMERA_RTSP_URL=rtsp://camera:554/stream"
ExecStart=/usr/bin/python3 stream_server.py
Restart=always

[Install]
WantedBy=multi-user.target
```

2. **Use proper WSGI server:**
```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:8000 stream_server:app
```

3. **Set up SSL/TLS:**
```bash
# Use Let's Encrypt or self-signed certs
gunicorn -w 4 -b 0.0.0.0:8443 \
  --certfile=/etc/ssl/cert.pem \
  --keyfile=/etc/ssl/key.pem \
  stream_server:app
```

### Portal Setup

1. **Set environment variables in Vercel:**
   - `POD_STREAM_SECRET` - Shared secret for token validation
   - `SUPABASE_SERVICE_ROLE_KEY` - For storage operations

2. **Create storage bucket:**
   - Name: `camera-recordings`
   - Privacy: Private
   - File size limit: 500MB per file

3. **Monitor usage:**
   - Check Supabase storage quotas
   - Monitor API rate limits
   - Review access logs

## Next Steps

1. ✅ Database schema created
2. ✅ API endpoints implemented
3. ✅ Portal UI updated
4. ✅ POD example scripts provided
5. ⏳ Deploy POD stream server
6. ⏳ Configure camera RTSP URLs
7. ⏳ Test end-to-end workflow
8. ⏳ Set up monitoring and alerts
