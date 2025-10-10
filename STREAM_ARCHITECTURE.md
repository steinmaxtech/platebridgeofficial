# Stream Architecture - How Portal Finds POD Cameras

This document explains how the portal discovers and connects to cameras on PODs.

## Architecture Overview

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Browser   │────────▶│    Portal    │────────▶│     POD     │
│  (Client)   │         │   (Vercel)   │         │  (Local)    │
└─────────────┘         └──────────────┘         └─────────────┘
                              │                         │
                              │                   ┌─────▼──────┐
                              │                   │  Camera(s) │
                              ▼                   └────────────┘
                        ┌──────────┐
                        │ Supabase │
                        │ Database │
                        └──────────┘
```

## Discovery Flow

### 1. POD Startup & Registration

When the POD agent starts:

```python
# POD sends heartbeat every 60 seconds
POST /api/pod/heartbeat
Authorization: Bearer pbk_xxx

{
  "pod_id": "main-gate-pod",
  "ip_address": "192.168.1.100",  # POD's local IP
  "firmware_version": "1.0.0",
  "status": "online",
  "cameras": [
    {
      "camera_id": "gate-camera-1",
      "name": "Main Gate Camera",
      "rtsp_url": "rtsp://192.168.1.50:554/stream",
      "position": "main entrance"
    }
  ]
}
```

### 2. Portal Registration

The portal receives heartbeat and:

```typescript
// 1. Register/update POD
INSERT INTO pods (id, site_id, name, ip_address, status)
VALUES ('main-gate-pod', 'site-uuid', 'Main Gate POD', '192.168.1.100', 'online')

// 2. Register/update each camera
INSERT INTO cameras (id, pod_id, name, stream_url, status)
VALUES (
  'gate-camera-1',
  'main-gate-pod',
  'Main Gate Camera',
  'https://192.168.1.100:8000/stream',  # Auto-generated
  'active'
)
```

### 3. Portal Queries Cameras

When user visits the Cameras page:

```typescript
GET /cameras

// Portal queries database
SELECT
  cameras.id,
  cameras.name,
  cameras.stream_url,
  cameras.status,
  pods.id as pod_id,
  pods.name as pod_name,
  pods.ip_address
FROM cameras
INNER JOIN pods ON cameras.pod_id = pods.id
WHERE pods.sites.communities.company_id = user.company_id
```

**Result:**
```json
{
  "cameras": [
    {
      "id": "gate-camera-1",
      "name": "Main Gate Camera",
      "stream_url": "https://192.168.1.100:8000/stream",
      "status": "active",
      "pod_id": "main-gate-pod",
      "pod_name": "Main Gate POD",
      "pod_ip": "192.168.1.100"
    }
  ]
}
```

## Connection Methods

### Method 1: Direct Connection (Simple, Limited)

**Use when:** POD has public IP or port forwarding configured

```
Browser ──────▶ POD directly
             https://public-ip:8000/stream
```

**Setup:**
1. POD must have public IP or port forwarding (port 8000 → POD)
2. POD sends public IP in heartbeat
3. Browser connects directly

**Limitations:**
- Requires network configuration
- May expose POD to internet
- SSL certificate challenges
- Firewall/NAT issues

### Method 2: Portal Proxy (Recommended)

**Use when:** POD is on private network, portal can reach it

```
Browser ──────▶ Portal ──────▶ POD
          (public)      (internal)
```

**Setup:**
1. Browser requests: `GET /api/pod/proxy-stream/main-gate-pod?camera_id=gate-camera-1`
2. Portal authenticates user
3. Portal looks up POD's internal IP: `192.168.1.100`
4. Portal fetches stream from POD: `http://192.168.1.100:8000/stream`
5. Portal proxies stream to browser

**Advantages:**
- No public POD exposure
- Portal handles authentication
- Works with private IPs
- Centralized access control

**Implementation:**
```typescript
// Browser request
const response = await fetch(
  `/api/pod/proxy-stream/${podId}?camera_id=${cameraId}`,
  {
    headers: {
      'Authorization': `Bearer ${userToken}`
    }
  }
);

// Portal proxies to POD
const podStream = await fetch(
  `http://${pod.ip_address}:8000/stream?token=${podToken}`
);
return new Response(podStream.body);
```

### Method 3: Tailscale/VPN (Advanced)

**Use when:** PODs are distributed across networks

```
Browser ──▶ Portal ──▶ Tailscale Network ──▶ POD
                            100.x.x.x
```

**Setup:**
1. Install Tailscale on POD and portal
2. POD sends Tailscale IP in heartbeat: `100.64.1.5`
3. Portal connects via Tailscale network

**Advantages:**
- Secure mesh network
- Multi-location support
- Encrypted traffic
- No port forwarding needed

## Token-Based Security

All stream access uses signed tokens:

### Portal Generates Token

```typescript
const tokenPayload = {
  user_id: "user-uuid",
  pod_id: "main-gate-pod",
  camera_id: "gate-camera-1",
  exp: Math.floor(Date.now() / 1000) + 3600  // 1 hour
};

const secret = pod.stream_token_secret || process.env.POD_STREAM_SECRET;
const token = sign(tokenPayload, secret);  // SHA-256 signature
```

### POD Validates Token

```python
def verify_token(token, secret):
    parts = token.split('.')
    payload_b64 = parts[0]
    signature = parts[1]

    # Verify signature
    expected_sig = hmac.sha256(payload_b64 + secret)
    if signature != expected_sig:
        return None

    # Decode payload
    payload = json.loads(base64.decode(payload_b64))

    # Check expiration
    if payload['exp'] < time.now():
        return None

    return payload
