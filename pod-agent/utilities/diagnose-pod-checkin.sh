#!/bin/bash

################################################################################
# POD Check-in Diagnostics
# Comprehensive tool to diagnose why POD is not checking in with portal
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  PlateBridge POD - Check-in Diagnostics                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

################################################################################
# Step 1: Check if POD agent is running
################################################################################

echo -e "${BLUE}[1/10] Checking POD Agent Status${NC}"

if docker ps | grep -q platebridge-pod; then
    echo -e "${GREEN}✓ POD agent container is running${NC}"
    CONTAINER_NAME="platebridge-pod"
elif docker ps | grep -q platebridge-agent; then
    echo -e "${GREEN}✓ POD agent container is running (as platebridge-agent)${NC}"
    CONTAINER_NAME="platebridge-agent"
else
    echo -e "${RED}✗ POD agent container is NOT running${NC}"
    echo ""
    echo "Checking stopped containers..."
    docker ps -a | grep -E "platebridge-pod|platebridge-agent" || echo "No POD containers found at all"
    echo ""
    echo -e "${YELLOW}Action: Start the POD agent${NC}"
    echo "  cd /opt/platebridge/docker"
    echo "  docker compose up -d"
    exit 1
fi

echo ""

################################################################################
# Step 2: Check container health
################################################################################

echo -e "${BLUE}[2/10] Checking Container Health${NC}"

CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' $CONTAINER_NAME)
CONTAINER_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' $CONTAINER_NAME 2>/dev/null || echo "no-healthcheck")

echo "Status: $CONTAINER_STATUS"
if [ "$CONTAINER_HEALTH" != "no-healthcheck" ]; then
    echo "Health: $CONTAINER_HEALTH"
fi

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo -e "${RED}✗ Container is not running properly${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Container is running${NC}"
echo ""

################################################################################
# Step 3: Check environment variables
################################################################################

echo -e "${BLUE}[3/10] Checking Environment Variables${NC}"

PORTAL_URL=$(docker exec $CONTAINER_NAME env | grep PORTAL_URL | cut -d= -f2)
POD_API_KEY=$(docker exec $CONTAINER_NAME env | grep POD_API_KEY | cut -d= -f2)
POD_ID=$(docker exec $CONTAINER_NAME env | grep POD_ID | cut -d= -f2)

if [ -z "$PORTAL_URL" ]; then
    echo -e "${RED}✗ PORTAL_URL is not set${NC}"
    ENV_ERROR=1
else
    echo -e "${GREEN}✓ PORTAL_URL: $PORTAL_URL${NC}"
fi

if [ -z "$POD_API_KEY" ]; then
    echo -e "${RED}✗ POD_API_KEY is not set${NC}"
    ENV_ERROR=1
else
    echo -e "${GREEN}✓ POD_API_KEY: ${POD_API_KEY:0:20}...${NC}"
fi

if [ -z "$POD_ID" ]; then
    echo -e "${YELLOW}⚠ POD_ID is not set (may be ok if using community_id)${NC}"
else
    echo -e "${GREEN}✓ POD_ID: $POD_ID${NC}"
fi

if [ "$ENV_ERROR" = "1" ]; then
    echo ""
    echo -e "${RED}Environment variables are missing!${NC}"
    echo ""
    echo "Check your .env file:"
    echo "  cat /opt/platebridge/docker/.env"
    echo ""
    echo "Required variables:"
    echo "  PORTAL_URL=https://platebridge.vercel.app"
    echo "  POD_API_KEY=pbk_your_api_key_here"
    echo "  POD_ID=your_pod_id_here"
    exit 1
fi

echo ""

################################################################################
# Step 4: Check network connectivity
################################################################################

echo -e "${BLUE}[4/10] Checking Network Connectivity${NC}"

# Check internet connectivity
if docker exec $CONTAINER_NAME ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Internet connectivity OK${NC}"
else
    echo -e "${RED}✗ No internet connectivity${NC}"
    echo ""
    echo "The POD cannot reach the internet. Check:"
    echo "  1. WAN interface is connected"
    echo "  2. Network cable is plugged in"
    echo "  3. Cellular modem has signal (if applicable)"
    echo "  4. Check: ip addr show"
    exit 1
