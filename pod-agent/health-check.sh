#!/bin/bash

################################################################################
# PlateBridge POD Health Check Script
# Run this to diagnose any issues with your POD
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ${GREEN}$1${BLUE}${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_check() {
    echo -e "${BLUE}→${NC} $1"
}

print_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

################################################################################
# Health Checks
################################################################################

print_header "PlateBridge POD Health Check"

# Check Docker
print_check "Checking Docker..."
if docker ps >/dev/null 2>&1; then
    print_ok "Docker is running"
else
    print_error "Docker is not running or not accessible"
    echo "  Fix: sudo systemctl start docker"
    exit 1
fi

# Check containers
print_check "Checking Docker containers..."
CONTAINERS=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "platebridge-pod|frigate|mosquitto" || true)

if [ -z "$CONTAINERS" ]; then
    print_error "No PlateBridge containers running"
    echo "  Fix: cd /opt/platebridge/docker && sudo docker compose up -d"
    exit 1
fi

for container in platebridge-pod frigate mosquitto; do
    if docker ps | grep -q "$container"; then
        STATUS=$(docker inspect --format='{{.State.Status}}' $container 2>/dev/null)
        if [ "$STATUS" = "running" ]; then
            UPTIME=$(docker inspect --format='{{.State.StartedAt}}' $container 2>/dev/null)
            print_ok "$container is running (since $UPTIME)"
        else
            print_error "$container is not running (status: $STATUS)"
        fi
    else
        print_warn "$container is not running"
    fi
done

# Check API key
print_check "Checking API key configuration..."
API_KEY=$(docker exec platebridge-pod env 2>/dev/null | grep POD_API_KEY | cut -d'=' -f2)

if [ -z "$API_KEY" ]; then
    print_error "POD_API_KEY is not set"
    echo "  Fix: Edit /opt/platebridge/docker/.env and add POD_API_KEY=pbk_your_key"
    echo "  Generate key at: https://platebridge.vercel.app/pods"
elif [[ ! "$API_KEY" =~ ^pbk_ ]]; then
    print_error "API key has wrong format (should start with pbk_)"
    echo "  Current: $API_KEY"
    echo "  Fix: Generate new key at portal"
else
    print_ok "API key configured: ${API_KEY:0:20}..."
fi

# Check heartbeat
print_check "Checking last heartbeat..."
LAST_LOG=$(docker logs platebridge-pod --tail 50 2>/dev/null | grep -i heartbeat | tail -1)

if echo "$LAST_LOG" | grep -qi "401"; then
    print_error "Heartbeat failing with 401 Unauthorized"
    echo "  Problem: Invalid or missing API key"
    echo "  Fix: Generate new API key from portal and update .env file"
elif echo "$LAST_LOG" | grep -qi "success\|sent"; then
    print_ok "Heartbeat successful"
else
    print_warn "Cannot determine heartbeat status"
    echo "  Last log: $LAST_LOG"
fi

# Check community ID
print_check "Checking community ID..."
COMMUNITY_LOG=$(docker logs platebridge-pod --tail 100 2>/dev/null | grep -i "community" | tail -1)

if echo "$COMMUNITY_LOG" | grep -qi "Community ID obtained"; then
    COMM_ID=$(echo "$COMMUNITY_LOG" | grep -oP 'Community ID obtained: \K[^\s]+')
    print_ok "Community ID: $COMM_ID"
elif echo "$COMMUNITY_LOG" | grep -qi "No community_id available"; then
    print_warn "No community ID available yet"
    echo "  This is normal on first start"
    echo "  Wait for successful heartbeat to obtain community ID"
else
    print_warn "Cannot determine community ID status"
fi

# Check network
print_check "Checking network connectivity..."
if docker exec platebridge-pod ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    print_ok "Internet connectivity OK"
else
    print_error "No internet connectivity"
    echo "  Fix: Check WAN interface and routing"
fi

if docker exec platebridge-pod ping -c 1 platebridge.vercel.app >/dev/null 2>&1; then
    print_ok "Can reach portal"
else
    print_error "Cannot reach portal"
    echo "  Fix: Check DNS and firewall"
fi

