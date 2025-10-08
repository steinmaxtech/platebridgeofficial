# PlateBridge Pod Agent

Connect your Frigate license plate detection system to the PlateBridge cloud portal.

## Quick Start

```bash
# 1. Copy this folder to your pod device
scp -r pod-agent/ pi@your-pod-ip:~/

# 2. SSH into your pod
ssh pi@your-pod-ip

# 3. Run setup
cd ~/pod-agent
chmod +x setup.sh
./setup.sh

# 4. Start the agent
sudo systemctl start platebridge-agent
sudo systemctl enable platebridge-agent
```

## What This Does

- Watches Frigate for license plate detections
- Sends detections to your PlateBridge portal
- Receives allow/deny decisions
- Triggers gate opening for authorized plates
- Caches whitelist locally for offline operation
- Auto-reconnects if network drops

## Requirements

- Python 3.7+
- Frigate with MQTT enabled
- Network access to your PlateBridge portal

## Files

- `agent.py` - Main agent script
- `setup.sh` - Automated installation script
- `config.example.yaml` - Configuration template
- `requirements.txt` - Python dependencies
- `README.md` - This file

## Documentation

See [POD_SETUP_GUIDE.md](../POD_SETUP_GUIDE.md) for detailed installation and troubleshooting instructions.

## Configuration

After running setup, edit `config.yaml`:

```yaml
portal_url: "https://your-portal.vercel.app"
api_key: "your-api-key"
site_id: "your-site-id"
pod_id: "front-gate"
```

## Commands

```bash
# View logs
sudo journalctl -u platebridge-agent -f

# Check status
sudo systemctl status platebridge-agent

# Restart
sudo systemctl restart platebridge-agent

# Stop
sudo systemctl stop platebridge-agent
```

## Support

Check logs first:
```bash
sudo journalctl -u platebridge-agent -f
```

Look for:
- "Connected to Frigate MQTT broker" - MQTT is working
- "License plate detected" - Frigate is sending events
- "Portal response" - Communication with portal is working
- "GATE OPENED" - Gate control is working
