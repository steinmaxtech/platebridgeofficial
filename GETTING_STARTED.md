# Getting Started with PlateBridge

This guide will walk you through setting up your first POD and getting plate detection working.

## Prerequisites

- Supabase project with database deployed
- Vercel deployment of PlateBridge portal
- Raspberry Pi or Linux device for POD
- Frigate NVR with license plate detection configured
- Camera with clear view of license plates

## Step 1: Portal Setup

### 1.1 Create Account

```bash
# Go to your portal URL
https://your-platebridge.vercel.app

# Sign up with email/password
# You'll be automatically assigned to a default company
```

### 1.2 Create Community

1. Login to portal
2. Go to **Communities** page
3. Click **Add Community**
4. Fill in:
   - Name: "Oak Ridge HOA"
   - Address: "123 Main St"
   - Timezone: Your timezone
5. Click **Create**

### 1.3 Create Site

1. Go to **Properties** page
2. Click **Add Site**
3. Fill in:
   - Community: Select your community
   - Name: "Main Gate"
   - Site ID: "main-gate"
4. Click **Create**

### 1.4 Create POD

1. Go to **PODs** page
2. Click **Add POD**
3. Fill in:
   - Name: "Main Gate POD"
   - Site: Select "Main Gate"
4. Click **Create**
5. **Copy the POD ID** - you'll need this

### 1.5 Generate POD API Key

1. Still on **PODs** page
2. Click **Generate API Key** for your POD
3. Fill in:
   - Name: "Main Gate POD Key"
   - Community: Your community
   - POD ID: Your POD ID
4. Click **Generate**
5. **IMPORTANT: Copy the API key immediately** (starts with `pbk_`)
6. You won't be able to see it again!

### 1.6 Create Camera

