# Golden Image Auto-Configuration Architecture

## How Auto-Configuration Works Without Manual Intervention

Your golden image will automatically configure itself with the portal and Tailscale using a **first-boot service** that reads configuration from USB, environment variables, or the portal.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     GOLDEN IMAGE                             │
│  ✅ Ubuntu 24.04 + Docker + Frigate + Agent (PRE-INSTALLED) │
│  ✅ First-boot service (systemd)                             │
│  ✅ Auto-configuration scripts                               │
│  ⚠️  NO CREDENTIALS (must be provided on first boot)        │
└─────────────────────────────────────────────────────────────┘
                            ↓
                    FIRST BOOT DETECTS
                            ↓
        ┌───────────────────┼───────────────────┐
        │                   │                   │
    USB CONFIG        ENV VARS         PORTAL CALLBACK
    (Recommended)     (Cloud/VM)       (Interactive)
        │                   │                   │
        ↓                   ↓                   ↓
    ┌─────────────────────────────────────────────┐
    │     AUTO-REGISTRATION WITH PORTAL           │
    │  POST /api/pods/register                    │
    │  → Receives: API key, POD ID, Community ID  │
    └─────────────────────────────────────────────┘
                            ↓
    ┌─────────────────────────────────────────────┐
    │     AUTO-CONNECT TO TAILSCALE               │
    │  tailscale up --authkey=...                 │
    │  tailscale funnel 8000                      │
    └─────────────────────────────────────────────┘
                            ↓
    ┌─────────────────────────────────────────────┐
    │     START ALL SERVICES                      │
    │  docker compose up -d                       │
    └─────────────────────────────────────────────┘
                            ↓
    ┌─────────────────────────────────────────────┐
    │     SEND FIRST HEARTBEAT                    │
    │  POST /api/pod/heartbeat                    │
    │  → Portal sees POD online                   │
    └─────────────────────────────────────────────┘
                            ↓
                    ✅ POD OPERATIONAL
```

---

## Method 1: USB Configuration (Recommended for Field Deployment)

### Step 1: Prepare USB Drive

**On any computer, create config file:**

```bash
# Create platebridge-config.yaml on USB root
cat > /media/usb/platebridge-config.yaml << EOF
# Required
portal_url: https://platebridge.vercel.app
registration_token: pbr_1234567890abcdef

# Optional
device_name: Main Gate POD
timezone: America/New_York
hostname: main-gate-pod
tailscale_authkey: tskey-auth-xxxxxxxxxxxxx
plate_recognizer_token: your_token_here
EOF
```

**Where to get these values:**

- **`portal_url`**: Your portal URL (always the same)
- **`registration_token`**: Generate in portal:
  - Go to **Communities** → Your Community → **Tokens**
  - Click "Generate Registration Token"
  - Valid for 24 hours
- **`tailscale_authkey`**: Generate in Tailscale admin:
  - Go to https://login.tailscale.com/admin/settings/keys
  - Create auth key (reusable, non-ephemeral)
- **`plate_recognizer_token`**: From https://app.platerecognizer.com/

### Step 2: POD First Boot

1. **Flash golden image to POD**
2. **Insert USB drive**
3. **Connect network cables** (WAN + LAN)
4. **Power on**

**What happens automatically:**

```bash
# First-boot service runs (/opt/platebridge/bin/first-boot.sh)

1. Detect USB drive mounted
2. Find platebridge-config.yaml
3. Read configuration values
4. Get hardware info (serial, MAC, model)
5. Register with portal:
   curl -X POST https://platebridge.vercel.app/api/pods/register \
     -d '{"registration_token": "pbr_...", "serial": "...", ...}'
   # Response: {"api_key": "pbk_...", "pod_id": "uuid", ...}

6. Create /opt/platebridge/docker/.env:
   PORTAL_URL=https://platebridge.vercel.app
   POD_API_KEY=pbk_xxxxxxxxxxxxx
   POD_ID=uuid
   COMMUNITY_ID=uuid
   PLATE_RECOGNIZER_TOKEN=xxx

7. Connect Tailscale:
   tailscale up --authkey=tskey-auth-xxxxxxxxxxxxx
   tailscale funnel 8000
   # Now accessible at https://pod-name.tail123.ts.net

8. Start Docker services:
   cd /opt/platebridge/docker
   docker compose up -d

9. Send first heartbeat:
   curl -X POST https://platebridge.vercel.app/api/pod/heartbeat \
     -H "Authorization: Bearer pbk_xxxxxxxxxxxxx" \
     -d '{"pod_id": "uuid", "status": "online", ...}'

