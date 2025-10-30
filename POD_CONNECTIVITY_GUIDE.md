# PlateBridge Pod Connectivity & Streaming Guide

## Overview

This guide explains how pods check in with the portal, how Tailscale provides secure connectivity, and how camera feeds stream to the portal.

---

## 1. Pod Check-In System

### Initial Registration

When you run the installer, the pod registers with the portal:

```bash
sudo ./install-complete.sh
```

**What happens:**

1. **User Input**:
   - Portal URL
   - Registration token (from portal)
   - Device friendly name (e.g., "North Gate POD")

2. **Pod Sends Registration Request**:
```json
POST /api/pods/register
{
  "serial": "ABC123456",
  "mac": "00:11:22:33:44:55",
  "model": "PB-M1",
  "version": "1.0.0",
  "registration_token": "token_abc123",
  "device_name": "North Gate POD"
}
```

3. **Portal Response**:
```json
{
  "pod_id": "uuid-pod-123",
  "api_key": "pbk_abc123xyz789...",
  "community_id": "uuid-community-456"
}
```

4. **Pod Saves Config Locally**:
```yaml
portal_url: "https://portal.com"
pod_api_key: "pbk_abc123xyz789..."
pod_id: "uuid-pod-123"
community_id: "uuid-community-456"
```

### Continuous Heartbeat (Every 60 Seconds)

Once registered, the pod continuously sends heartbeats:

```json
POST /api/pod/heartbeat
Authorization: Bearer pbk_abc123xyz789...

{
  "pod_id": "uuid-pod-123",
  "ip_address": "73.45.123.89",
  "tailscale_ip": "100.64.15.23",
  "tailscale_hostname": "north-gate-pod",
  "firmware_version": "1.0.0",
  "status": "online",
  "cameras": [
    {
      "camera_id": "cam_001",
      "name": "Main Entrance",
      "rtsp_url": "rtsp://192.168.1.100:554/stream",
      "position": "main entrance"
    }
  ],
  "cpu_usage": 45.2,
  "memory_usage": 62.1,
  "disk_usage": 38.5,
  "temperature": 52
}
```

### Portal Updates Database

On each heartbeat, portal updates:

```sql
UPDATE pods SET
  last_heartbeat = NOW(),
  status = 'online',
  ip_address = '73.45.123.89',
  tailscale_ip = '100.64.15.23',
  tailscale_hostname = 'north-gate-pod',
  firmware_version = '1.0.0',
  cpu_usage = 45.2,
  memory_usage = 62.1,
  disk_usage = 38.5,
  temperature = 52
WHERE id = 'uuid-pod-123';
```

### Offline Detection

Portal marks pods offline if no heartbeat received for 5 minutes:

```sql
SELECT * FROM pods
WHERE last_heartbeat < NOW() - INTERVAL '5 minutes'
  AND status = 'online'
-- These pods are marked as offline
```

---

## 2. Tailscale Secure Connectivity

### Why Tailscale?

- **Zero-trust networking**: Encrypted WireGuard VPN
- **No port forwarding**: Works through NAT/firewalls
- **Mesh network**: Direct pod-to-portal communication
- **100.x.x.x addresses**: Secure, private IP space

### How It Works

#### On the Pod:

1. **Tailscale Container Runs**:
```yaml
tailscale:
  image: tailscale/tailscale:latest
  network_mode: host
  privileged: true
  environment:
    - TS_AUTHKEY=${TS_AUTHKEY}
```

2. **Pod Agent Detects Tailscale**:
```python
# Get Tailscale IP
result = subprocess.run(['tailscale', 'ip', '-4'], capture_output=True)
tailscale_ip = result.stdout.strip()  # "100.64.15.23"

# Get Tailscale hostname
result = subprocess.run(['tailscale', 'status', '--json'], capture_output=True)
status = json.loads(result.stdout)
tailscale_hostname = status['Self']['HostName']  # "north-gate-pod"
```

3. **Sent in Heartbeat**:
```json
{
  "tailscale_ip": "100.64.15.23",
  "tailscale_hostname": "north-gate-pod"
}
```

