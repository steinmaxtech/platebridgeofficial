# PlateBridge Pod Setup Guide

This guide will walk you through installing the PlateBridge agent on your Frigate-powered license plate detection device.

## Prerequisites

Before you begin, make sure you have:

- A Raspberry Pi or Linux computer running Frigate
- Frigate configured with license plate detection
- SSH access to the device
- Python 3.7 or higher installed
- Your PlateBridge portal URL (e.g., `https://your-portal.vercel.app`)

## What is a Pod?

A **pod** is the physical device at your gate that:
- Runs Frigate to detect license plates from cameras
- Runs the PlateBridge agent to communicate with your cloud portal
- Controls the gate via Gatewise or another system

## Quick Installation

### Option 1: Automated Setup (Recommended)

1. **Copy the agent files to your pod**

   ```bash
   # From your computer, copy the pod-agent folder to your device
   scp -r pod-agent/ pi@your-pod-ip:~/
   ```

2. **SSH into your pod**

   ```bash
   ssh pi@your-pod-ip
   ```

3. **Run the automated setup**

   ```bash
   cd ~/pod-agent
   chmod +x setup.sh
   ./setup.sh
   ```

4. **Follow the prompts** - you'll need:
   - Portal URL: Your PlateBridge website URL
   - API Key: Generate this from your portal's Settings page
   - Site ID: Your site's UUID from the portal
   - Pod ID: A unique name like "front-gate" or "main-entrance"

5. **Start the agent**

   ```bash
   sudo systemctl start platebridge-agent
   sudo systemctl enable platebridge-agent  # Auto-start on boot
   ```

6. **Check it's running**

   ```bash
   sudo systemctl status platebridge-agent
   sudo journalctl -u platebridge-agent -f  # View live logs
   ```

### Option 2: Manual Installation

If you prefer to set things up manually:

1. **Install dependencies**

   ```bash
   sudo apt-get update
   sudo apt-get install python3 python3-pip
   ```

2. **Create installation directory**

   ```bash
   mkdir -p ~/platebridge-agent
   cd ~/platebridge-agent
   ```

3. **Copy files**

   Copy `agent.py`, `requirements.txt`, and `config.example.yaml` to this directory.

4. **Install Python packages**

   ```bash
   pip3 install -r requirements.txt
   ```

5. **Create configuration**

   ```bash
   cp config.example.yaml config.yaml
   nano config.yaml  # Edit with your settings
   ```

6. **Test the agent**

   ```bash
   python3 agent.py config.yaml
   ```

   Press Ctrl+C to stop when you're done testing.

7. **Create systemd service**

   ```bash
   sudo nano /etc/systemd/system/platebridge-agent.service
   ```

   Paste this content:

   ```ini
   [Unit]
   Description=PlateBridge Pod Agent
   After=network.target

   [Service]
   Type=simple
   User=pi
   WorkingDirectory=/home/pi/platebridge-agent
   ExecStart=/usr/bin/python3 /home/pi/platebridge-agent/agent.py /home/pi/platebridge-agent/config.yaml
   Restart=always
   RestartSec=10
   StandardOutput=journal
   StandardError=journal

   [Install]
   WantedBy=multi-user.target
   ```

8. **Enable and start the service**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable platebridge-agent
   sudo systemctl start platebridge-agent
   ```

## Getting Your Configuration Values

### Portal URL
Your PlateBridge website URL (e.g., `https://platebridge.vercel.app`)

