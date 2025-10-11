# 🔧 POD Registration to Site - Complete Guide

## How a POD Registers to a Specific Site

---

## 📋 Overview

A POD can register to a site using **multiple methods**, all using the same API endpoint:

**Endpoint:** `POST /api/pods/register`

**Required Parameters:**
- `serial` - POD serial number
- `mac` - MAC address
- `model` - Hardware model (e.g., "PB-M1")
- `version` - Software version
- **Either** `site_id` OR `community_id`

---

## 🎯 Registration Methods

### **Method 1: QR Code Scan (Recommended) ⭐**

**Best for:** Field installation by technicians

**How it works:**

1. **Admin generates QR code** in portal:
   - Navigate to site detail page
   - Display QR code containing site configuration

2. **Installer scans QR code:**
   - Use POD's camera
   - Or use mobile app
   - Or manual entry from displayed data

3. **POD auto-registers:**
   ```bash
   # POD extracts site_id from QR code and calls:
   curl -X POST https://portal/api/pods/register \
     -H "Content-Type: application/json" \
     -d '{
       "serial": "PB-2025-0012",
       "mac": "b8:27:eb:fa:ce:01",
       "model": "PB-M1",
       "version": "1.0.0",
       "site_id": "abc-123-from-qr"
     }'
   ```

**QR Code Content:**
```json
{
  "site_id": "abc-123-def-456",
  "site_name": "Main Entrance",
  "community_id": "xyz-789",
  "community_name": "Sunset Villas",
  "portal_url": "https://portal.platebridge.io",
  "version": "1.0"
}
```

**Portal Page Created:** `/sites/[id]` - Shows QR code and site info

---

### **Method 2: WiFi Setup Interface**

**Best for:** On-site configuration

**How it works:**

1. **POD boots in setup mode:**
   ```
   POD creates WiFi hotspot: "PlateBridge-Setup-XXXX"
   ```

2. **Installer connects to WiFi:**
   - Connect phone/laptop to POD's WiFi
   - Browser auto-opens to http://192.168.4.1

3. **Setup page displays:**
   ```html
   <form>
     <label>Portal URL</label>
     <input value="https://portal.platebridge.io" />

     <label>Site ID</label>
     <input placeholder="Enter site ID from portal" />

     <button>Register POD</button>
   </form>
   ```

4. **POD registers with entered site_id**

---

### **Method 3: Pre-Configuration via USB**

**Best for:** Bulk deployment

**How it works:**

1. **Admin creates config file:**
   ```yaml
   # config.yaml
   portal_url: https://portal.platebridge.io
   site_id: abc-123-def-456
   community_id: xyz-789
   api_key: "" # Left blank, generated during registration
   ```

2. **USB drive loaded on POD:**
   - POD reads `/mnt/usb/config.yaml` on boot
   - Auto-registers using config

3. **POD saves returned API key:**
   - Updates config.yaml with received API key
   - Writes to local storage

---

### **Method 4: Installation Script**

**Best for:** SSH installation

**How it works:**

```bash
#!/bin/bash
# install-pod.sh

# Configuration
PORTAL_URL="https://portal.platebridge.io"
SITE_ID="abc-123-def-456"  # Provided by installer

# Get hardware info
SERIAL=$(cat /sys/class/dmi/id/product_serial)
MAC=$(cat /sys/class/net/eth0/address)

# Register POD
RESPONSE=$(curl -s -X POST "$PORTAL_URL/api/pods/register" \
  -H "Content-Type: application/json" \
  -d "{
    \"serial\": \"$SERIAL\",
    \"mac\": \"$MAC\",
    \"model\": \"PB-M1\",
    \"version\": \"1.0.0\",
    \"site_id\": \"$SITE_ID\"
  }")

# Extract API key and POD ID
API_KEY=$(echo $RESPONSE | jq -r '.api_key')
POD_ID=$(echo $RESPONSE | jq -r '.pod_id')

# Save to config
cat > /opt/platebridge/config.yaml <<EOF
pod_id: $POD_ID
api_key: $API_KEY
portal_url: $PORTAL_URL
site_id: $SITE_ID
EOF

# Download docker-compose.yml
curl -o docker-compose.yml "$PORTAL_URL/api/pods/config/$POD_ID?format=compose"

# Start services
docker-compose up -d

echo "✅ POD registered successfully!"
echo "POD ID: $POD_ID"
```