fi

# Check DNS resolution
if docker exec $CONTAINER_NAME ping -c 1 google.com >/dev/null 2>&1; then
    echo -e "${GREEN}✓ DNS resolution OK${NC}"
else
    echo -e "${RED}✗ DNS resolution failed${NC}"
    echo ""
    echo "DNS is not working. Check:"
    echo "  cat /etc/resolv.conf"
    echo "  systemctl status dnsmasq"
    exit 1
fi

# Extract hostname from PORTAL_URL
PORTAL_HOST=$(echo "$PORTAL_URL" | sed -e 's|^http://||' -e 's|^https://||' -e 's|/.*||')

# Check portal connectivity
if docker exec $CONTAINER_NAME ping -c 1 $PORTAL_HOST >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Portal host reachable: $PORTAL_HOST${NC}"
else
    echo -e "${YELLOW}⚠ Cannot ping portal host: $PORTAL_HOST (may be normal if ICMP blocked)${NC}"
fi

echo ""

################################################################################
# Step 5: Test HTTPS connection to portal
################################################################################

echo -e "${BLUE}[5/10] Testing HTTPS Connection to Portal${NC}"

HTTPS_TEST=$(docker exec $CONTAINER_NAME curl -s -o /dev/null -w "%{http_code}" "$PORTAL_URL" --connect-timeout 10)

if [ "$HTTPS_TEST" = "200" ] || [ "$HTTPS_TEST" = "301" ] || [ "$HTTPS_TEST" = "302" ]; then
    echo -e "${GREEN}✓ HTTPS connection successful (HTTP $HTTPS_TEST)${NC}"
else
    echo -e "${RED}✗ HTTPS connection failed (HTTP $HTTPS_TEST)${NC}"
    echo ""
    echo "Portal URL: $PORTAL_URL"
    echo "Cannot connect to portal. Check:"
    echo "  1. Portal URL is correct"
    echo "  2. Portal is online"
    echo "  3. Firewall allows outbound HTTPS"
    exit 1
fi

echo ""

################################################################################
# Step 6: Test heartbeat endpoint authentication
################################################################################

echo -e "${BLUE}[6/10] Testing Heartbeat API Authentication${NC}"

HEARTBEAT_ENDPOINT="$PORTAL_URL/api/pod/heartbeat"

# Test with current API key
HEARTBEAT_TEST=$(docker exec $CONTAINER_NAME curl -s -X POST "$HEARTBEAT_ENDPOINT" \
    -H "Authorization: Bearer $POD_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"pod_id":"'"$POD_ID"'","status":"online"}' \
    -w "\nHTTP_CODE:%{http_code}" \
    --connect-timeout 10)

HTTP_CODE=$(echo "$HEARTBEAT_TEST" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE=$(echo "$HEARTBEAT_TEST" | grep -v "HTTP_CODE:")

echo "HTTP Status: $HTTP_CODE"

case $HTTP_CODE in
    200|201)
        echo -e "${GREEN}✓ Heartbeat authentication successful${NC}"
        echo "Response: $RESPONSE"
        ;;
    401)
        echo -e "${RED}✗ Authentication failed (401 Unauthorized)${NC}"
        echo "Response: $RESPONSE"
        echo ""
        echo -e "${YELLOW}Your API key is invalid or expired!${NC}"
        echo ""
        echo "To fix:"
        echo "  1. Go to portal: $PORTAL_URL/pods"
        echo "  2. Find your POD in the list"
        echo "  3. Click 'Regenerate API Key'"
        echo "  4. Copy the new key"
        echo "  5. Update .env file:"
        echo "     sudo nano /opt/platebridge/docker/.env"
        echo "     POD_API_KEY=pbk_your_new_key_here"
        echo "  6. Restart:"
        echo "     cd /opt/platebridge/docker"
        echo "     docker compose restart"
        exit 1
        ;;
    403)
        echo -e "${RED}✗ Forbidden (403)${NC}"
        echo "Response: $RESPONSE"
        echo ""
        echo "POD is not authorized to access this community."
        ;;
    404)
        echo -e "${RED}✗ Endpoint not found (404)${NC}"
        echo "Response: $RESPONSE"
        echo ""
        echo "Portal URL may be incorrect or endpoint doesn't exist."
        echo "Verify: $HEARTBEAT_ENDPOINT"
        ;;
    500|502|503)
        echo -e "${RED}✗ Portal server error ($HTTP_CODE)${NC}"
        echo "Response: $RESPONSE"
        echo ""
        echo "Portal is experiencing issues. Check portal logs."
        ;;
    000)
        echo -e "${RED}✗ Connection timeout or refused${NC}"
        echo ""
        echo "Cannot connect to portal. Possible issues:"
        echo "  1. Portal is down"
        echo "  2. Firewall blocking connection"
        echo "  3. Network issue"
        exit 1
        ;;
    *)
        echo -e "${YELLOW}⚠ Unexpected response: HTTP $HTTP_CODE${NC}"
        echo "Response: $RESPONSE"
        ;;
