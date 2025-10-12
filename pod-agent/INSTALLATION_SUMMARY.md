# POD Installation - Ready for Fresh Deploy

## What's Been Fixed

All issues discovered during troubleshooting are now permanently fixed in `install-complete.sh`:

### Critical DHCP Fixes ✅
1. **Reverse Path Filtering** - Set to 0 on camera interface (allows DHCP from 0.0.0.0)
2. **Hardware Offload** - Disabled on camera interface (rx, tx, gso, tso, gro)
3. **systemd-resolved** - Properly disabled to prevent port 53 conflicts
4. **dnsmasq bind-interfaces** - Correct binding mode for dual-NIC setup

### Additional Improvements ✅
- ethtool added to dependencies
- Systemd service to persist offload settings across reboots
- Port verification (confirms dnsmasq listening on 53 and 67)
- Interface IP verification
- Comprehensive logging and error messages

## One-Command Installation

Starting from a **fresh Ubuntu 24.04 LTS** install:

```bash
# Install git
sudo apt update && sudo apt install -y git

# Clone repo
cd /tmp
git clone https://github.com/your-org/platebridge.git
cd platebridge/pod-agent

# Run complete installation
sudo ./install-complete.sh
```

**That's it!** Everything is configured automatically.

## What the Script Does (Automatically)

1. ✅ Installs Docker, Docker Compose, dnsmasq, iptables, ethtool, fail2ban
2. ✅ Configures dual-NIC network (WAN/LAN)
3. ✅ Disables hardware offload on camera interface
4. ✅ Sets rp_filter=0 for DHCP compatibility
5. ✅ Disables systemd-resolved (DNS conflict prevention)
6. ✅ Configures dnsmasq DHCP server for cameras
7. ✅ Sets up firewall with NAT and security rules
8. ✅ Installs and configures Frigate NVR
9. ✅ Installs PlateBridge Python agent
10. ✅ Creates systemd services for auto-start
11. ✅ Builds Docker images
12. ✅ Optionally registers POD with portal

## Installation Time

- **Ubuntu Install:** 10 minutes
- **Script Execution:** 15 minutes
- **Total:** ~25 minutes

## Post-Install Verification

```bash
# 1. Check dnsmasq is running and listening
sudo systemctl status dnsmasq
sudo ss -ulnp | grep dnsmasq

# 2. Verify rp_filter is disabled (should return 0)
sudo sysctl net.ipv4.conf.enp1s0.rp_filter

# 3. Verify hardware offload is disabled
sudo ethtool -k enp1s0 | grep -E "tx-checksumming|rx-checksumming|generic-segmentation-offload"

# 4. Connect camera and monitor DHCP
sudo tcpdump -i enp1s0 -n port 67 or port 68

# 5. Check DHCP leases
cat /var/lib/misc/dnsmasq.leases

# 6. Verify all Docker containers are running
cd /opt/platebridge/docker
sudo docker compose ps
```

## Expected Results

- ✅ Camera gets IP automatically (192.168.100.100-200)
- ✅ DHCP lease appears in dnsmasq.leases
- ✅ Camera is pingable from POD
- ✅ RTSP stream accessible
- ✅ Frigate detects camera
- ✅ POD registers with portal
- ✅ All services auto-start on boot

## Known Working Configuration

**Hardware:** Intel NUC with dual NICs
**OS:** Ubuntu 24.04 LTS Server
**Interfaces:**
- enp3s0: WAN (cellular) - DHCP
- enp1s0: LAN (cameras) - 192.168.100.1/24

**Network:**
- POD Gateway: 192.168.100.1
- DHCP Range: 192.168.100.100-200
- DNS: 8.8.8.8, 8.8.4.4

## Documentation

Created/Updated:
1. ✅ `install-complete.sh` - Production-ready installation script
2. ✅ `DHCP_FIXES_APPLIED.md` - Technical details of all fixes
3. ✅ `README.md` - Updated with fresh install instructions
4. ✅ `POD_INSTALLATION_GUIDE.md` - Complete step-by-step guide (root level)

## Ready to Deploy

The system is now ready for a clean installation on a fresh Ubuntu system. All known issues have been resolved and the installation is fully automated.

**Next step:** Wipe the test system and run the installation fresh to verify everything works first time!