```

## Database Schema

### pods table
```sql
CREATE TABLE pods (
  id uuid PRIMARY KEY,
  site_id uuid REFERENCES sites(id),
  name text NOT NULL,
  ip_address text,              -- POD's IP (internal or public)
  last_heartbeat timestamptz,
  status text,                   -- 'online', 'offline', 'error'
  stream_token_secret text       -- Shared secret for stream auth
);
```

### cameras table
```sql
CREATE TABLE cameras (
  id uuid PRIMARY KEY,
  pod_id uuid REFERENCES pods(id),
  name text NOT NULL,
  stream_url text NOT NULL,      -- Generated from POD IP
  status text,                   -- 'active', 'inactive', 'error'
  position text                  -- Optional: camera location
);
```

## Heartbeat Process

Every 60 seconds, POD sends heartbeat:

```python
def send_heartbeat():
    # Get local IP
    ip_address = get_local_ip()  # e.g., 192.168.1.100

    # Build camera list
    cameras = [
        {
            'camera_id': config['camera_id'],
            'name': config['camera_name'],
            'rtsp_url': config['camera_rtsp_url'],
            'position': config.get('camera_position', '')
        }
    ]

    # Send to portal
    response = requests.post(
        f"{portal_url}/api/pod/heartbeat",
        headers={'Authorization': f'Bearer {api_key}'},
        json={
            'pod_id': config['pod_id'],
            'ip_address': ip_address,
            'firmware_version': '1.0.0',
            'status': 'online',
            'cameras': cameras
        }
    )
```

Portal processes heartbeat:

```typescript
// Update POD status
UPDATE pods SET
  ip_address = '192.168.1.100',
  last_heartbeat = NOW(),
  status = 'online'
WHERE id = 'main-gate-pod';

// Update/create cameras
FOR EACH camera IN cameras:
  INSERT INTO cameras (id, pod_id, name, stream_url)
  VALUES (camera.id, pod_id, camera.name, generate_stream_url(pod_ip))
  ON CONFLICT (id) DO UPDATE SET
    name = camera.name,
    stream_url = generate_stream_url(pod_ip),
    status = 'active';
```

## Frontend Usage

### List Cameras

```typescript
// Fetch cameras from portal
const { data: cameras } = await supabase
  .from('cameras')
  .select(`
    *,
    pods!inner (
      id,
      name,
      ip_address,
      status
    )
  `)
  .eq('status', 'active');

// Display in UI
{cameras.map(camera => (
  <CameraCard
    name={camera.name}
    podName={camera.pods.name}
    status={camera.status}
    onViewStream={() => openStream(camera.id, camera.pod_id)}
  />
))}
```

### Stream Video (Method 1: Direct)

```typescript
const streamUrl = `${camera.stream_url}?token=${streamToken}`;

<video>
  <source src={streamUrl} type="application/x-mpegURL" />
</video>
```

### Stream Video (Method 2: Proxy)

```typescript
const proxyUrl = `/api/pod/proxy-stream/${camera.pod_id}?camera_id=${camera.id}`;

<video>
  <source src={proxyUrl} type="application/x-mpegURL" />
</video>
```

## Troubleshooting

### Browser Can't Connect to POD

**Symptoms:**
- Camera shows in portal but won't stream
- "Failed to load stream" error
- Timeout connecting to camera

**Diagnosis:**
```bash
# Check POD is reachable from portal server
curl http://POD-IP:8000/health

# Check stream endpoint
curl http://POD-IP:8000/stream?token=xxx
```

**Solutions:**
1. Use proxy method instead of direct connection
2. Configure port forwarding for POD
3. Use VPN/Tailscale for network connectivity
4. Ensure POD is sending correct IP in heartbeat

### POD Shows Offline

**Symptoms:**
- POD status = "offline" in portal
- Last heartbeat > 5 minutes ago

**Diagnosis:**
```bash
# On POD, check agent is running
ps aux | grep complete_pod_agent

# Check logs
journalctl -u platebridge-pod -f

# Test heartbeat manually
curl -X POST https://portal/api/pod/heartbeat \
  -H "Authorization: Bearer pbk_xxx" \
  -d '{"pod_id":"main-gate-pod"}'
```

**Solutions:**
1. Restart POD agent
2. Check network connectivity
3. Verify API key is valid
4. Check portal URL in config

### Camera Not Appearing

**Symptoms:**
- POD is online but no cameras shown

**Diagnosis:**
Check heartbeat payload includes cameras:
```python
print(json.dumps(heartbeat_payload, indent=2))
```

**Solutions:**
1. Verify camera_id and camera_name in config.yaml
2. Check heartbeat response from portal
3. Query database directly:
   ```sql
   SELECT * FROM cameras WHERE pod_id = 'main-gate-pod';
   ```

## Summary

**Discovery:** POD → Heartbeat → Portal → Database → Frontend
**Connection:** Browser → Portal (proxy) → POD → Camera
**Security:** Signed tokens with expiration
**Flexibility:** Direct, proxy, or VPN connection methods

The portal knows where to find cameras because:
1. POD tells portal its IP address via heartbeat
2. POD tells portal what cameras it has
3. Portal stores this in database
4. Frontend queries database
5. Portal proxies stream requests to POD's IP