#### On the Portal:

1. **Portal Receives Tailscale Info**:
```typescript
const { tailscale_ip, tailscale_hostname } = heartbeat;

await db.pods.update({
  tailscale_ip: "100.64.15.23",
  tailscale_hostname: "north-gate-pod"
});
```

2. **Portal Uses Tailscale IP for Connections**:
```typescript
// Prefer Tailscale IP over public IP
const connectIp = pod.tailscale_ip || pod.ip_address;
const streamUrl = `https://${connectIp}:8000/stream`;
```

### Benefits

| Without Tailscale | With Tailscale |
|------------------|----------------|
| Public IP + Port forwarding | Private 100.x.x.x IP |
| Exposed to internet | Zero-trust network |
| NAT/firewall issues | Works through NAT |
| Insecure connections | Encrypted WireGuard |

---

## 3. Camera Feed Streaming

### Architecture

```
Camera Network (192.168.1.x)
    ↓ RTSP
Pod (acts as gateway)
    ↓ HLS/WebRTC
Portal (via Tailscale 100.x.x.x)
    ↓ HTTPS
Browser
```

### How Streams Work

#### Step 1: Camera Connects to Pod

Cameras on isolated LAN (192.168.1.x):
```
rtsp://192.168.1.100:554/stream  ← Camera
         ↓
    Pod (192.168.1.1)
```

#### Step 2: Pod Converts to HLS

Pod agent transcodes RTSP to HLS:

```python
ffmpeg_cmd = [
    'ffmpeg',
    '-i', 'rtsp://192.168.1.100:554/stream',  # Input: camera RTSP
    '-f', 'hls',                                # Output: HLS format
    '-hls_time', '2',                           # 2-second segments
    '-hls_list_size', '3',                      # Keep 3 segments
    '-hls_flags', 'delete_segments',            # Auto-delete old
    '/tmp/hls_output/stream.m3u8'               # Output playlist
]
```

**Output Files**:
```
/tmp/hls_output/
├── stream.m3u8       ← Playlist (pointers to segments)
├── stream0.ts        ← Video segment 1
├── stream1.ts        ← Video segment 2
└── stream2.ts        ← Video segment 3 (rolling window)
```

#### Step 3: Portal Requests Stream

Portal uses Tailscale IP to connect:

```typescript
// Portal generates stream token
const token = jwt.sign({ pod_id, camera_id }, secret);

// Portal requests stream via Tailscale
const streamUrl = `https://${pod.tailscale_ip}:8000/stream?token=${token}`;

// Browser fetches HLS playlist
fetch(streamUrl)
  → Returns stream.m3u8
```

#### Step 4: Browser Plays Stream

```html
<video id="stream">
  <source src="https://100.64.15.23:8000/stream?token=abc123" type="application/vnd.apple.mpegurl">
</video>

<script>
  const video = document.getElementById('stream');
  const hls = new Hls();
  hls.loadSource('https://100.64.15.23:8000/stream?token=abc123');
  hls.attachMedia(video);
  video.play();
</script>
```

### Stream Endpoints

Pod exposes these endpoints:

```python
# Main stream playlist
GET /stream?token=abc123
→ Returns stream.m3u8

# Video segments
GET /stream/segment/stream0.ts
→ Returns video segment

# Recordings list
GET /recordings/list?token=abc123
→ Returns list of saved recordings

# Download recording
GET /recording/{recording_id}?token=abc123
→ Returns MP4 video file

# Thumbnail
GET /thumbnail/{recording_id}?token=abc123
→ Returns JPEG thumbnail
```

### Security

1. **Token-based authentication**:
```python
def validate_stream_token(token):
    payload = jwt.decode(token, secret)
    return payload['pod_id'] == self.pod_id
```

2. **Tailscale encryption**:
   - All traffic encrypted with WireGuard
   - No exposure to public internet

3. **Camera network isolation**:
   - Cameras on isolated 192.168.1.x network
   - Cannot be accessed from internet
   - Pod acts as secure gateway

---

## 4. How Portal Connects to Pods

### Connection Priority

Portal tries connections in this order:

1. **Tailscale IP** (preferred)
   - `https://100.64.15.23:8000`
   - Encrypted, direct mesh connection
   - Works through NAT/firewalls