# Check Frigate
print_check "Checking Frigate..."
if curl -s http://localhost:5000/api/ >/dev/null 2>&1; then
    print_ok "Frigate API is accessible"
else
    print_warn "Frigate API not accessible"
    echo "  Check: docker logs frigate"
fi

# Check MQTT
print_check "Checking MQTT..."
if docker exec mosquitto mosquitto_sub -t 'test' -C 1 -W 1 >/dev/null 2>&1; then
    print_ok "MQTT broker is working"
else
    print_warn "MQTT broker not responding"
    echo "  Check: docker logs mosquitto"
fi

# Check disk space
print_check "Checking disk space..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    print_ok "Disk usage: ${DISK_USAGE}%"
elif [ "$DISK_USAGE" -lt 90 ]; then
    print_warn "Disk usage: ${DISK_USAGE}% (getting full)"
else
    print_error "Disk usage: ${DISK_USAGE}% (critically full)"
    echo "  Fix: Clean up recordings or expand storage"
fi

# Check USB storage if mounted
if mountpoint -q /media/frigate 2>/dev/null; then
    USB_USAGE=$(df -h /media/frigate | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$USB_USAGE" -lt 80 ]; then
        print_ok "USB storage: ${USB_USAGE}%"
    else
        print_warn "USB storage: ${USB_USAGE}% (getting full)"
    fi
fi

# Check system resources
print_check "Checking system resources..."
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')

if (( $(echo "$CPU_USAGE < 80" | bc -l) )); then
    print_ok "CPU usage: ${CPU_USAGE}%"
else
    print_warn "CPU usage: ${CPU_USAGE}% (high)"
fi

if [ "$MEM_USAGE" -lt 80 ]; then
    print_ok "Memory usage: ${MEM_USAGE}%"
else
    print_warn "Memory usage: ${MEM_USAGE}% (high)"
fi

# Check Tailscale
print_check "Checking Tailscale..."
if command -v tailscale >/dev/null 2>&1; then
    if tailscale status >/dev/null 2>&1; then
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
        print_ok "Tailscale connected: $TAILSCALE_IP"
    else
        print_warn "Tailscale not connected"
        echo "  Connect: sudo tailscale up"
    fi
else
    print_warn "Tailscale not installed"
fi

# Summary
echo ""
print_header "Summary"

ERROR_COUNT=$(docker logs platebridge-pod --tail 100 2>/dev/null | grep -i error | wc -l)
WARNING_COUNT=$(docker logs platebridge-pod --tail 100 2>/dev/null | grep -i warning | wc -l)

echo "Recent logs (last 100 lines):"
echo "  Errors: $ERROR_COUNT"
echo "  Warnings: $WARNING_COUNT"

if [ "$ERROR_COUNT" -gt 5 ]; then
    print_warn "High error count, check logs: docker logs platebridge-pod"
fi

# Recent important logs
echo ""
echo "Recent important logs:"
docker logs platebridge-pod --tail 20 2>/dev/null | grep -E "ERROR|WARNING|Heartbeat|Community" || echo "  (none)"

echo ""
print_header "Quick Commands"
echo "View live logs:      docker logs -f platebridge-pod"
echo "Restart services:    cd /opt/platebridge/docker && sudo docker compose restart"
echo "Check containers:    docker ps"
echo "View heartbeat:      docker logs platebridge-pod | grep -i heartbeat"
echo "Portal dashboard:    https://platebridge.vercel.app/pods"
echo ""

# Exit code based on critical issues
if [ -z "$API_KEY" ] || docker logs platebridge-pod --tail 50 2>/dev/null | grep -q "401"; then
    echo -e "${RED}❌ Critical issues found - POD not operational${NC}"
    echo ""
    echo "FIX NOW:"
    echo "1. Generate API key at: https://platebridge.vercel.app/pods"
    echo "2. Edit: sudo nano /opt/platebridge/docker/.env"
    echo "3. Set: POD_API_KEY=pbk_your_new_key"
    echo "4. Restart: cd /opt/platebridge/docker && sudo docker compose restart"
    exit 1
else
    echo -e "${GREEN}✅ POD appears to be operational${NC}"
    exit 0
fi