---

### **Method 5: Portal Pre-Registration**

**Best for:** Centralized management

**How it works:**

1. **Admin creates POD in portal first:**
   ```
   Navigate to: /pods/new

   Form:
   - POD Name: "Main Gate POD"
   - Serial Number: "PB-2025-0012"
   - Site: [Select from dropdown]
   - Status: "Pending"
   ```

2. **Portal creates POD record:**
   ```sql
   INSERT INTO pods (name, serial_number, site_id, status)
   VALUES ('Main Gate POD', 'PB-2025-0012', 'abc-123', 'pending');
   ```

3. **POD boots and registers:**
   ```bash
   # POD only sends serial number
   curl -X POST https://portal/api/pods/register \
     -d '{"serial": "PB-2025-0012", "mac": "..."}'
   ```

4. **Portal matches by serial:**
   - Finds existing POD record
   - Updates status to "online"
   - Returns configuration
   - **Does NOT return new API key** (already created)

---

## 📊 Registration Endpoint Logic

### Current Implementation:

```typescript
POST /api/pods/register

// Accepts:
{
  serial: string,      // Required
  mac: string,         // Required
  model?: string,      // Optional, defaults to "PB-M1"
  version?: string,    // Optional, defaults to "1.0.0"
  site_id?: string,    // Either site_id OR community_id required
  community_id?: string
}

// Logic:
1. Validate serial + mac
2. Require either site_id or community_id
3. If site_id provided, lookup community_id from sites table
4. Check if POD already exists (by serial_number)
5. If exists:
   - Update last_heartbeat, status, metrics
   - Return message: "Already registered, use existing API key"
6. If new:
   - Generate API key (pb_[64 hex chars])
   - Create POD record in database
   - Create API key record
   - Return API key + config

// Returns:
{
  pod_id: "uuid",
  api_key: "pb_xxx",  // Only for new registrations
  docker_compose_url: "https://portal/api/pods/config/uuid",
  env: {
    PLATEBRIDGE_API: "...",
    POD_ID: "...",
    SITE_ID: "...",
    COMMUNITY_ID: "..."
  },
  message: "POD registered successfully"
}
```

---

## 🗄️ Database Flow

### Registration Creates:

**1. Record in `pods` table:**
```sql
INSERT INTO pods (
  id,
  site_id,
  name,
  serial_number,
  mac_address,
  hardware_model,
  software_version,
  api_key_hash,
  status,
  last_heartbeat
) VALUES (
  gen_random_uuid(),
  'site-uuid',
  'POD-PB-2025-0012',
  'PB-2025-0012',
  'b8:27:eb:fa:ce:01',
  'PB-M1',
  '1.0.0',
  'sha256_hash_of_api_key',
  'online',
  now()
);
```

**2. Record in `pod_api_keys` table:**
```sql
INSERT INTO pod_api_keys (
  id,
  name,
  community_id,
  pod_id,
  key_hash,
  created_by
) VALUES (
  gen_random_uuid(),
  'PB-2025-0012 Registration Key',
  'community-uuid',
  'PB-2025-0012',
  'sha256_hash',
  'user-uuid'
);
```

### Lookup Relationships:

```
site_id (provided)
  ↓
sites table
  ↓
community_id
  ↓
communities table
  ↓
company_id
  ↓
Access control via memberships
```

---

## 🔐 Security Flow

### API Key Generation:

```javascript
// Generate random 32-byte key
const apiKey = `pb_${crypto.randomBytes(32).toString('hex')}`;
// Example: pb_a1b2c3d4e5f6...

// Hash for storage
const keyHash = crypto.createHash('sha256')
  .update(apiKey)
  .digest('hex');

// Store hash in database
// Return plaintext key ONCE to POD
```

### Subsequent Requests:

