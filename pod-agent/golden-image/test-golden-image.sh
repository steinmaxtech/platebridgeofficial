#!/bin/bash
#
# Golden Image Test Suite
# Validates the golden image before production deployment
#
# Usage: sudo ./test-golden-image.sh
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((PASSED++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Test function
test_component() {
    local test_name=$1
    local test_command=$2

    echo -n "Testing $test_name... "

    if eval "$test_command" > /dev/null 2>&1; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

log_info "🧪 Starting Golden Image Validation"
log_info "========================================"
echo ""

# ============================================================================
# PHASE 1: System Requirements
# ============================================================================

log_info "📋 PHASE 1: System Requirements"

test_component "Ubuntu 22.04 LTS" "grep -q '22.04' /etc/os-release"
test_component "64-bit architecture" "[ $(uname -m) == 'x86_64' ]"
test_component "Systemd init" "[ -d /run/systemd/system ]"

echo ""

# ============================================================================
# PHASE 2: Docker Installation
# ============================================================================

log_info "🐳 PHASE 2: Docker Installation"

test_component "Docker installed" "command -v docker"
test_component "Docker running" "systemctl is-active docker"
test_component "Docker Compose v2" "docker compose version | grep -q 'Docker Compose version v2'"
test_component "Docker service enabled" "systemctl is-enabled docker"
test_component "Docker daemon config" "[ -f /etc/docker/daemon.json ]"

# Check Docker version
DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
log_info "Docker version: $DOCKER_VERSION"

echo ""

# ============================================================================
# PHASE 3: PlateBridge System
# ============================================================================

log_info "🔧 PHASE 3: PlateBridge System"

test_component "PlateBridge directory" "[ -d /opt/platebridge ]"
test_component "PlateBridge user" "id -u platebridge"
test_component "Init script" "[ -x /opt/platebridge/bin/platebridge-init.sh ]"
test_component "Heartbeat script" "[ -x /opt/platebridge/bin/platebridge-heartbeat.sh ]"
test_component "Config directory" "[ -d /opt/platebridge/config ]"
test_component "Docker directory" "[ -d /opt/platebridge/docker ]"
test_component "Logs directory" "[ -d /opt/platebridge/logs ]"
test_component "Recordings directory" "[ -d /opt/platebridge/recordings ]"
test_component "State directory" "[ -d /var/lib/platebridge ]"

echo ""

# ============================================================================
# PHASE 4: Systemd Services
# ============================================================================

log_info "⚙️  PHASE 4: Systemd Services"

test_component "Init service exists" "[ -f /etc/systemd/system/platebridge-init.service ]"
test_component "Init service enabled" "systemctl is-enabled platebridge-init.service"
test_component "Heartbeat service exists" "[ -f /etc/systemd/system/platebridge-heartbeat.service ]"
test_component "Heartbeat timer exists" "[ -f /etc/systemd/system/platebridge-heartbeat.timer ]"
test_component "Heartbeat timer enabled" "systemctl is-enabled platebridge-heartbeat.timer"

echo ""

# ============================================================================
# PHASE 5: Security Configuration
# ============================================================================

log_info "🔒 PHASE 5: Security Configuration"

test_component "UFW installed" "command -v ufw"
test_component "UFW enabled" "ufw status | grep -q 'Status: active'"
test_component "Fail2ban installed" "command -v fail2ban-client"
test_component "Fail2ban running" "systemctl is-active fail2ban"
test_component "Secure permissions on config" "[ $(stat -c '%a' /opt/platebridge/config) == '700' ]"

echo ""

# ============================================================================
# PHASE 6: Network Tools
# ============================================================================

log_info "📡 PHASE 6: Network Tools"

test_component "curl installed" "command -v curl"
test_component "wget installed" "command -v wget"
test_component "jq installed" "command -v jq"
test_component "dig installed" "command -v dig"
test_component "ping available" "command -v ping"

echo ""

# ============================================================================
# PHASE 7: Remote Access
# ============================================================================

log_info "🌐 PHASE 7: Remote Access (Optional)"

test_component "Tailscale installed" "command -v tailscale"
test_component "Tailscale service" "systemctl list-unit-files | grep -q tailscaled"

echo ""

# ============================================================================
# PHASE 8: System Optimization
# ============================================================================

log_info "⚡ PHASE 8: System Optimization"

test_component "Swappiness configured" "grep -q 'vm.swappiness=10' /etc/sysctl.conf"
test_component "Log rotation configured" "[ -f /etc/logrotate.d/platebridge ]"
test_component "Docker log limits" "grep -q 'max-size' /etc/docker/daemon.json"

echo ""

# ============================================================================
# PHASE 9: Documentation
# ============================================================================

log_info "📚 PHASE 9: Documentation"

test_component "VERSION file" "[ -f /opt/platebridge/VERSION ]"
test_component "README file" "[ -f /opt/platebridge/README.md ]"

if [ -f /opt/platebridge/VERSION ]; then
    log_info "Version info:"
    cat /opt/platebridge/VERSION | sed 's/^/  /'
fi

echo ""

# ============================================================================
# PHASE 10: Functional Tests
# ============================================================================

log_info "🧪 PHASE 10: Functional Tests"

# Test Docker can pull images
log_info "Testing Docker image pull..."
if docker pull hello-world > /dev/null 2>&1; then
    log_success "Docker can pull images"
    docker rmi hello-world > /dev/null 2>&1
else
    log_error "Docker cannot pull images"
fi

# Test Docker Compose
log_info "Testing Docker Compose..."
cat > /tmp/test-compose.yml <<EOF
version: '3.8'
services:
  test:
    image: busybox
    command: echo "test"
EOF

if docker compose -f /tmp/test-compose.yml config > /dev/null 2>&1; then
    log_success "Docker Compose syntax validation"
else
    log_error "Docker Compose validation failed"
fi
rm /tmp/test-compose.yml

# Test network connectivity
log_info "Testing network connectivity..."
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    log_success "Network connectivity (IPv4)"
else
    log_error "No network connectivity"
fi

# Test DNS resolution
log_info "Testing DNS resolution..."
if dig google.com +short > /dev/null 2>&1; then
    log_success "DNS resolution"
else
    log_error "DNS resolution failed"
fi

echo ""

# ============================================================================
# PHASE 11: Disk Space Check
# ============================================================================

log_info "💾 PHASE 11: Disk Space Analysis"

TOTAL_SIZE=$(df -h / | tail -1 | awk '{print $2}')
USED_SIZE=$(df -h / | tail -1 | awk '{print $3}')
AVAILABLE_SIZE=$(df -h / | tail -1 | awk '{print $4}')
USE_PERCENT=$(df / | tail -1 | awk '{print $5}')

log_info "Disk usage:"
log_info "  Total: $TOTAL_SIZE"
log_info "  Used: $USED_SIZE"
log_info "  Available: $AVAILABLE_SIZE"
log_info "  Usage: $USE_PERCENT"

if [ ${USE_PERCENT%\%} -lt 50 ]; then
    log_success "Sufficient disk space"
else
    log_warning "Disk usage above 50% - consider cleanup"
fi

echo ""

# ============================================================================
# PHASE 12: Performance Check
# ============================================================================

log_info "⚡ PHASE 12: Performance Metrics"

# Check CPU
CPU_COUNT=$(nproc)
log_info "CPU cores: $CPU_COUNT"

# Check memory
TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
AVAILABLE_MEM=$(free -h | grep Mem | awk '{print $7}')
log_info "Memory: $TOTAL_MEM total, $AVAILABLE_MEM available"

# Check Docker storage driver
STORAGE_DRIVER=$(docker info | grep 'Storage Driver' | awk '{print $3}')
log_info "Docker storage driver: $STORAGE_DRIVER"

if [ "$STORAGE_DRIVER" == "overlay2" ]; then
    log_success "Using recommended storage driver (overlay2)"
else
    log_warning "Not using overlay2 storage driver"
fi

echo ""

# ============================================================================
# Final Summary
# ============================================================================

log_info "========================================"
log_info "�� Test Summary"
log_info "========================================"

TOTAL=$((PASSED + FAILED))

echo ""
log_success "Passed: $PASSED/$TOTAL"
log_error "Failed: $FAILED/$TOTAL"
echo ""

if [ $FAILED -eq 0 ]; then
    log_success "✅ All tests passed! Golden image is ready for production."
    echo ""
    log_info "Next steps:"
    log_info "  1. Create disk image: sudo ./create-disk-image.sh"
    log_info "  2. Test deployment on spare hardware"
    log_info "  3. Store in image library"
    log_info "  4. Document any hardware-specific requirements"
    exit 0
else
    log_error "❌ Some tests failed. Please review and fix issues."
    echo ""
    log_info "Check logs at:"
    log_info "  - /opt/platebridge/logs/"
    log_info "  - journalctl -u platebridge-init.service"
    log_info "  - journalctl -u docker.service"
    exit 1
fi
