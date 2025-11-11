# Secure Vercel-to-POD Access via Tailscale

This guide explains how to securely connect your Vercel-hosted portal to PODs that have Tailscale installed.

## Overview

**Problem:** PODs are behind NAT/cellular networks, Vercel cannot directly access them.

**Solution:** Use Tailscale Funnel to create secure public HTTPS endpoints that Vercel can access.

---

## Method 1: Tailscale Funnel (RECOMMENDED)

### What is Tailscale Funnel?

Tailscale Funnel exposes your POD's local service to the public internet with:
- ✅ Automatic HTTPS with valid certificates
- ✅ Unique `*.ts.net` domain
- ✅ Works behind any NAT/firewall
- ✅ No port forwarding needed
- ✅ Rate limiting built-in

### Setup on POD

```bash
# 1. Ensure Tailscale is connected
sudo tailscale up

# 2. Enable Funnel for port 8000 (stream server)
sudo tailscale funnel 8000

# 3. Verify it's running
tailscale funnel status

# Output shows:
# https://pod-name.tail1234.ts.net
#   |-- / proxy http://127.0.0.1:8000
```

### Get Your Funnel URL

```bash
# Method 1: From funnel status
tailscale funnel status

# Method 2: From DNS name
echo "https://$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"

# Method 3: Check POD logs
docker logs platebridge-pod | grep "Tailscale Funnel URL"
```

### How It Works

1. **POD sends heartbeat** with `tailscale_funnel_url`
2. **Portal stores** the URL in database (`pods.tailscale_funnel_url`)
3. **Vercel uses** the Funnel URL to access POD streams

### Security

Even though the Funnel URL is technically public:
- ✅ Requires API key authentication
- ✅ Token-based stream access
- ✅ Rate limiting via Tailscale
- ✅ HTTPS encrypted
- ✅ Only your POD can serve it

---

## Method 2: Tailscale Subnet Router

For more security, route Vercel traffic through Tailscale.

### Setup Subnet Router on POD

```bash
# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Start Tailscale as subnet router
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes

# Verify
tailscale status
```

### Enable Routes in Tailscale Admin

1. Go to https://login.tailscale.com/admin/machines
2. Find your POD
3. Click "Edit route settings"
4. Enable the advertised routes

### Problem with Vercel

Vercel cannot join your Tailnet directly, so this method requires an intermediary.

---

## Method 3: Proxy via Tailscale Edge Function

If you have a server on your Tailnet, use it as a proxy.

### Setup Proxy Server

```bash
# On a server in your Tailnet
sudo tailscale up

# Install nginx or similar
sudo apt install nginx

# Configure nginx to proxy to PODs
sudo nano /etc/nginx/sites-available/pod-proxy

# Add:
server {
    listen 443 ssl;
    server_name proxy.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /pod/ {
        proxy_pass http://pod-tailscale-ip:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

---

## Implementation in Portal

### 1. Proxy Endpoint (Already Created)

```typescript
// /api/pod/tailscale-proxy
POST {
  "pod_id": "uuid",
  "endpoint": "/stream",
  "method": "GET"
}

// Response
{
  "success": true,
  "data": {...},
  "pod_url": "https://pod.tail123.ts.net",
  "via": "tailscale_funnel"
}
```

### 2. Update Stream Component

```typescript
// In your React component
const fetchPodStream = async (podId: string) => {
  const response = await fetch('/api/pod/tailscale-proxy', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      pod_id: podId,
      endpoint: '/stream?token=xyz',
      method: 'GET'
    })
  });

  const { data, pod_url, via } = await response.json();

  console.log(`Connected via ${via}: ${pod_url}`);
  return data;
};
```

### 3. Check POD Connection Status

```bash
# GET /api/pod/tailscale-proxy?pod_id=<uuid>
curl https://platebridge.vercel.app/api/pod/tailscale-proxy?pod_id=<uuid>

# Response shows best connection method
{
  "pod_id": "...",
  "connection": {
    "method": "tailscale_funnel",
    "url": "https://pod.tail123.ts.net",
    "tailscale_hostname": "pod-name",
    "tailscale_ip": "100.x.x.x"
  },
  "recommendations": {
    "best": "tailscale_funnel",
    "current": "tailscale_funnel",
    "action": "Using optimal connection method"
  }
}
```

---

## POD Configuration

### Update POD Heartbeat (Already Implemented)

The POD agent already detects and sends Tailscale info in heartbeats:

```python
# complete_pod_agent.py (line 410-431)
tailscale_ip = subprocess.run(['tailscale', 'ip', '-4'],
                               capture_output=True, text=True).stdout.strip()

tailscale_hostname = ...  # from tailscale status --json

# Build Funnel URL
tailscale_funnel_url = f"https://{tailscale_hostname}.{tailnet}.ts.net"