10. Remove first-boot flag
11. ✅ DONE - POD is operational!
```

**Timeline: 2-3 minutes total**

**Portal shows: "Main Gate POD - Online - Just registered"**

---

## Method 2: Environment Variables (Cloud/VM Deployment)

### For Cloud-Init or Automated Deployment

**Set environment variables before first boot:**

```bash
# /etc/environment or cloud-init
export PLATEBRIDGE_PORTAL_URL=https://platebridge.vercel.app
export PLATEBRIDGE_REGISTRATION_TOKEN=pbr_xxxxxxxxxxxxx
export PLATEBRIDGE_TAILSCALE_KEY=tskey-auth-xxxxxxxxxxxxx
export PLATEBRIDGE_DEVICE_NAME="Cloud POD 01"
```

**On first boot, same auto-configuration runs using env vars instead of USB**

---

## Method 3: Portal Callback (Interactive for Remote PODs)

### For PODs Without Physical Access

**POD first boot:**
1. No USB config found
2. No env vars set
3. POD creates "pending registration" request
4. Sends to portal: serial, MAC, model, IP address

**Portal:**
1. Shows notification: "New POD requesting registration"
2. Admin clicks POD → "Approve" → Assigns to community
3. Portal generates API key
4. Portal pushes config to POD via callback

**POD:**
1. Receives API key from portal
2. Auto-configures
3. Starts services
4. Sends heartbeat

---

## Implementation: First-Boot Service

### Script Location in Golden Image

```
/opt/platebridge/
├── bin/
│   ├── first-boot.sh          ← Auto-configuration script
│   └── health-check.sh
├── config/
│   └── .first-boot-needed     ← Flag file (removed after first boot)
├── docker/
│   ├── docker-compose.yml
│   └── .env.example
└── logs/
```

### First-Boot Script

**File:** `/opt/platebridge/bin/first-boot.sh`

```bash
#!/bin/bash
set -e

FIRST_BOOT_FLAG="/opt/platebridge/config/.first-boot-needed"
ENV_FILE="/opt/platebridge/docker/.env"

# Exit if not first boot
[ ! -f "$FIRST_BOOT_FLAG" ] && exit 0

echo "🚀 PlateBridge POD - First Boot Auto-Configuration"

# Priority 1: USB Configuration
USB_CONFIG=$(find /media /mnt -name "platebridge-config.yaml" 2>/dev/null | head -1)
if [ -n "$USB_CONFIG" ]; then
    echo "✓ Found USB config: $USB_CONFIG"
    source <(grep = "$USB_CONFIG" | sed 's/: /=/g')
    PORTAL_URL=$(grep "portal_url:" "$USB_CONFIG" | cut -d: -f2- | xargs)
    REG_TOKEN=$(grep "registration_token:" "$USB_CONFIG" | cut -d: -f2- | xargs)
    DEVICE_NAME=$(grep "device_name:" "$USB_CONFIG" | cut -d: -f2- | xargs)
    TAILSCALE_KEY=$(grep "tailscale_authkey:" "$USB_CONFIG" | cut -d: -f2- | xargs)
    PLATE_TOKEN=$(grep "plate_recognizer_token:" "$USB_CONFIG" | cut -d: -f2- | xargs)
fi

# Priority 2: Environment Variables
[ -z "$PORTAL_URL" ] && PORTAL_URL="$PLATEBRIDGE_PORTAL_URL"
[ -z "$REG_TOKEN" ] && REG_TOKEN="$PLATEBRIDGE_REGISTRATION_TOKEN"
[ -z "$DEVICE_NAME" ] && DEVICE_NAME="$PLATEBRIDGE_DEVICE_NAME"
[ -z "$TAILSCALE_KEY" ] && TAILSCALE_KEY="$PLATEBRIDGE_TAILSCALE_KEY"

# Priority 3: Request manual config
if [ -z "$PORTAL_URL" ] || [ -z "$REG_TOKEN" ]; then
    echo "⚠ No configuration found. Waiting for USB config or env vars..."
    echo "Insert USB with platebridge-config.yaml and reboot."
    exit 0
fi

# Get hardware info
SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || hostname)
MAC=$(ip link show enp1s0 | grep link/ether | awk '{print $2}')
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "PB-M1")
DEVICE_NAME="${DEVICE_NAME:-POD-$SERIAL}"

echo "Hardware: $MODEL (Serial: $SERIAL, MAC: $MAC)"

