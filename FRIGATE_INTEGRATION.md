# Frigate Integration Guide

## Overview

PlateBridge integrates seamlessly with [Frigate NVR](https://frigate.video/) for license plate detection and recording.

**How it works:**
1. Frigate detects license plates using AI
2. Frigate publishes events to MQTT
3. PlateBridge POD agent listens to MQTT
4. Agent checks whitelist and opens gate automatically
5. Agent records clip and retrieves snapshot from Frigate

## Architecture

```
┌──────────────────────────────────────────────┐
│              Frigate NVR                     │
│                                              │
│  ┌─────────┐      ┌──────────┐             │
│  │ Camera  │─────→│ License  │             │
│  │ Stream  │      │  Plate   │             │
│  │ (RTSP)  │      │  Detect  │             │
│  └─────────┘      └──────────┘             │
│                         │                    │
│                         ↓                    │
│                   MQTT Broker                │
│                   (events)                   │
└──────────────────────────────────────────────┘
              │                    ↑
              │ frigate/events     │ Snapshot API
              ↓                    │
┌──────────────────────────────────────────────┐
│         PlateBridge POD Agent                │
│                                              │
│  ├─ MQTT Listener                           │
│  ├─ Whitelist Checker                       │
│  ├─ Detection Logger                         │
│  ├─ Clip Recorder                           │
│  └─ Snapshot Downloader                     │
└──────────────────────────────────────────────┘
              │
              ↓
┌──────────────────────────────────────────────┐
│           Portal + Database                  │
│  - Audit logs                               │
│  - Gate control                             │
│  - Recording metadata                       │
└──────────────────────────────────────────────┘
```

## Prerequisites

1. **Frigate NVR installed and running**
   - Version 0.12.0 or later recommended
   - MQTT enabled
   - License plate detection configured

2. **MQTT Broker**
   - Usually included with Frigate
   - Or standalone Mosquitto

3. **Camera with license plate view**
   - Clear view of plates
   - Good lighting
   - Appropriate resolution (1080p+)

## Frigate Configuration

### 1. Configure License Plate Detection

Edit your Frigate config (`/config/config.yml`):

```yaml
mqtt:
  enabled: true
  host: localhost  # Or your MQTT broker
  port: 1883
  # user: username  # Optional
  # password: password  # Optional

cameras:
  front_gate:
    enabled: true
    ffmpeg:
      inputs:
        - path: rtsp://192.168.1.100:554/stream
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

    record:
      enabled: true
      retain:
        days: 7
      events:
        retain:
          default: 14
          mode: active_objects

    snapshots:
      enabled: true
      timestamp: true
      bounding_box: true
      crop: false
      retain:
        default: 14
```

### 2. Add License Plate Model

Frigate needs a license plate detection model. Add to config:

```yaml
model:
  path: /config/model_cache/yolov7-320.tflite
  labelmap_path: /labelmap.txt
  width: 320
  height: 320

# For license plates, you may need a custom model
# See: https://frigate.video/plus
```

**Option A: Frigate+ (Recommended)**
- Subscribe to Frigate+
- Get access to license plate models
- Automatic model updates

**Option B: Custom Model**
- Train your own YOLOv7 model
- Place in `/config/model_cache/`
- Update labelmap with `license_plate` label

### 3. Configure Sub-labels for Plates

```yaml
cameras:
  front_gate:
    objects:
      track:
        - license_plate
      filters:
        license_plate:
          min_score: 0.7  # Confidence threshold
          threshold: 0.85
```

## PlateBridge POD Configuration

### 1. Install Dependencies

POD agent already includes everything needed:

```bash
# Already in requirements.txt:
# - paho-mqtt (for MQTT)
# - requests (for Frigate API)
```

### 2. Configure config.yaml

```yaml
# Portal connection
portal_url: "https://your-portal.vercel.app"
pod_api_key: "pbk_your_api_key_here"

# Pod identification
pod_id: "main-gate-pod"
camera_id: "your-camera-uuid"

# Camera settings
camera_rtsp_url: "rtsp://192.168.1.100:554/stream"
min_confidence: 0.75

# Frigate integration
enable_mqtt: true
mqtt_host: "localhost"  # Frigate's MQTT broker
mqtt_port: 1883
mqtt_topic: "frigate/events"

frigate_url: "http://localhost:5000"  # Frigate API
save_snapshots: true  # Download snapshots

# Recording
record_on_detection: true
recordings_dir: "/var/lib/platebridge/recordings"
recording_duration: 30
```

### 3. Start POD Agent

```bash
sudo python3 complete_pod_agent.py config.yaml
```

## How Detection Works

### MQTT Event Flow

When Frigate detects a license plate:

**1. Frigate publishes MQTT event:**
```json
{
  "type": "new",
  "after": {
    "id": "1696800000.123456-abc123",
    "camera": "front_gate",
    "label": "license_plate",
    "sub_label": "ABC123",
    "score": 0.95,
    "area": 12345,
    "box": [100, 200, 300, 400],
    "snapshot": {
      "path": "/media/frigate/clips/snapshot.jpg"
    }
  }
}
```

**2. POD agent receives event:**
```python
# Agent filters for license_plate events
if label.lower() == 'license_plate':
    plate = event.get('sub_label', '')  # ABC123
    confidence = event.get('score', 0.0)  # 0.95
```

**3. Agent checks confidence:**
```python
if confidence >= min_confidence:  # 0.75
    # Process detection
```

**4. Agent retrieves snapshot:**
```python
snapshot = get_frigate_snapshot(event_id)
# GET http://localhost:5000/api/events/{event_id}/snapshot.jpg
```

**5. Agent checks whitelist:**
```python
if is_plate_whitelisted(plate):
    decision = 'allow'
else:
    decision = 'deny'
```

**6. Agent sends to portal:**
```python
await send_detection(plate, confidence)
# Portal logs audit and opens gate if allowed
```

**7. Agent records clip:**
```python
clip_path = record_clip(duration=30)
await register_recording(clip_path, plate, snapshot)
```

## Frigate Event Types

POD agent handles these Frigate events:

### `type: "new"`
New object detected. Agent processes immediately.

```json
{
  "type": "new",
  "after": {
    "label": "license_plate",
    "sub_label": "ABC123",
    "score": 0.95
  }
}
```

### `type: "update"`
Object still being tracked (ignored by default).

### `type: "end"`
Object tracking ended. Agent logs for debugging.

```json
{
  "type": "end",
  "before": {
    "id": "event-id",
    "label": "license_plate"
  }
}
```

## Snapshot Handling

### Automatic Download

When `save_snapshots: true`, agent automatically:

1. Gets event ID from Frigate MQTT
2. Calls Frigate API: `/api/events/{id}/snapshot.jpg`
3. Saves to: `/recordings/{event_id}_snapshot.jpg`
4. Registers snapshot with recording

### Manual Snapshot Access

Snapshots stored locally on POD:

```bash
# List snapshots
ls -lh /var/lib/platebridge/recordings/*_snapshot.jpg

# View snapshot
firefox /var/lib/platebridge/recordings/1696800000.123456_snapshot.jpg
```

### Snapshot in Portal

Portal serves snapshots via POD:

```
GET https://pod-ip:8000/thumbnail/{recording_id}?token=xxx
```

Browser displays snapshot in recordings list.

## Testing Integration

### 1. Test MQTT Connection

```bash
# Subscribe to Frigate events
mosquitto_sub -h localhost -t "frigate/events" -v

# You should see events when plates detected
```

### 2. Test POD Agent

```bash
# Run agent with debug logging
sudo python3 complete_pod_agent.py config.yaml

# Watch for:
# "Connected to Frigate MQTT broker"
# "Subscribed to: frigate/events"
```

### 3. Trigger Detection

Drive a car past the camera or use a test image:

```bash
# Check POD logs
sudo journalctl -u platebridge-pod -f | grep -i plate

# Should see:
# "Plate detected: ABC123 (95.00%)"
# "Saved snapshot: /recordings/xxx_snapshot.jpg"
# "Recording clip..."
# "Recording registered successfully"
```

### 4. Verify in Portal

1. Login to portal
2. Go to Audit Logs
3. Should see detection with plate number
4. Go to Cameras → View Recordings
5. Should see recording with snapshot

## Troubleshooting

### No Events Received

**Check MQTT connection:**
```bash
# Test MQTT broker
mosquitto_sub -h localhost -t "frigate/events"

# Should see JSON events when plates detected
```

**Check POD logs:**
```bash
sudo journalctl -u platebridge-pod -f

# Look for:
# "Connected to MQTT broker" - Good!
# "MQTT connection failed" - Check mqtt_host and mqtt_port
```

**Check Frigate MQTT:**
```bash
# Verify MQTT enabled in Frigate
curl http://localhost:5000/api/config | jq '.mqtt'

# Should show: {"enabled": true, "host": "..."}
```

### Plates Not Detected

**Check Frigate is detecting:**
```bash
# Open Frigate UI
open http://localhost:5000

# Go to Events tab
# Should see license_plate detections
```

**Check confidence threshold:**
```yaml
# In config.yaml, lower threshold:
min_confidence: 0.5  # Was 0.75
```

**Check MQTT topic:**
```bash
# Verify correct topic
mosquitto_sub -h localhost -t "#" -v | grep license_plate
```

### Snapshots Not Saving

**Check Frigate URL:**
```bash
# Test Frigate API
curl http://localhost:5000/api/events

# Should return JSON with events
```

**Check event ID:**
POD logs should show:
```
Saved snapshot: /recordings/1696800000.123456_snapshot.jpg
```

If not, check `frigate_url` in config.yaml.

**Verify snapshots enabled:**
```yaml
# In Frigate config:
cameras:
  front_gate:
    snapshots:
      enabled: true
```

### Recordings Not Working

**Check RTSP URL:**
```bash
# Test RTSP stream
ffplay rtsp://192.168.1.100:554/stream

# Press Q to quit
```

**Check recording directory:**
```bash
# Verify writable
ls -ld /var/lib/platebridge/recordings

# Should be: drwxr-xr-x pi pi
```

**Check disk space:**
```bash
df -h /var/lib/platebridge/recordings
```

## Advanced Configuration

### Multiple Cameras

One POD can monitor multiple Frigate cameras:

```yaml
# Run separate agent per camera
# config_camera1.yaml
camera_id: "camera-1-uuid"
mqtt_topic: "frigate/events"
# Filter in code by camera name

# config_camera2.yaml
camera_id: "camera-2-uuid"
mqtt_topic: "frigate/events"
```

Or filter in agent code:

```python
def on_mqtt_message(self, msg):
    event = json.loads(msg)
    camera = event['after']['camera']

    # Only process specific camera
    if camera == self.config['frigate_camera_name']:
        # Process...
```

### Custom MQTT Topics

Frigate publishes to several topics:

- `frigate/events` - All events (default)
- `frigate/{camera}/events` - Per-camera events
- `frigate/available` - Status updates

Subscribe to specific camera:

```yaml
mqtt_topic: "frigate/front_gate/events"
```

### Region of Interest (ROI)

Configure Frigate to only detect in specific area:

```yaml
cameras:
  front_gate:
    zones:
      entry_zone:
        coordinates: 0,400,1000,400,1000,600,0,600

    objects:
      filters:
        license_plate:
          mask: entry_zone  # Only detect in this zone
```

### Time-Based Rules

Only process detections during certain times:

```python
from datetime import datetime

def on_mqtt_message(self, msg):
    # Only process 6 AM - 10 PM
    hour = datetime.now().hour
    if not (6 <= hour <= 22):
        return

    # Process detection...
```

Or configure in portal per site/community.

## Performance Tips

### Reduce False Positives

```yaml
# In Frigate config
cameras:
  front_gate:
    objects:
      filters:
        license_plate:
          min_score: 0.8  # Higher threshold
          min_area: 5000  # Minimum pixel area
```

### Optimize Recording

```yaml
# Shorter clips for faster processing
recording_duration: 15  # seconds

# Or disable if not needed
record_on_detection: false
```

### Reduce Snapshot Size

```yaml
# In Frigate config
cameras:
  front_gate:
    snapshots:
      height: 720  # Lower resolution
      quality: 70  # JPEG quality
```

## Production Deployment

### Systemd Service

```ini
[Unit]
Description=PlateBridge Pod Agent (Frigate)
After=network.target frigate.service
Wants=frigate.service

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

### Health Monitoring

Add to cron for health checks:

```bash
# /etc/cron.d/platebridge-health
*/5 * * * * pi curl -s http://localhost:8000/health || systemctl restart platebridge-pod
```

### Log Rotation

```bash
# /etc/logrotate.d/platebridge
/var/log/platebridge/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

## Summary

✅ **Frigate detects plates** using AI
✅ **POD agent listens** via MQTT
✅ **Automatic whitelist check** and gate control
✅ **Clips recorded** from RTSP
✅ **Snapshots downloaded** from Frigate API
✅ **Metadata registered** in portal

Perfect integration for automated license plate recognition and access control!