esac

echo ""

################################################################################
# Step 7: Check POD agent logs
################################################################################

echo -e "${BLUE}[7/10] Checking POD Agent Logs (Last 30 lines)${NC}"

echo "Recent logs:"
docker logs $CONTAINER_NAME --tail 30

echo ""
echo -e "${YELLOW}Look for:${NC}"
echo "  - 'Heartbeat sent successfully' = Good"
echo "  - '401 Unauthorized' = Bad API key"
echo "  - 'Connection refused' = Cannot reach portal"
echo "  - Python errors/tracebacks = Code issues"

echo ""

################################################################################
# Step 8: Check if POD is in database
################################################################################

echo -e "${BLUE}[8/10] Checking POD Registration in Portal${NC}"

# Try to get POD info from portal
POD_INFO=$(docker exec $CONTAINER_NAME curl -s -X GET "$PORTAL_URL/api/pod/info?pod_id=$POD_ID" \
    -H "Authorization: Bearer $POD_API_KEY" \
    --connect-timeout 10)

if echo "$POD_INFO" | grep -q "pod_id\|name"; then
    echo -e "${GREEN}✓ POD is registered in portal${NC}"
    echo "POD Info:"
    echo "$POD_INFO" | grep -E "pod_id|name|community_id|status" || echo "$POD_INFO"
else
    echo -e "${RED}✗ POD not found in portal database${NC}"
    echo "Response: $POD_INFO"
    echo ""
    echo -e "${YELLOW}POD may not be registered properly.${NC}"
    echo "To register:"
    echo "  1. Generate registration token in portal"
    echo "  2. Run: cd /opt/platebridge/docker"
    echo "  3. Run: sudo ../utilities/register-pod.sh"
fi

echo ""

################################################################################
# Step 9: Check Tailscale status (if applicable)
################################################################################

echo -e "${BLUE}[9/10] Checking Tailscale Status${NC}"

if command -v tailscale &> /dev/null; then
    if tailscale status >/dev/null 2>&1; then
        TS_IP=$(tailscale ip -4 2>/dev/null)
        TS_STATUS=$(tailscale status --json 2>/dev/null | jq -r '.Self.Online' 2>/dev/null || echo "unknown")

        if [ "$TS_STATUS" = "true" ]; then
            echo -e "${GREEN}✓ Tailscale connected: $TS_IP${NC}"

            # Check if Funnel is enabled
            if tailscale funnel status 2>/dev/null | grep -q "https://"; then
                TS_FUNNEL=$(tailscale funnel status 2>/dev/null | grep "https://" | awk '{print $1}')
                echo -e "${GREEN}✓ Tailscale Funnel enabled: $TS_FUNNEL${NC}"
            else
                echo -e "${YELLOW}⚠ Tailscale Funnel not enabled${NC}"
                echo "  To enable: sudo tailscale funnel 8000"
            fi
        else
            echo -e "${YELLOW}⚠ Tailscale installed but not connected${NC}"
            echo "  To connect: sudo tailscale up"
        fi
    else
        echo -e "${YELLOW}⚠ Tailscale installed but not running${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Tailscale not installed${NC}"
fi

echo ""

################################################################################
# Step 10: Test manual heartbeat
################################################################################