# Register with portal
echo "Registering with portal: $PORTAL_URL"
RESPONSE=$(curl -s -X POST "$PORTAL_URL/api/pods/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"serial\": \"$SERIAL\",
        \"mac\": \"$MAC\",
        \"model\": \"$MODEL\",
        \"version\": \"1.0.0\",
        \"registration_token\": \"$REG_TOKEN\",
        \"device_name\": \"$DEVICE_NAME\"
    }")

# Parse response
POD_API_KEY=$(echo "$RESPONSE" | jq -r '.api_key // empty')
POD_ID=$(echo "$RESPONSE" | jq -r '.pod_id // empty')
COMMUNITY_ID=$(echo "$RESPONSE" | jq -r '.community_id // empty')

if [ -z "$POD_API_KEY" ]; then
    echo "✗ Registration failed: $RESPONSE"
    exit 1
fi

echo "✓ Registered: POD ID=$POD_ID, Community=$COMMUNITY_ID"

# Create .env file
cat > "$ENV_FILE" << EOF
PORTAL_URL=$PORTAL_URL
POD_API_KEY=$POD_API_KEY
POD_ID=$POD_ID
COMMUNITY_ID=$COMMUNITY_ID
POD_SERIAL=$SERIAL
PLATE_RECOGNIZER_TOKEN=${PLATE_TOKEN:-}
FRIGATE_RTSP_PASSWORD=password
EOF

chmod 600 "$ENV_FILE"
chown platebridge:platebridge "$ENV_FILE"
echo "✓ Configuration saved"

# Connect to Tailscale
if [ -n "$TAILSCALE_KEY" ]; then
    echo "Connecting to Tailscale..."
    tailscale up --authkey="$TAILSCALE_KEY" --accept-routes --ssh
    sleep 3
    tailscale funnel 8000
    TS_IP=$(tailscale ip -4)
    echo "✓ Tailscale connected: $TS_IP"
    echo "✓ Funnel enabled: https://$(tailscale status --json | jq -r '.Self.DNSName')"
fi

# Start Docker services
echo "Starting services..."
cd /opt/platebridge/docker
docker compose up -d --remove-orphans
echo "✓ Services started"

# Wait for services
sleep 15

# Send first heartbeat
echo "Sending first heartbeat..."
HEARTBEAT=$(curl -s -X POST "$PORTAL_URL/api/pod/heartbeat" \
    -H "Authorization: Bearer $POD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"pod_id\": \"$POD_ID\",
        \"status\": \"online\",
        \"system\": {
            \"cpu_percent\": $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'),
            \"memory_percent\": $(free | grep Mem | awk '{print ($3/$2)*100}'),
            \"disk_percent\": $(df / | tail -1 | awk '{print $5}' | tr -d %)
        }
    }")

echo "Heartbeat response: $(echo $HEARTBEAT | jq -r '.status // "sent"')"

# Remove first-boot flag
rm -f "$FIRST_BOOT_FLAG"

echo ""
echo "╔═════════════════════════════════════════════╗"
echo "║  ✓ POD Configuration Complete!              ║"
echo "╚═════════════════════════════════════════════╝"
echo ""
echo "POD Name: $DEVICE_NAME"
echo "POD ID: $POD_ID"
echo "Status: Online and reporting to portal"
echo ""
echo "Services:"
echo "  - Frigate: http://$(hostname -I | awk '{print $1}'):5000"
[ -n "$TS_IP" ] && echo "  - Tailscale: https://$(tailscale status --json | jq -r '.Self.DNSName')"
echo ""
echo "Your POD is operational! Check the portal."
```

### Systemd Service

**File:** `/etc/systemd/system/platebridge-first-boot.service`

```ini
[Unit]
Description=PlateBridge POD First Boot Auto-Configuration
After=network-online.target docker.service
Wants=network-online.target
Before=platebridge-pod.service

[Service]
Type=oneshot
ExecStart=/opt/platebridge/bin/first-boot.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=300

[Install]
WantedBy=multi-user.target
```

**Enable in golden image creation:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable platebridge-first-boot
```

---

## Portal Integration

### Add Registration Token API

**File:** `app/api/pods/registration-tokens/route.ts`

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { supabaseServer } from '@/lib/supabase-server';
import crypto from 'crypto';