```javascript
// POD sends API key in header
Authorization: Bearer pb_a1b2c3d4e5f6...

// Portal validates:
1. Hash the received key
2. Look up hash in pod_api_keys table
3. Check if key is revoked (revoked_at IS NULL)
4. Update last_used_at
5. Allow/deny request
```

---

## 🎨 UI Features Created

### Site Detail Page: `/sites/[id]`

**Features:**
- ✅ Site information display
- ✅ QR code generation for POD registration
- ✅ Copy-to-clipboard for site ID
- ✅ Three registration methods documented
- ✅ cURL command generator

**Screenshot Layout:**
```
┌─────────────────────────────────────┐
│ Site Information        QR Code     │
│ ├─ Site ID              ┌─────────┐ │
│ ├─ Site Code            │ QR HERE │ │
│ └─ Community ID         └─────────┘ │
├─────────────────────────────────────┤
│ Registration Instructions            │
│ ├─ Method 1: QR Code                │
│ ├─ Method 2: Manual Entry           │
│ └─ Method 3: API Call               │
└─────────────────────────────────────┘
```

**Access:**
```
/sites/[site-uuid]
```

---

## 📝 Example: Complete Registration Flow

### Step-by-Step: Installing POD at "Main Entrance"

**1. Admin prepares in portal:**
```
Navigate to: /properties
Find site: "Main Entrance"
Click: "View Details"
Portal displays: QR code + site ID
```

**2. Technician arrives on-site:**
```
Unbox POD
Power on device
Wait for "Ready for setup" LED
```

**3. Registration (choose one method):**

**Option A: QR Code**
```
Open mobile app
Scan QR code from portal
App configures POD automatically
```

**Option B: WiFi Setup**
```
Connect to "PlateBridge-Setup-1234"
Browser opens setup page
Enter site ID: abc-123-def
Click "Register"
```

**Option C: SSH Script**
```bash
ssh tech@pod-ip
sudo ./install-pod.sh --site-id abc-123-def
```

**4. POD calls registration endpoint:**
```bash
POST /api/pods/register
{
  "serial": "PB-2025-0012",
  "mac": "b8:27:eb:fa:ce:01",
  "model": "PB-M1",
  "version": "1.0.0",
  "site_id": "abc-123-def"
}
```

**5. Portal responds:**
```json
{
  "pod_id": "new-uuid-generated",
  "api_key": "pb_32byte_hex_key",
  "docker_compose_url": "https://portal/api/pods/config/new-uuid",
  "env": {
    "POD_ID": "new-uuid-generated",
    "SITE_ID": "abc-123-def",
    "SITE_NAME": "Main Entrance",
    "COMMUNITY_ID": "xyz-789",
    "COMMUNITY_NAME": "Sunset Villas"
  }
}
```

**6. POD saves config:**
```bash
# POD downloads compose file
curl -o docker-compose.yml \
  "https://portal/api/pods/config/new-uuid?format=compose"

# POD starts services
docker-compose up -d

# POD sends first heartbeat
curl -X POST https://portal/api/pod/heartbeat \
  -H "Authorization: Bearer pb_32byte_hex_key" \
  -d '{"pod_id": "new-uuid", "status": "online"}'
```

**7. Verification:**
```
Admin opens: /pods
Sees: "POD-Main-Entrance" - Status: Online
Click: "View Details"
Confirms: Cameras connected, metrics reporting
```

---

## ✅ Registration Checklist

**Portal Setup:**
- [x] Registration endpoint created
- [x] Site detail page with QR code
- [x] API key generation working
- [x] Site lookup from site_id
- [x] Database records created

**POD Requirements:**
- [ ] Read QR code (camera or manual)
- [ ] WiFi setup interface
- [ ] Call registration endpoint
- [ ] Store API key securely
- [ ] Download docker-compose.yml
- [ ] Start services
- [ ] Send first heartbeat

---

## 🚀 Ready to Deploy

All portal infrastructure is complete! The POD agent now needs to:

1. Implement QR code scanning OR WiFi setup interface
2. Call `/api/pods/register` with site_id
3. Store returned API key
4. Download configuration files
5. Start services and begin heartbeat loop

**The portal is ready to register PODs! 🎉**