# Send in heartbeat
payload = {
    'pod_id': pod_id,
    'tailscale_ip': tailscale_ip,
    'tailscale_hostname': tailscale_hostname,
    'tailscale_funnel_url': tailscale_funnel_url
}
```

### Enable Funnel Automatically on Boot

Create systemd service:

```bash
sudo nano /etc/systemd/system/tailscale-funnel.service
```

```ini
[Unit]
Description=Tailscale Funnel for POD Stream
After=tailscaled.service
Requires=tailscaled.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/tailscale funnel 8000
ExecStop=/usr/bin/tailscale funnel reset

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable tailscale-funnel
sudo systemctl start tailscale-funnel
```

---

## Security Best Practices

### 1. Rate Limiting

Tailscale Funnel has built-in rate limiting, but add application-level limits:

```python
# In pod agent
from flask_limiter import Limiter

limiter = Limiter(
    app,
    key_func=lambda: request.headers.get('X-Forwarded-For', request.remote_addr),
    default_limits=["100 per hour"]
)

@app.route('/stream')
@limiter.limit("10 per minute")
def stream():
    # ...
```

### 2. Token-Based Authentication

Already implemented in `complete_pod_agent.py`:

```python
def validate_stream_token(token: str) -> bool:
    # Validates JWT-like tokens with expiration
    payload = jwt.decode(token, secret)
    return payload['exp'] > time.time()
```

### 3. API Key Validation

All POD endpoints require API key:

```python
headers = {
    'Authorization': f"Bearer {pod_api_key}"
}
```

### 4. HTTPS Only

Tailscale Funnel enforces HTTPS with valid certificates automatically.

### 5. Firewall Rules

Even with Funnel, keep firewall rules restrictive:

```bash
# Only allow Tailscale and localhost
sudo iptables -A INPUT -i tailscale0 -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8000 -j DROP
```

---

## Monitoring

### Check Funnel Status

```bash
# On POD
tailscale funnel status

# Check logs
sudo journalctl -u tailscaled -f | grep funnel
```

### Monitor Access Logs

```bash
# POD stream server logs
docker logs platebridge-pod | grep "X-Forwarded-For"

# Tailscale access logs
tailscale status --json | jq '.Peer[] | select(.Online==true)'
```

### Portal Dashboard

Add Tailscale status to POD detail page:

```typescript
// Display in UI
<Card>
  <h3>Connection Status</h3>
  <Badge color={pod.tailscale_funnel_url ? "green" : "yellow"}>
    {pod.tailscale_funnel_url ? "Tailscale Funnel Active" : "Fallback Mode"}
  </Badge>

  {pod.tailscale_funnel_url && (
    <p>Secure URL: {pod.tailscale_funnel_url}</p>
  )}
</Card>
```

---

## Troubleshooting

### Funnel Not Working

```bash
# Check Tailscale is running
sudo systemctl status tailscaled

# Check Tailscale connection
tailscale status

# Re-enable funnel
sudo tailscale funnel reset
sudo tailscale funnel 8000

# Check funnel logs
sudo journalctl -u tailscaled -f
```

### Cannot Access Funnel URL

```bash
# Test locally
curl http://localhost:8000/health

# Test via Tailscale
curl https://$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')/health

# Check firewall
sudo iptables -L -n | grep 8000
```

### Heartbeat Not Sending Funnel URL

```bash
# Check POD logs
docker logs platebridge-pod | grep -i tailscale

# Manually test Tailscale detection
docker exec platebridge-pod tailscale ip -4

# Should output: 100.x.x.x
```

### Vercel Cannot Connect

```bash
# Test from external network
curl https://pod-name.tail123.ts.net/health

# Check Tailscale status
tailscale status --json | jq '.Self.Online'

# Verify funnel is serving
curl -I https://pod-name.tail123.ts.net
```

---

## Cost Considerations

### Tailscale Pricing

- **Free tier:** 100 devices, unlimited bandwidth
- **Personal Pro:** $6/month (more devices)
- **Team:** $6/user/month (ACLs, admin features)

### Funnel Limits

- Free tier: Reasonable rate limits
- No bandwidth charges
- No concurrent connection limits

---

## Alternative: Cloudflare Tunnel

If you prefer not to use Tailscale Funnel:

```bash
# Install cloudflared
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared

# Authenticate
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create platebridge-pod

# Configure
cloudflared tunnel route dns platebridge-pod pod.yourdomain.com

# Run tunnel
cloudflared tunnel run --url http://localhost:8000 platebridge-pod
```

---

## Summary

**Recommended Setup:**

1. ✅ Enable Tailscale Funnel on POD: `sudo tailscale funnel 8000`
2. ✅ POD sends Funnel URL in heartbeat (already implemented)
3. ✅ Portal stores URL in database
4. ✅ Vercel uses `/api/pod/tailscale-proxy` to access PODs
5. ✅ All traffic is HTTPS with authentication

**Result:**
- Vercel can securely access PODs anywhere
- No port forwarding needed
- No VPN configuration required
- Automatic HTTPS certificates
- Built-in rate limiting

Your PODs are now securely accessible from Vercel! 🎉