### API Key
1. Log into your PlateBridge portal
2. Go to Settings
3. Navigate to "API Keys" section
4. Click "Generate Pod API Key"
5. Copy the key (you won't see it again!)

### Site ID
1. Log into your PlateBridge portal
2. Go to "Sites" or "Properties"
3. Find your site in the list
4. Copy the Site ID (UUID format)

### Pod ID
A friendly name for this specific pod, like:
- `front-gate`
- `back-entrance`
- `visitor-parking`

## Configuration Options

Edit `config.yaml` to customize behavior:

```yaml
# How often to refresh the whitelist from the portal (seconds)
whitelist_refresh_interval: 300

# Minimum confidence score to process a detection (0.0 - 1.0)
min_confidence: 0.7

# Frigate MQTT settings
frigate_mqtt_host: "localhost"
frigate_mqtt_port: 1883
frigate_mqtt_topic: "frigate/events"
```

## Troubleshooting

### Agent won't start

**Check Python version:**
```bash
python3 --version  # Should be 3.7+
```

**Check dependencies:**
```bash
pip3 install -r requirements.txt
```

**Check config file:**
```bash
cat config.yaml  # Make sure all values are filled in
```

### Not receiving detections

**Check Frigate is running:**
```bash
docker ps | grep frigate
```

**Check MQTT connection:**
```bash
mosquitto_sub -h localhost -t "frigate/events"
```

You should see events when plates are detected.

**Check agent logs:**
```bash
sudo journalctl -u platebridge-agent -f
```

Look for "License plate detected" messages.

### Portal communication failing

**Test internet connection:**
```bash
ping your-portal-domain.vercel.app
```

**Test API endpoint:**
```bash
curl -X POST https://your-portal.vercel.app/api/pod/detect \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "pod_id": "test",
    "site_id": "your-site-id",
    "license_plate": "TEST123",
    "confidence": 0.95
  }'
```

**Check API key:**
Make sure your API key is correct and hasn't expired.

### Gate not opening

**Check Gatewise integration:**
1. Log into your portal
2. Go to Settings → Gatewise
3. Verify your Gatewise credentials are correct
4. Test the connection

**Check audit logs:**
1. Log into your portal
2. Go to Audit Logs
3. Look for your recent detections
4. Check the action and gate_opened fields

## How It Works

1. **Frigate detects a license plate** and publishes an MQTT event
2. **PlateBridge agent receives** the MQTT event
3. **Agent checks local cache** first (works offline!)
4. **Agent sends to portal** for verification and logging
5. **Portal responds** with allow/deny decision
6. **If allowed**, portal triggers Gatewise to open the gate
7. **Agent logs** the result locally

## Monitoring

### View live logs
```bash
sudo journalctl -u platebridge-agent -f
```

### Check service status
```bash
sudo systemctl status platebridge-agent
```

### View whitelist cache
```bash
cat ~/platebridge-agent/whitelist_cache.json
```

### Restart the service
```bash
sudo systemctl restart platebridge-agent
```

### Stop the service
```bash
sudo systemctl stop platebridge-agent
```

## Updating the Agent

1. **Stop the service**
   ```bash
   sudo systemctl stop platebridge-agent
   ```

2. **Backup your config**
   ```bash
   cp ~/platebridge-agent/config.yaml ~/config.yaml.backup
   ```

3. **Copy new files**
   ```bash
   scp -r pod-agent/ pi@your-pod-ip:~/platebridge-agent-new/
   ```

4. **Replace agent.py**
   ```bash
   cp ~/platebridge-agent-new/agent.py ~/platebridge-agent/
   ```

5. **Restore config**
   ```bash
   cp ~/config.yaml.backup ~/platebridge-agent/config.yaml
   ```

6. **Restart service**
   ```bash
   sudo systemctl start platebridge-agent
   ```

## Security Notes

- **Keep your API key secret** - it grants full access to your pod's site
- **Use HTTPS** - always use `https://` for your portal URL
- **Firewall** - restrict outbound traffic to only your portal domain
- **Regular updates** - keep Python and dependencies updated

## Support

If you run into issues:

1. Check the logs: `sudo journalctl -u platebridge-agent -f`
2. Verify your configuration in `config.yaml`
3. Test the portal API endpoints manually
4. Check Frigate is detecting plates correctly

## Multiple Pods

To set up multiple pods at the same site:

1. Install the agent on each device
2. Use the **same** `site_id` for all pods at that location
3. Use **different** `pod_id` values (e.g., "front-gate", "back-gate")
4. Each pod will share the same whitelist but report separately

## Next Steps

Once your pod is running:

1. Test with a known license plate
2. Watch the logs to see detections
3. Check the portal's Audit Logs page
4. Add more plates to your whitelist
5. Set up email notifications in the portal
