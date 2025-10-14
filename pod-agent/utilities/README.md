# PlateBridge POD Utilities

This folder contains utility scripts for troubleshooting and maintenance.

## Network & DHCP Troubleshooting

### `diagnose-dhcp.sh`
Comprehensive DHCP diagnostics - checks dnsmasq, ports, and network config.

### `diagnose-dhcp-simple.sh`
Quick DHCP check - verifies service status and listening ports.

### `basic-network-test.sh`
Tests basic network connectivity and interface configuration.

### `debug-dnsmasq-port.sh`
Debugs DNS and DHCP port conflicts.

## DHCP Fixes

### `fix-dhcp-enable.sh`
Enables and restarts DHCP service with proper configuration.

### `fix-dhcp-simple.sh`
Simple DHCP fix - stops conflicts and restarts service.

### `fix-dnsmasq.sh`
Reconfigures dnsmasq with proper settings.

### `fix-restart-loop.sh`
Fixes systemd restart loops for dnsmasq.

### `force-clean-dhcp.sh`
Nuclear option - completely resets DHCP configuration.

## Network Configuration

### `network-config.sh`
Interactive network configuration for dual-NIC setup.

### `setup-remote-access.sh`
Configures secure remote access (SSH, tunnels).

## Camera Discovery

### `discover-cameras.sh`
Scans network for IP cameras and tests RTSP streams.

## Legacy

### `setup.sh`
Original setup script (superseded by install-complete.sh).

## Usage

All scripts should be run with sudo:

```bash
sudo ./utilities/diagnose-dhcp.sh
sudo ./utilities/discover-cameras.sh
```
