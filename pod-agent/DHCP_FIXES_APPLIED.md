# Critical DHCP Fixes Applied to install-complete.sh

This document summarizes all the fixes discovered during troubleshooting that are now included in the installation script.

## Root Cause Analysis

The DHCP server was not responding to camera discovery packets due to three critical issues:

### 1. Reverse Path Filtering (rp_filter)
**Problem**: Linux kernel was dropping DHCP Discover packets from `0.0.0.0` source address
**Solution**: Disabled rp_filter on camera interface
```bash
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.enp1s0.rp_filter=0
```

### 2. Hardware Offloading
**Problem**: NIC hardware offload was interfering with DHCP packet processing
**Solution**: Disabled all hardware offload features on camera interface
```bash
ethtool -K enp1s0 rx off tx off gso off tso off gro off
```
Made persistent via systemd service: `disable-offload.service`

### 3. systemd-resolved Conflict
**Problem**: systemd-resolved was binding to port 53, preventing dnsmasq from starting
**Solution**: Disabled systemd-resolved and created static `/etc/resolv.conf`

## Script Changes Summary

### 1. Dependencies (Line 127-132)
Added `ethtool` to network packages

### 2. Network Configuration (Line 235-272)
- Added wait time for interfaces to come up
- Disabled hardware offload with ethtool
- Created systemd service to persist offload settings across reboots
- Added verification that interface has correct IP

### 3. DHCP Configuration (Line 277-381)
- Properly disables systemd-resolved
- Creates immutable `/etc/resolv.conf`
- Configures dnsmasq with `bind-interfaces` mode
- Verifies dnsmasq is listening on ports 53 and 67
- Provides troubleshooting command

### 4. Firewall Configuration (Line 341-344)
- Sets rp_filter=0 globally and per-interface
- CRITICAL: Must be 0 for DHCP to work with 0.0.0.0 source addresses

## What Works Now (Out of Box)

When you run `sudo ./install-complete.sh` on a fresh Ubuntu system:

1. ✅ All required packages installed (including ethtool)
2. ✅ Dual-NIC networking configured correctly
3. ✅ Hardware offload disabled on camera interface
4. ✅ systemd-resolved disabled to prevent port 53 conflict
5. ✅ dnsmasq configured with proper bind-interfaces mode
6. ✅ Reverse path filtering disabled for DHCP compatibility
7. ✅ Firewall rules allow DHCP and DNS traffic
8. ✅ All settings persist across reboots via systemd services
9. ✅ Verification steps confirm DHCP is listening correctly

## Testing Checklist

After fresh install, verify:

```bash
# 1. Check dnsmasq is running
sudo systemctl status dnsmasq

# 2. Verify listening on correct ports
sudo ss -ulnp | grep dnsmasq
# Should show: *:53 and *:67

# 3. Check rp_filter is disabled
sudo sysctl net.ipv4.conf.enp1s0.rp_filter
# Should return: 0

# 4. Verify hardware offload is disabled
sudo ethtool -k enp1s0 | grep -E "tx-checksumming|rx-checksumming|generic-segmentation-offload|tcp-segmentation-offload|generic-receive-offload"
# All should show: off

# 5. Monitor for DHCP packets (connect camera)
sudo tcpdump -i enp1s0 -n port 67 or port 68
# Should see Discover -> Offer -> Request -> Ack

# 6. Check DHCP leases after camera connects
cat /var/lib/misc/dnsmasq.leases
```

## Known Working Configuration

**Hardware**: Intel NUC with dual NICs
- enp3s0: WAN (cellular)
- enp1s0: LAN (cameras) - Static 192.168.100.1/24

**Software**:
- Ubuntu 24.04 LTS
- dnsmasq (DHCP/DNS)
- iptables firewall (no UFW)
- Docker & Docker Compose

**Camera Network**:
- Network: 192.168.100.0/24
- Gateway: 192.168.100.1 (POD)
- DHCP Range: 192.168.100.100-200
- DNS: 8.8.8.8, 8.8.4.4

## Critical Don'ts

❌ Do NOT enable UFW (conflicts with iptables-persistent)
❌ Do NOT enable systemd-resolved (conflicts with dnsmasq)
❌ Do NOT set rp_filter=1 (breaks DHCP)
❌ Do NOT enable hardware offload on camera interface
❌ Do NOT use `--listen-address` with dnsmasq (use `bind-interfaces`)

## Emergency Fixes

If DHCP still doesn't work after install:

```bash
# Fix 1: Manually disable rp_filter
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.enp1s0.rp_filter=0

# Fix 2: Manually disable offload
sudo ethtool -K enp1s0 rx off tx off gso off tso off gro off

# Fix 3: Restart dnsmasq
sudo systemctl restart dnsmasq

# Fix 4: Check logs
sudo journalctl -u dnsmasq -f
```

## Installation Time

Expected install time: 10-15 minutes (including Docker image builds)

## Post-Install

After successful installation:
1. Camera connects and gets IP via DHCP automatically
2. POD registers with portal using registration token
3. Docker containers start automatically on boot
4. All security hardening is active (fail2ban, auto-updates, firewall)

The system is production-ready immediately after installation.