echo -e "${BLUE}[10/10] Testing Manual Heartbeat${NC}"

echo "Sending test heartbeat..."

# Try to send a heartbeat with full system info
MANUAL_HEARTBEAT=$(docker exec $CONTAINER_NAME curl -s -X POST "$PORTAL_URL/api/pod/heartbeat" \
    -H "Authorization: Bearer $POD_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "pod_id": "'"$POD_ID"'",
        "status": "online",
        "system": {
            "cpu_percent": 25.0,
            "memory_percent": 45.0,
            "disk_percent": 60,
            "temperature": 55
        },
        "ip_address": "test",
        "version": "1.0.0"
    }' \
    -w "\nHTTP_CODE:%{http_code}" \
    --connect-timeout 10)

HTTP_CODE=$(echo "$MANUAL_HEARTBEAT" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE=$(echo "$MANUAL_HEARTBEAT" | grep -v "HTTP_CODE:")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo -e "${GREEN}✓ Manual heartbeat successful!${NC}"
    echo "Response: $RESPONSE"
else
    echo -e "${RED}✗ Manual heartbeat failed: HTTP $HTTP_CODE${NC}"
    echo "Response: $RESPONSE"
fi

echo ""

################################################################################
# Summary and Recommendations
################################################################################

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Diagnostic Summary                                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Determine issues
ISSUES=()

# Check container
if ! docker ps | grep -q "platebridge-pod\|platebridge-agent"; then
    ISSUES+=("Container not running")
fi

# Check env vars
if [ -z "$POD_API_KEY" ]; then
    ISSUES+=("POD_API_KEY not set")
fi

# Check connectivity
if ! docker exec $CONTAINER_NAME ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    ISSUES+=("No internet connectivity")
fi

# Check portal connection
if [ "$HTTPS_TEST" != "200" ] && [ "$HTTPS_TEST" != "301" ] && [ "$HTTPS_TEST" != "302" ]; then
    ISSUES+=("Cannot connect to portal")
fi

# Check auth
if [ "$HTTP_CODE" = "401" ]; then
    ISSUES+=("Invalid API key (401 Unauthorized)")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ No critical issues detected!${NC}"
    echo ""
    echo "POD should be checking in successfully."
    echo ""
    echo "If POD still not showing in portal:"
    echo "  1. Check portal logs for errors"
    echo "  2. Verify POD ID matches in portal database"
    echo "  3. Check portal's /api/pod/heartbeat endpoint"
    echo "  4. Restart POD agent: docker compose restart"
else
    echo -e "${RED}Issues detected:${NC}"
    for issue in "${ISSUES[@]}"; do
        echo -e "  ${RED}✗${NC} $issue"
    done
    echo ""
    echo -e "${YELLOW}Recommended Actions:${NC}"

    for issue in "${ISSUES[@]}"; do
        case "$issue" in
            "Container not running")
                echo "  • Start POD agent:"
                echo "      cd /opt/platebridge/docker && docker compose up -d"
                ;;
            "POD_API_KEY not set")
                echo "  • Set POD_API_KEY in .env file:"
                echo "      sudo nano /opt/platebridge/docker/.env"
                echo "      POD_API_KEY=pbk_your_key_here"
                ;;
            "No internet connectivity")
                echo "  • Check WAN interface connection"
                echo "  • Verify: ip addr show"
                echo "  • Check: ping 8.8.8.8"
                ;;
            "Cannot connect to portal")
                echo "  • Verify portal URL: $PORTAL_URL"
                echo "  • Check portal is online"
                echo "  • Test manually: curl $PORTAL_URL"
                ;;
            "Invalid API key (401 Unauthorized)")
                echo "  • Regenerate API key in portal"
                echo "  • Update .env file with new key"
                echo "  • Restart: docker compose restart"
                ;;
        esac
    done
fi

echo ""
echo -e "${BLUE}For more details, check:${NC}"
echo "  • POD logs:    docker logs -f $CONTAINER_NAME"
echo "  • All logs:    cd /opt/platebridge/docker && docker compose logs -f"
echo "  • System logs: journalctl -u platebridge-pod -f"
echo ""