export async function POST(request: NextRequest) {
  const { community_id } = await request.json();

  // Generate unique token
  const token = `pbr_${crypto.randomBytes(32).toString('hex')}`;

  // Store in database
  const { data, error } = await supabase
    .from('pod_registration_tokens')
    .insert({
      token,
      community_id,
      expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      used: false,
      created_at: new Date().toISOString()
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({
    token: data.token,
    expires_at: data.expires_at,
    community_id: data.community_id
  });
}
```

### Update Registration Endpoint

Your existing `/api/pods/register` already handles token-based registration. Just ensure it:

1. Validates token hasn't been used
2. Checks token hasn't expired
3. Generates API key automatically
4. Returns pod_id, api_key, and community_id
5. Marks token as used

---

## Tailscale Bulk Setup

### Generate Auth Keys for Communities

**In Portal Settings:**

```typescript
// Generate reusable Tailscale auth key for a community
async function generateTailscaleKey(communityId: string) {
  // Call Tailscale API to create key
  const response = await fetch('https://api.tailscale.com/api/v2/tailnet/-/keys', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.TAILSCALE_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      capabilities: {
        devices: {
          create: {
            reusable: true,
            ephemeral: false,
            preauthorized: true,
            tags: [`tag:community-${communityId}`]
          }
        }
      },
      expirySeconds: 31536000 // 1 year
    })
  });

  const { key } = await response.json();

  // Store in database
  await supabase
    .from('communities')
    .update({ tailscale_authkey: key })
    .eq('id', communityId);

  return key;
}
```

**Include in USB config generation:**

```typescript
// Generate USB config for a POD
export async function generateUSBConfig(communityId: string) {
  const { data: token } = await supabase
    .from('pod_registration_tokens')
    .insert({ community_id: communityId, expires_at: ... })
    .select()
    .single();

  const { data: community } = await supabase
    .from('communities')
    .select('tailscale_authkey')
    .eq('id', communityId)
    .single();

  const config = `
portal_url: ${process.env.NEXT_PUBLIC_PORTAL_URL}
registration_token: ${token.token}
tailscale_authkey: ${community.tailscale_authkey}
device_name: ${siteName} POD
timezone: America/New_York
`;

  return config;
}
```

---

## Creating Golden Image with First-Boot

### During Golden Image Creation

```bash
# 1. Install everything
sudo ./install-complete.sh

# 2. Clean configuration
sudo rm -f /opt/platebridge/docker/.env
sudo rm -f /var/lib/platebridge/pod-id
sudo rm -f /etc/machine-id
sudo dbus-uuidgen --ensure=/etc/machine-id

# 3. Logout Tailscale
sudo tailscale logout

# 4. Create first-boot flag
sudo touch /opt/platebridge/config/.first-boot-needed

# 5. Clear logs
sudo journalctl --vacuum-time=1s
sudo rm -rf /var/log/*.log

# 6. Clear bash history
history -c

# 7. Create the images
sudo ./golden-image/create-disk-image.sh
```

---

## Field Deployment Workflow

### Prepare for Deployment

**Portal Admin:**
1. Go to Communities → Select community
2. Go to Tokens tab
3. Click "Generate USB Config"
4. Download `platebridge-config.yaml`
5. Copy to USB drive
6. Send USB to installer

**OR bulk generate:**
```typescript
// Generate 100 USB configs
for (let i = 0; i < 100; i++) {
  const config = await generateUSBConfig(communityId);
  await writeFile(`usb-configs/site-${i}.yaml`, config);
}
```

### Installation

**Installer (no technical knowledge needed):**

1. **Receive:** POD + USB drive
2. **Flash** golden image to POD (if not pre-flashed)
3. **Install** POD at gate location
4. **Connect** cables (power, WAN, cameras)
5. **Insert** USB drive
6. **Power on** POD
7. **Wait 3 minutes** (auto-configures)
8. **Check portal** - POD shows online
9. **Remove** USB drive
10. **Done!**

**No command line, no typing, no configuration!**

---

## Summary

### What Makes It Automatic

✅ **First-boot service** runs on every boot until configured
✅ **USB detection** automatically reads config file
✅ **Portal registration** gets API key without human interaction
✅ **Tailscale auto-connect** if authkey provided
✅ **Funnel auto-enable** for secure public access
✅ **Docker auto-start** all services
✅ **Heartbeat auto-send** confirms to portal
✅ **Self-healing** if config fails, retries every 5 minutes

### Zero Manual Steps Required

❌ No SSH login needed
❌ No command typing
❌ No portal username/password
❌ No copy-paste of keys
❌ No network configuration
❌ No firewall setup
❌ No service management

### Result

**Golden Image + USB Config = Fully Operational POD in 3 Minutes!** 🚀