1. Go to **Cameras** page
2. Click **Add Camera**
3. Fill in:
   - Name: "Gate Camera 1"
   - POD: Select your POD
   - Stream URL: `https://pod-ip:8000/stream` (use your POD's IP)
   - Position: "Main entrance"
4. Click **Create**
5. **Copy the Camera ID**

### 1.7 Add Test Plate to Whitelist

1. Go to **Plates** page
2. Click **Add Plate**
3. Fill in:
   - Plate Number: "ABC123"
   - Community: Your community
   - Site: "Main Gate"
   - Unit: "101"
   - Tenant: "John Doe"
   - Vehicle: "Toyota Camry"
   - Enabled: ✅
5. Click **Save**

## Step 2: Frigate Setup

### 2.1 Configure License Plate Detection

Edit `/config/config.yml` on your Frigate server:

```yaml
mqtt:
  enabled: true
  host: localhost
  port: 1883

cameras:
  gate_camera:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://camera-ip:554/stream
          roles:
            - detect
            - record

    detect:
      enabled: true
      width: 1920
      height: 1080
      fps: 5

    objects:
      track:
        - license_plate
      filters:
        license_plate:
          min_score: 0.7

    record:
      enabled: true
      retain:
        days: 7

    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
```

### 2.2 Restart Frigate

```bash
docker restart frigate
# or
sudo systemctl restart frigate
```

### 2.3 Verify Detection

1. Open Frigate UI: `http://frigate-ip:5000`
2. Go to Events tab
3. Drive a car past the camera
4. Should see `license_plate` detections

## Step 3: POD Agent Installation

### 3.1 Download POD Agent

SSH to your Raspberry Pi or Linux device:

```bash
ssh pi@pod-ip

# Create directory
mkdir -p /opt/platebridge-pod
cd /opt/platebridge-pod

# Download files (from your portal or git repo)
wget https://your-portal/pod-agent/complete_pod_agent.py
wget https://your-portal/pod-agent/requirements.txt
wget https://your-portal/pod-agent/config.example.yaml
```

### 3.2 Install Dependencies

```bash
sudo apt update
sudo apt install -y python3-pip ffmpeg mosquitto-clients

pip3 install -r requirements.txt
```

### 3.3 Configure POD

```bash
cp config.example.yaml config.yaml
nano config.yaml
```

Update these values:

```yaml
# Portal connection
portal_url: "https://your-platebridge.vercel.app"
pod_api_key: "pbk_xxxxx"  # From step 1.5

# Pod identification
pod_id: "your-pod-id"  # From step 1.4
camera_id: "your-camera-uuid"  # From step 1.6

# Camera settings
camera_rtsp_url: "rtsp://camera-ip:554/stream"
min_confidence: 0.75

# Frigate integration
enable_mqtt: true
mqtt_host: "frigate-ip"  # Or localhost if on same machine
mqtt_port: 1883
mqtt_topic: "frigate/events"

frigate_url: "http://frigate-ip:5000"
save_snapshots: true

# Recording
record_on_detection: true
recordings_dir: "/var/lib/platebridge/recordings"
recording_duration: 30

# Streaming
enable_streaming: true
stream_port: 8000
stream_secret: "your-secret-here"  # Same as POD_STREAM_SECRET in Vercel
```

### 3.4 Create Recordings Directory

```bash
sudo mkdir -p /var/lib/platebridge/recordings
sudo chown $USER:$USER /var/lib/platebridge/recordings
```

### 3.5 Test POD Agent

```bash
python3 complete_pod_agent.py config.yaml
```

You should see:

```
============================================================
PlateBridge Complete Pod Agent
============================================================
Portal: https://your-platebridge.vercel.app
Pod ID: your-pod-id
Camera ID: your-camera-uuid
============================================================
Connected to Frigate MQTT broker
Subscribed to: frigate/events
Stream started successfully
Stream server running on port 8000
```

Press `Ctrl+C` to stop.

## Step 4: Test Detection

### 4.1 Run POD Agent

```bash
python3 complete_pod_agent.py config.yaml
```

### 4.2 Trigger Frigate Detection

Drive a car past the camera (or use a test image).

### 4.3 Check POD Logs

You should see:

```
[gate_camera] Plate detected: ABC123 (95.00%)
Saved snapshot: /var/lib/platebridge/recordings/123_snapshot.jpg
Recording clip...
Recorded: /var/lib/platebridge/recordings/recording_20251010_120000.mp4
Registering recording in portal: recording_20251010_120000.mp4
Recording registered successfully
```

### 4.4 Check Portal

1. Go to **Audit Logs** page
2. Should see detection event:
   - Plate: ABC123
   - Camera: Gate Camera 1
   - Action: gate_open
   - Result: allow

3. Go to **Cameras** → **Gate Camera 1** → **View Recordings**
4. Should see recording with snapshot

## Step 5: Setup as Service

### 5.1 Create Systemd Service

```bash
sudo nano /etc/systemd/system/platebridge-pod.service
```

```ini
[Unit]
Description=PlateBridge POD Agent
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/platebridge-pod
ExecStart=/usr/bin/python3 complete_pod_agent.py config.yaml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 5.2 Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable platebridge-pod
sudo systemctl start platebridge-pod
```

### 5.3 Check Status

```bash
sudo systemctl status platebridge-pod
sudo journalctl -u platebridge-pod -f
```

## Step 6: Test Live Streaming

### 6.1 Get Stream Token

In portal:
1. Go to **Cameras** page
2. Click on your camera
3. Click **View Live Stream**
4. Stream should load in browser

### 6.2 Test Direct Access

```bash
# Test POD health endpoint
curl http://pod-ip:8000/health

# Should return:
{
  "status": "ok",
  "pod_id": "your-pod-id",
  "streaming": true,
  "recording_count": 5
}
```

## Troubleshooting

### POD Not Connecting

**Check API key:**
```bash
# Test heartbeat endpoint
curl -X POST https://your-portal/api/pod/heartbeat \
  -H "Authorization: Bearer pbk_xxx" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Should return 200 OK.

**Check network:**
```bash
ping your-portal.vercel.app
```

### No Detections

**Check Frigate MQTT:**
```bash
mosquitto_sub -h frigate-ip -t "frigate/events" -v
```

Should see events when plates detected.

**Check POD logs:**
```bash
sudo journalctl -u platebridge-pod -f | grep -i plate
```

**Check Frigate UI:**
- Open `http://frigate-ip:5000`
- Go to Events
- Should see `license_plate` events

### Recordings Not Working

**Check RTSP stream:**
```bash
ffplay rtsp://camera-ip:554/stream
```

**Check recording directory:**
```bash
ls -la /var/lib/platebridge/recordings/
```

**Check disk space:**
```bash
df -h /var/lib/platebridge/recordings
```

### Stream Not Loading

**Check POD is accessible:**
```bash
curl http://pod-ip:8000/health
```

**Check firewall:**
```bash
sudo ufw allow 8000/tcp
```

**Check stream URL in camera config:**
- Should be: `https://pod-ip:8000/stream`
- Or use internal IP if on same network

## Next Steps

### Add More Plates

1. Go to **Plates** page
2. Bulk import CSV:
   ```csv
   plate,unit,tenant,vehicle,site_ids
   XYZ789,102,Jane Smith,Honda Civic,main-gate
   LMN456,103,Bob Jones,Ford F150,main-gate
   ```

### Add Gate Control

Integrate with Gatewise or custom hardware:

1. Go to **Settings** → **Gatewise Integration**
2. Enter API credentials
3. Map access points to sites
4. Test gate opening

### Monitor System

1. **Dashboard** - System overview
2. **Audit Logs** - All detections
3. **PODs** page - POD health and status
4. **Cameras** page - Camera status

### Setup Alerts

Coming soon:
- Email/SMS notifications
- Webhook integration
- Slack/Discord alerts

## Summary

✅ **Portal setup** - Company, community, site, POD, camera, whitelist
✅ **Frigate configured** - License plate detection enabled
✅ **POD agent running** - Connected to portal and Frigate
✅ **Test detection** - Plate detected, logged, recorded
✅ **Service running** - Auto-start on boot

Your PlateBridge system is now operational!