2. **Public IP** (fallback)
   - `https://73.45.123.89:8000`
   - Requires port forwarding
   - Less secure

3. **Hostname** (last resort)
   - `https://pod-uuid-123.local:8000`
   - Only works on same network

### Example Connection Flow

```typescript
// Portal fetches pod info from database
const pod = await db.pods.findById(pod_id);

// Determine best connection method
const connectIp = pod.tailscale_ip || pod.ip_address || `pod-${pod.id}.local`;

// Generate authentication token
const token = jwt.sign({
  pod_id: pod.id,
  camera_id: 'cam_001',
  expires: Date.now() + 3600000  // 1 hour
}, process.env.JWT_SECRET);

// Connect to pod
const streamUrl = `https://${connectIp}:8000/stream?token=${token}`;

// Proxy stream to browser
const response = await fetch(streamUrl);
return response.body.pipe(res);
```

### Portal API Endpoints

```typescript
// Get stream token
POST /api/pod/stream-token
{
  "pod_id": "uuid-123",
  "camera_id": "cam_001"
}
→ Returns { token: "jwt_abc123" }

// Proxy stream (uses Tailscale internally)
GET /api/pod/proxy-stream/[pod_id]?camera_id=cam_001
→ Proxies HLS stream from pod

// Get recordings
GET /api/pod/recordings?pod_id=uuid-123
→ Returns list of recordings
```

---

## 5. Complete Example Flow

### Scenario: User views camera feed in portal

1. **User clicks "View Stream" in portal**

2. **Portal fetches pod info**:
```sql
SELECT id, tailscale_ip, ip_address FROM pods WHERE id = 'uuid-123';
```

3. **Portal generates token**:
```typescript
const token = jwt.sign({ pod_id, camera_id }, secret);
```

4. **Portal connects via Tailscale**:
```typescript
const streamUrl = `https://${pod.tailscale_ip}:8000/stream?token=${token}`;
```

5. **Pod validates token**:
```python
if validate_stream_token(token):
    return send_file('/tmp/hls_output/stream.m3u8')
```

6. **Browser plays HLS stream**:
```javascript
const hls = new Hls();
hls.loadSource(streamUrl);
hls.attachMedia(videoElement);
```

7. **Video plays in real-time!**

---

## 6. Troubleshooting

### Pod Not Checking In

**Check pod agent logs**:
```bash
docker logs -f platebridge-pod
```

**Verify API key**:
```bash
cat /opt/platebridge/config.yaml | grep pod_api_key
```

**Test heartbeat manually**:
```bash
curl -X POST https://portal.com/api/pod/heartbeat \
  -H "Authorization: Bearer pbk_abc123" \
  -H "Content-Type: application/json" \
  -d '{"pod_id":"uuid-123","status":"online"}'
```

### Tailscale Not Connecting

**Check Tailscale status**:
```bash
docker exec platebridge-tailscale tailscale status
```

**Get Tailscale IP**:
```bash
docker exec platebridge-tailscale tailscale ip -4
```

**Reconnect Tailscale**:
```bash
docker exec platebridge-tailscale tailscale up
```

### Stream Not Loading

**Check if pod is reachable**:
```bash
# From portal server
ping 100.64.15.23  # Tailscale IP
curl https://100.64.15.23:8000/health
```

**Check HLS files exist**:
```bash
docker exec platebridge-pod ls -la /tmp/hls_output/
```

**Verify stream server is running**:
```bash
docker exec platebridge-pod ps aux | grep python
```

---

## Summary

✅ **Pods check in every 60 seconds** with heartbeat containing system stats and Tailscale info

✅ **Tailscale provides secure mesh networking** using encrypted WireGuard tunnels

✅ **Camera feeds stream via HLS** from pod to portal using Tailscale IPs

✅ **Portal uses Tailscale IPs** as preferred connection method for all pod communications

✅ **Everything is encrypted and secure** with zero-trust networking
