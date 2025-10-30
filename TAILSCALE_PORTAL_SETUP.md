# Tailscale Portal Access Guide

## Problem: Portal Cannot Directly Access Pods

Your portal runs on **Vercel** (serverless cloud), which means:
- ❌ Portal cannot install Tailscale
- ❌ Portal cannot access 100.x.x.x Tailscale IPs directly
- ❌ Portal is stateless and serverless

## Solution: Three Approaches

---

## Approach 1: Tailscale Funnel (Easiest - Recommended)

**Tailscale Funnel** exposes pod services to the public internet through Tailscale's infrastructure.

### On Each Pod:

```bash
# Enable Tailscale Funnel for stream server
docker exec platebridge-tailscale tailscale funnel --bg 8000

# This creates a public HTTPS URL:
# https://north-gate-pod.tail-abc123.ts.net
```

### Update Pod Database Migration:

```sql
-- Add funnel URL column
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_funnel_url TEXT;
```

### Update Pod Heartbeat:

```python
# In complete_pod_agent.py send_heartbeat()

# Get Tailscale funnel URL
try:
    result = subprocess.run(['tailscale', 'serve', 'status', '--json'],
                           capture_output=True, text=True, timeout=2)
    if result.returncode == 0:
        status = json.loads(result.stdout)
        funnel_url = status.get('Web', {}).get('FunnelURL', '')
except:
    funnel_url = None

payload = {
    'tailscale_ip': tailscale_ip,
    'tailscale_hostname': tailscale_hostname,
    'tailscale_funnel_url': funnel_url,  # NEW
}
```

### Portal Connects:

```typescript
// In portal API
const streamUrl = pod.tailscale_funnel_url
  || `https://${pod.tailscale_ip}:8000`  // Fallback (won't work from Vercel)
  || `https://${pod.ip_address}:8000`;    // Last resort
```

**Benefits:**
- ✅ Portal can connect from anywhere (even Vercel)
- ✅ Traffic encrypted by Tailscale
- ✅ No relay server needed
- ✅ Free (included with Tailscale)
- ✅ Automatic HTTPS certificates

**Drawbacks:**
- ⚠️ Exposes pods to public internet (through Tailscale)
- ⚠️ Requires Funnel enabled in Tailscale ACL

---

## Approach 2: Supabase Edge Function Relay (Hybrid)

Deploy a Supabase Edge Function on a server with Tailscale access.

### Architecture:

```
Portal (Vercel)
    ↓ HTTPS API call
Supabase Edge Function (on VPS with Tailscale)
    ↓ Tailscale (100.x.x.x)
Pods
```

### 1. Deploy Relay Server with Tailscale:

```bash
# On a VPS (DigitalOcean, AWS, etc.)
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=tskey-your-key

# Verify Tailscale is running
tailscale status
tailscale ip -4  # Should show 100.x.x.x
```

### 2. Install Supabase CLI:

```bash
npm install -g supabase
cd /path/to/project
```

### 3. Deploy Edge Function:

The relay function is already created at `supabase/functions/pod-relay/index.ts`.

```bash
# Deploy to your Supabase project
supabase functions deploy pod-relay

# Get the function URL
echo "Relay URL: https://your-project.supabase.co/functions/v1/pod-relay"
```

### 4. Portal Uses Relay:

```typescript
// In portal /app/api/pod/proxy-stream/[pod_id]/route.ts

export async function GET(request: NextRequest, { params }: { params: { pod_id: string } }) {
  const podId = params.pod_id;
  const camera_id = request.nextUrl.searchParams.get('camera_id');

  // Generate stream token
  const token = await generateStreamToken(podId, camera_id);

  // Call relay function
  const relayResponse = await fetch(
    `${process.env.SUPABASE_URL}/functions/v1/pod-relay`,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        pod_id: podId,
        endpoint: '/stream',
        method: 'GET',
        query: { token },
      }),
    }
  );

  // Stream response back to browser
  return new Response(relayResponse.body, {
    headers: {
      'Content-Type': 'application/vnd.apple.mpegurl',
    },
  });
}
```

**Benefits:**
- ✅ Portal stays on Vercel
- ✅ Pods not exposed to public internet
- ✅ Centralized relay server
- ✅ Can relay to any pod on Tailscale network

**Drawbacks:**
- ⚠️ Requires VPS with Tailscale
- ⚠️ Extra hop (slight latency)
- ⚠️ Single point of failure

---

## Approach 3: Self-Hosted Portal (Full Control)

Move portal to your own server with Tailscale.

### Architecture:

```
Portal Server (with Tailscale)
    ↓ Direct Tailscale (100.x.x.x)
Pods
```

### 1. Deploy Portal on VPS:

```bash
# On your VPS
git clone https://github.com/your-repo/platebridge-portal
cd platebridge-portal

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=tskey-your-key

