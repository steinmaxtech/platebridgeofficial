# Cloudflare Tunnel Setup for PlateBridge POD

Use Cloudflare Tunnel to securely expose your POD to the portal without port forwarding.

## Why Cloudflare Tunnel?

- ✅ POD stays private (no inbound ports)
- ✅ Works with Vercel serverless portal
- ✅ Auto SSL certificates
- ✅ DDoS protection included
- ✅ Free tier available
- ✅ No router/firewall config needed

## Prerequisites

- Cloudflare account (free)
- Domain name (can use Cloudflare's free subdomain)
- POD device with internet access

---

## Step 1: Install cloudflared on POD

```bash
# SSH into POD
ssh pi@your-pod-ip

# Download cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64

# Make executable
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared

# Verify
cloudflared --version
```

---

## Step 2: Authenticate with Cloudflare

```bash
# Login (opens browser)
cloudflared tunnel login

# This saves credentials to ~/.cloudflared/cert.pem
```

---

## Step 3: Create Tunnel

```bash
# Create tunnel named "platebridge-pod"
cloudflared tunnel create platebridge-pod

# Output shows tunnel ID:
# Tunnel credentials written to /home/pi/.cloudflared/TUNNEL-ID.json
# Copy this tunnel ID!
```

---

## Step 4: Configure Tunnel

Create config file:

```bash
sudo mkdir -p /etc/cloudflared
sudo nano /etc/cloudflared/config.yml
```

**Paste this config:**

```yaml
tunnel: TUNNEL-ID-HERE
credentials-file: /home/pi/.cloudflared/TUNNEL-ID.json

ingress:
  # Stream endpoint
  - hostname: pod.yourdomain.com
    service: http://localhost:8000
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s

  # Fallback (required)
  - service: http_status:404
```

**Replace:**
- `TUNNEL-ID-HERE` with your actual tunnel ID
- `pod.yourdomain.com` with your desired hostname

---

## Step 5: Create DNS Record

```bash
# Point DNS to tunnel
cloudflared tunnel route dns platebridge-pod pod.yourdomain.com

# Output:
# Created CNAME pod.yourdomain.com → TUNNEL-ID.cfargotunnel.com
```

**Or manually in Cloudflare Dashboard:**
1. Go to DNS settings
2. Add CNAME record:
   - Name: `pod`
   - Target: `TUNNEL-ID.cfargotunnel.com`
   - Proxied: ✅ Yes

---

## Step 6: Test Tunnel

```bash
# Start tunnel in foreground (test)
cloudflared tunnel run platebridge-pod

# You should see:
# "Connection registered"
# "Proxy ready to accept requests"
```

**Test from another machine:**
```bash
curl https://pod.yourdomain.com/health

# Should return: {"status": "ok"}
```

---

## Step 7: Run as Service

```bash
# Install service
sudo cloudflared service install

# Start service
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# Check status
sudo systemctl status cloudflared

# View logs
sudo journalctl -u cloudflared -f
```

---

## Step 8: Update POD Config

Edit POD agent config:

```yaml
# config.yaml

# POD will report this as its public URL
public_ip: "pod.yourdomain.com"

# Stream server listens on localhost only
stream_bind: "127.0.0.1"
stream_port: 8000

# Portal will connect via Cloudflare tunnel
enable_streaming: true
```

Restart POD agent:
```bash
sudo systemctl restart platebridge-pod
```

---

## Step 9: Update Portal Config

In portal, POD will auto-register with URL:
```
https://pod.yourdomain.com:8000/stream
```

Portal (on Vercel) can now reach POD via Cloudflare!

**Test in portal:**
1. Go to **Cameras** page
2. Click on camera
3. Click **View Stream**
4. Stream should load from `pod.yourdomain.com`

---

## Architecture

```
┌──────────┐
│ Browser  │
└────┬─────┘
     │ HTTPS
     ▼
┌──────────────┐
│   Portal     │
│  (Vercel)    │
└────┬─────────┘
     │ HTTPS
     ▼
┌──────────────┐
│  Cloudflare  │
│     CDN      │
└────┬─────────┘
     │ Encrypted Tunnel
     ▼
┌──────────────┐
│ cloudflared  │
│   (on POD)   │
└────┬─────────┘
     │ localhost
     ▼
┌──────────────┐
│ POD Stream   │
│   :8000      │
└──────────────┘
```

**Security:**
- POD has NO inbound ports open
- All connections are outbound (POD → Cloudflare)
- Cloudflare handles SSL/TLS
- POD stays at 192.168.1.x (private)

---

## Multiple PODs Setup

For multiple PODs, each gets its own tunnel:

**POD 1 (Main Gate):**
```bash
cloudflared tunnel create main-gate-pod
cloudflared tunnel route dns main-gate-pod main-gate.yourdomain.com
```

**POD 2 (Back Gate):**
```bash
cloudflared tunnel create back-gate-pod
cloudflared tunnel route dns back-gate-pod back-gate.yourdomain.com
```

Each POD reports its own URL in heartbeat.

---

## Troubleshooting

### Tunnel Won't Start

**Check credentials exist:**
```bash
ls -la ~/.cloudflared/
# Should show: cert.pem and TUNNEL-ID.json
```

**Check config valid:**
```bash
cloudflared tunnel ingress validate
```

### Can't Reach POD from Portal

**Test tunnel endpoint:**
```bash
curl https://pod.yourdomain.com/health
```

**Check DNS propagation:**
```bash
dig pod.yourdomain.com
# Should show CNAME → cfargotunnel.com
```

**Check cloudflared logs:**
```bash
sudo journalctl -u cloudflared -n 50
```

### Stream Timeout

**Increase timeout in config:**
```yaml
ingress:
  - hostname: pod.yourdomain.com
    service: http://localhost:8000
    originRequest:
      connectTimeout: 60s      # Increase
      noTLSVerify: true
      keepAliveTimeout: 90s
```

### Too Slow

Cloudflare free tier has bandwidth limits. For high bandwidth:
- Use Cloudflare paid plan
- Or use Tailscale VPN instead
- Or self-host portal closer to PODs

---

## Cost

**Cloudflare Tunnel:**
- Free tier: Unlimited tunnels, reasonable bandwidth
- Paid tier ($5/month): Higher bandwidth, more features

**Domain:**
- Use existing domain (free if you have one)
- Or buy domain (~$10/year)
- Or use Cloudflare's free .cfargotunnel.com subdomain

**Total:** $0/month (free tier) or ~$5-10/month (paid)

---

## Alternative: Tailscale (If Self-Hosting Portal)

If you're NOT using Vercel, use Tailscale instead:

```bash
# On POD and Portal server
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# POD gets: 100.64.1.5
# Portal gets: 100.64.1.2
# Portal connects to: http://100.64.1.5:8000
```

**Pros:**
- Simpler setup
- Better performance
- More secure (private network)

**Cons:**
- Requires VPN client on portal server
- Doesn't work with Vercel serverless

---

## Summary

**For Vercel Portal + Home POD:**
✅ Use Cloudflare Tunnel

**For Self-Hosted Portal:**
✅ Use Tailscale VPN

**For Quick Testing:**
✅ Port forward (temporary)

Your POD stays private, portal stays on Vercel, everything works securely!
