# PlateBridge Quick Start Guide

## 🚀 Get Your System Running in 15 Minutes

This guide shows you how to set up the **Vercel + Tailscale Funnel** approach - the easiest way to get started.

---

## Prerequisites

- [ ] Vercel account (free)
- [ ] Tailscale account (free)
- [ ] Supabase project (free)
- [ ] Ubuntu server for pod (physical or VM)

---

## Step 1: Deploy Portal to Vercel (5 minutes)

### 1.1 Push to GitHub
```bash
git add .
git commit -m "Ready for deployment"
git push origin main
```

### 1.2 Deploy to Vercel
1. Go to [vercel.com/new](https://vercel.com/new)
2. Import your GitHub repository
3. Add environment variables:
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
   SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
   POD_STREAM_SECRET=generate-random-secret
   NEXT_PUBLIC_SITE_URL=https://your-app.vercel.app
   ```
4. Click **Deploy**
5. Wait 2-3 minutes
6. ✅ Your portal is live at `https://your-app.vercel.app`

---

## Step 2: Apply Database Migration (2 minutes)

### 2.1 Run Migration in Supabase

Go to Supabase Dashboard → SQL Editor → New Query:

```sql
-- Add Tailscale support to pods
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_ip TEXT;
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_hostname TEXT;
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_funnel_url TEXT;

CREATE INDEX IF NOT EXISTS idx_pods_tailscale_ip ON pods(tailscale_ip);
```

Click **Run** ✅

---

## Step 3: Install Pod Software (8 minutes)

### 3.1 Get Registration Token

1. Go to `https://your-app.vercel.app/properties`
2. Click **Generate POD Registration Token**
3. Copy the token (starts with `token_`)

### 3.2 Install on Ubuntu Server

SSH into your pod server:

```bash
# Download installer
wget https://your-app.vercel.app/install-pod.sh

# Run installer
sudo bash install-pod.sh
```

Follow the prompts:
```
Portal URL: https://your-app.vercel.app
Registration Token: token_abc123xyz789
Device Name: North Gate POD
```

Wait for installation to complete (5-8 minutes).

### 3.3 Enable Tailscale Funnel

```bash
# Get Tailscale auth key from https://login.tailscale.com/admin/settings/keys
# Create a new auth key with "Reusable" and "Ephemeral" unchecked

# Enable Tailscale Funnel on port 8000
docker exec platebridge-tailscale tailscale funnel --bg 8000

# Verify funnel is active
docker exec platebridge-tailscale tailscale serve status
```

You should see output like:
```
https://north-gate-pod.tail-abc123.ts.net (Funnel on)
|-- / proxy http://127.0.0.1:8000
```

✅ Your pod is now accessible from anywhere via Tailscale Funnel!

---

## Step 4: Verify Everything Works (2 minutes)

### 4.1 Check Portal

1. Go to `https://your-app.vercel.app/pods`
2. You should see your pod as **Online** ✅
3. Tailscale Funnel URL should show: `https://north-gate-pod.tail-abc123.ts.net` ✅

### 4.2 Check Heartbeat

Pod should be checking in every 60 seconds. Watch the logs:

```bash
docker logs -f platebridge-pod --tail 20
```

You should see:
```
Tailscale IP detected: 100.64.15.23
Tailscale Funnel URL: https://north-gate-pod.tail-abc123.ts.net
Heartbeat sent
```

### 4.3 Test Stream (if camera connected)

1. Go to portal → Pods → Your Pod → View Stream
2. Stream should load from Tailscale Funnel URL
3. Works from anywhere! ✅

---

## Architecture Overview

Your setup now looks like this:

```
Browser
    ↓ HTTPS
Vercel Portal (your-app.vercel.app)
    ↓ HTTPS via Tailscale Funnel
Pod (north-gate-pod.tail-abc123.ts.net)
    ↓ RTSP over private network
Cameras (192.168.1.x)
```

**Key Benefits:**
- ✅ Portal on Vercel - Fast, global CDN
- ✅ Pod accessible via Tailscale Funnel - No port forwarding
- ✅ Encrypted traffic - Tailscale WireGuard VPN
- ✅ Camera network isolated - Only pod can access

---

## Common Issues & Solutions

### Issue: Pod shows "Offline" in portal

**Check 1: Is pod running?**
```bash
docker ps | grep platebridge
```
Should show 3 containers running.

**Check 2: Is Tailscale connected?**
```bash
docker exec platebridge-tailscale tailscale status
```
Should show your tailnet.

**Check 3: Check pod logs**
```bash
docker logs platebridge-pod --tail 50
```
Look for errors.

**Fix:**
```bash
# Restart pod services
docker restart platebridge-pod
docker restart platebridge-tailscale
```

---

### Issue: Tailscale Funnel not working

**Check 1: Is funnel enabled?**
```bash
docker exec platebridge-tailscale tailscale serve status
```

**Check 2: Enable funnel properly**
```bash
# Stop existing serve
docker exec platebridge-tailscale tailscale serve off

# Re-enable funnel on port 8000
docker exec platebridge-tailscale tailscale funnel --bg 8000

# Verify
docker exec platebridge-tailscale tailscale serve status
```

**Check 3: Tailscale ACL allows funnel**

Go to [Tailscale Admin → Access Controls](https://login.tailscale.com/admin/acls)

Make sure funnel is enabled:
```json
{
  "acls": [
    {"action": "accept", "src": ["*"], "dst": ["*:*"]}
  ],
  "nodeAttrs": [
    {
      "target": ["*"],
      "attr": ["funnel"]
    }
  ]
}
```

---

### Issue: Stream not loading

**Check 1: Is camera connected?**
```bash
# SSH into pod
ping 192.168.1.100  # Your camera IP
```

**Check 2: Test stream directly**
```bash
curl "https://north-gate-pod.tail-abc123.ts.net/health"
```
Should return `{"status":"ok"}`

**Check 3: Check stream server logs**
```bash
docker logs platebridge-pod | grep stream
```

---

## Next Steps

Now that your basic system is running:

### Add More Cameras
1. Run discover script on pod:
   ```bash
   bash /opt/platebridge/discover-cameras.sh
   ```
2. Add cameras in portal under Cameras page

### Add More Pods
1. Generate new registration token in portal
2. Install on new server with same steps
3. Each pod gets its own Tailscale Funnel URL

### Configure Frigate (Optional)
If you want advanced AI detection:
1. Install Frigate on pod
2. Configure in `/opt/platebridge/frigate/config.yml`
3. Point cameras to Frigate MQTT

### Setup Trusted Vehicles
1. Go to Communities → Your Community → Access Control
2. Add license plates for automatic gate opening
3. Configure access schedules

---

## Performance Tips

### Optimize Stream Quality

Edit pod config:
```bash
sudo nano /opt/platebridge/config.yaml
```

Adjust:
```yaml
stream_quality: medium  # Options: low, medium, high
stream_fps: 15          # Lower = less bandwidth
```

Restart:
```bash
docker restart platebridge-pod
```

### Monitor Resource Usage

```bash
# Check CPU/Memory
docker stats platebridge-pod

# Check disk space
df -h /opt/platebridge/recordings
```

---

## Costs Summary

| Service | Cost | Notes |
|---------|------|-------|
| Vercel | **Free** | Hobby plan (100GB bandwidth/month) |
| Supabase | **Free** | Free plan (500MB database) |
| Tailscale | **Free** | Personal use up to 100 devices |
| **Total** | **$0/month** | For small deployments |

**When you scale:**
- Vercel Pro: $20/month (more bandwidth)
- Supabase Pro: $25/month (8GB database)
- Tailscale Premium: $6/user/month (enterprise features)

---

## Getting Help

### Check Logs
```bash
# Portal logs (Vercel)
# Go to Vercel Dashboard → Your Project → Functions → Logs

# Pod logs
docker logs -f platebridge-pod

# Tailscale logs
docker logs -f platebridge-tailscale
```

### Test Connectivity
```bash
# From pod, test portal
curl https://your-app.vercel.app/api/health

# From anywhere, test pod
curl https://north-gate-pod.tail-abc123.ts.net/health
```

### Community Support
- GitHub Issues: [your-repo/issues]
- Documentation: `TAILSCALE_PORTAL_SETUP.md`
- Architecture: `POD_CONNECTIVITY_GUIDE.md`

---

## You're All Set! 🎉

Your PlateBridge system is now running:
- ✅ Portal deployed to Vercel (global edge network)
- ✅ Pod connected via Tailscale (encrypted VPN)
- ✅ Funnel enabled (accessible from anywhere)
- ✅ Heartbeat active (pod checks in every 60 seconds)
- ✅ Ready for cameras and plate detection!

Start adding cameras and detecting plates! 🚗📸