# Install dependencies
npm install

# Build portal
npm run build

# Run with PM2
npm install -g pm2
pm2 start npm --name "platebridge-portal" -- start
pm2 save
pm2 startup
```

### 2. Portal Directly Accesses Pods:

```typescript
// Portal is on Tailscale network, can directly access pods
const streamUrl = `http://${pod.tailscale_ip}:8000/stream?token=${token}`;
const response = await fetch(streamUrl);
```

**Benefits:**
- ✅ Direct pod access (lowest latency)
- ✅ Full control over infrastructure
- ✅ No relay needed
- ✅ Can use Tailscale ACLs for security

**Drawbacks:**
- ⚠️ Requires managing your own server
- ⚠️ Can't use Vercel's edge network
- ⚠️ More DevOps overhead

---

## Comparison Table

| Feature | Funnel | Relay | Self-Hosted |
|---------|--------|-------|-------------|
| Portal on Vercel | ✅ Yes | ✅ Yes | ❌ No |
| Setup Difficulty | ⭐ Easy | ⭐⭐ Medium | ⭐⭐⭐ Hard |
| Latency | Low | Medium | Lowest |
| Cost | Free | VPS cost | VPS cost |
| Security | Public HTTPS | Private VPN | Private VPN |
| Maintenance | None | Low | High |

---

## Recommended Setup

### For MVP/Testing: **Approach 1 (Funnel)**
```bash
# On each pod
docker exec platebridge-tailscale tailscale funnel --bg 8000
```

### For Production: **Approach 2 (Relay)**
- Portal stays on Vercel (fast, CDN, easy deployments)
- One VPS runs relay function with Tailscale
- Pods stay private on Tailscale network

### For Enterprise: **Approach 3 (Self-Hosted)**
- Full control over infrastructure
- Direct pod access
- Can implement custom networking

---

## Implementation Steps for Recommended Setup (Relay)

### Step 1: Provision VPS

Choose any provider:
- DigitalOcean: $6/month
- AWS EC2: t3.micro
- Hetzner: €4/month

### Step 2: Install Tailscale on VPS

```bash
ssh root@your-vps.com

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Get auth key from https://login.tailscale.com/admin/settings/keys
tailscale up --authkey=tskey-auth-xxx

# Verify
tailscale status
tailscale ip -4
```

### Step 3: Deploy Supabase Function

```bash
# On your local machine
cd /path/to/platebridge

# Deploy function
supabase functions deploy pod-relay \
  --project-ref your-project-ref

# Test function
curl -X POST https://your-project.supabase.co/functions/v1/pod-relay \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "pod_id": "uuid-123",
    "endpoint": "/health"
  }'
```

### Step 4: Update Portal API

Update `app/api/pod/proxy-stream/[pod_id]/route.ts` to use relay function (code shown in Approach 2 section above).

### Step 5: Add Environment Variable

```bash
# In Vercel dashboard or .env
SUPABASE_RELAY_URL=https://your-project.supabase.co/functions/v1/pod-relay
```

### Step 6: Test End-to-End

1. Pod sends heartbeat with Tailscale IP
2. Portal receives heartbeat, stores Tailscale IP
3. User clicks "View Stream" in portal
4. Portal calls relay function with pod_id
5. Relay function fetches pod's Tailscale IP from database
6. Relay function connects to pod via Tailscale
7. Stream flows back through relay to portal to browser

---

## Troubleshooting

### Relay Cannot Reach Pod

```bash
# SSH into relay server
ssh root@your-vps.com

# Check Tailscale status
tailscale status

# Ping pod's Tailscale IP
ping 100.64.15.23

# Test HTTP connection
curl http://100.64.15.23:8000/health
```

### Portal Cannot Reach Relay

```bash
# Test relay function directly
curl -X POST https://your-project.supabase.co/functions/v1/pod-relay \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -d '{
    "pod_id": "uuid-123",
    "endpoint": "/health"
  }'
```

### Check Relay Logs

```bash
# In Supabase dashboard
# Go to Edge Functions → pod-relay → Logs
```

---

## Security Considerations

1. **API Authentication**: Relay function validates authorization header
2. **Pod Authentication**: Stream endpoints require JWT tokens
3. **Tailscale ACLs**: Restrict which devices can talk to pods
4. **Rate Limiting**: Add rate limiting to relay function
5. **Logging**: Log all relay requests for audit

---

## Next Steps

1. Choose your approach (recommend: Relay for production)
2. Provision infrastructure (VPS for relay)
3. Install Tailscale on relay server
4. Deploy Supabase Edge Function
5. Update portal API to use relay
6. Test with one pod
7. Roll out to all pods

Your pods are now securely accessible from the Vercel-hosted portal via Tailscale! 🎉
