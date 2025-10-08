# Pod Integration Guide for PlateBridge

## Overview

Your PlateBridge system supports connecting physical gate pods (license plate recognition hardware) to the cloud platform. Pods are the edge devices that run at gate entrances and perform real-time license plate detection.

## System Architecture

```
[Pod Device at Gate]
    ↓ (HTTPS API Calls)
[Your Vercel Deployment - PlateBridge API]
    ↓
[Supabase Database]
```

## Available API Endpoints

### 1. Get Plates Configuration for a Site

**Endpoint:** `GET /api/plates`

**Purpose:** Pods call this to get the current whitelist of allowed license plates for a site.

**Query Parameters:**
- `site` (required) - Site name identifier
- `company_id` (required) - Company UUID

**Example Request:**
```bash
curl "https://your-domain.vercel.app/api/plates?site=main-gate&company_id=6081bef5-f756-4dda-8b49-b7b5b140a959"
```

**Example Response:**
```json
{
  "config_version": 5,
  "site": "main-gate",
  "company_id": "6081bef5-f756-4dda-8b49-b7b5b140a959",
  "entries": [
    {
      "id": "uuid",
      "plate": "ABC123",
      "unit": "101",
      "tenant": "John Doe",
      "vehicle": "Toyota Camry",
      "starts": "2025-01-01",
      "ends": "2026-01-01",
      "enabled": true,
      "notes": "Resident"
    }
  ],
  "timestamp": "2025-10-08T02:00:00.000Z"
}
```

### 2. Nudge Configuration Update

**Endpoint:** `POST /api/nudge`

**Purpose:** Force pods to refresh their configuration by incrementing the config_version.

**Authentication:** Requires Bearer token (admin/owner JWT or ADMIN_NUDGE_SECRET)

**Request Body:**
```json
{
  "property": "main-gate",
  "reason": "Added new resident plate"
}
```

**Example Request:**
```bash
curl -X POST https://your-domain.vercel.app/api/nudge \
  -H "Authorization: Bearer YOUR_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"property":"main-gate","reason":"Added new resident"}'
```

**Example Response:**
```json
{
  "property": "main-gate",
  "config_version": 6,
  "previous_version": 5,
  "timestamp": "2025-10-08T02:00:00.000Z"
}
```

## Database Tables

### pod_health

Tracks the health and status of each pod device.

**Columns:**
- `id` - UUID
- `site_id` - Foreign key to sites table
- `pod_name` - Unique identifier for the pod
- `status` - 'online', 'offline', 'error'
- `last_checkin` - Timestamp of last heartbeat
- `last_sync` - Timestamp of last config sync
- `version` - Software version running on pod
- `ip_address` - Pod's current IP address
- `cpu_usage` - CPU usage percentage
- `memory_usage` - Memory usage percentage
- `disk_usage` - Disk usage percentage
- `camera_count` - Number of cameras connected
- `plates_detected_24h` - Plates detected in last 24 hours
- `error_message` - Last error message if any
- `metadata` - JSONB for additional data

### sites

Defines physical sites/gates where pods are deployed.

**Columns:**
- `id` - UUID
- `community_id` - Foreign key to communities
- `name` - Site name (e.g., "main-gate", "north-entrance")
- `site_id` - External site identifier
- `camera_ids` - Array of camera IDs
- `is_active` - Boolean
- `config_version` - Current configuration version number

### gatewise_config

Configuration for Gatewise API integration (if using Gatewise hardware).

**Columns:**
- `id` - UUID
- `community_id` - Foreign key to communities
- `api_key` - Gatewise API key
- `api_endpoint` - Gatewise API endpoint
- `enabled` - Boolean
- `last_sync` - Last sync timestamp
- `sync_status` - 'pending', 'success', 'error'

## Pod Integration Steps

### Step 1: Create a Site

In the PlateBridge UI or via database:

```sql
INSERT INTO sites (community_id, name, site_id, camera_ids, is_active)
VALUES (
  'your-community-uuid',
  'main-gate',
  'site-001',
  ARRAY['camera-1', 'camera-2'],
  true
);
```

### Step 2: Configure Pod to Poll API

Configure your pod device to:

1. **Poll for configuration changes:**
   - Call `GET /api/plates?site=main-gate&company_id=YOUR_COMPANY_ID`
   - Check `config_version` field
   - If version changed, refresh local plate database
   - Poll interval: 30-60 seconds recommended

2. **Send health updates:**
   - POST to a health endpoint (you may need to create this)
   - Include: status, cpu_usage, memory_usage, plates_detected_24h
   - Update interval: 60 seconds recommended

### Step 3: Add Plates via UI

Use the PlateBridge web interface:

1. Login to your deployed site
2. Navigate to Communities → Select your community
3. Go to Sites → Select your site
4. Add plates to the whitelist
5. Optionally call `/api/nudge` to force immediate sync

### Step 4: Monitor Pod Health

The dashboard displays:
- Total pods online/offline
- Plates detected (24h, 7d)
- Camera status
- Pod health metrics

## Example Pod Implementation (Pseudocode)

```python
import requests
import time

class PlateBridgePod:
    def __init__(self, api_base, site_name, company_id):
        self.api_base = api_base
        self.site_name = site_name
        self.company_id = company_id
        self.current_version = 0
        self.plates_cache = []

    def poll_config(self):
        """Poll for configuration updates"""
        url = f"{self.api_base}/api/plates"
        params = {
            "site": self.site_name,
            "company_id": self.company_id
        }

        response = requests.get(url, params=params)
        data = response.json()

        # Check if config version changed
        if data['config_version'] > self.current_version:
            print(f"Config updated: v{self.current_version} → v{data['config_version']}")
            self.current_version = data['config_version']
            self.plates_cache = data['entries']
            self.update_local_database()

    def update_local_database(self):
        """Update local SQLite/database with new plates"""
        # Clear old entries
        # Insert new entries from self.plates_cache
        pass

    def check_plate(self, plate_number):
        """Check if plate is in whitelist"""
        for entry in self.plates_cache:
            if entry['plate'].upper() == plate_number.upper():
                if entry['enabled']:
                    return True
        return False

    def run(self):
        """Main pod loop"""
        while True:
            try:
                # Poll for config updates every 30 seconds
                self.poll_config()
                time.sleep(30)
            except Exception as e:
                print(f"Error: {e}")
                time.sleep(60)

# Usage
pod = PlateBridgePod(
    api_base="https://your-domain.vercel.app",
    site_name="main-gate",
    company_id="6081bef5-f756-4dda-8b49-b7b5b140a959"
)
pod.run()
```

## Security Considerations

1. **HTTPS Only:** Always use HTTPS for API calls
2. **Company ID Verification:** Pods must know their company_id
3. **Site Name:** Must match exactly what's in the database
4. **Rate Limiting:** Implement reasonable polling intervals
5. **Error Handling:** Handle network errors gracefully

## Troubleshooting

### Pod Not Getting Plates

1. Verify site exists in database
2. Check company_id matches
3. Verify site name is exact match
4. Check that plates are enabled
5. Verify API endpoint is correct

### Configuration Not Updating

1. Check config_version is incrementing
2. Verify pod is polling regularly
3. Use `/api/nudge` to force update
4. Check pod logs for API errors

### Health Monitoring Not Working

You may need to create a POST endpoint for pod health updates:

```typescript
// app/api/pod-health/route.ts
export async function POST(request: NextRequest) {
  const body = await request.json();
  const { site_id, pod_name, status, cpu_usage, memory_usage } = body;

  // Upsert pod health record
  await supabase
    .from('pod_health')
    .upsert({
      site_id,
      pod_name,
      status,
      cpu_usage,
      memory_usage,
      last_checkin: new Date().toISOString()
    }, { onConflict: 'site_id,pod_name' });

  return NextResponse.json({ success: true });
}
```

## Next Steps

1. Deploy your Vercel app with environment variables
2. Create sites in the database
3. Configure your pod devices with the API endpoint
4. Test with `/api/plates` endpoint
5. Add plates via web UI
6. Monitor pod health in dashboard

## Support

For technical issues:
- Check API endpoint responses
- Verify database RLS policies allow access
- Review Vercel function logs
- Check pod device logs
