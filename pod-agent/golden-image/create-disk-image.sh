#!/bin/bash
#
# Create Deployable Disk Image
# Converts the golden system into distributable formats
#
# Usage: sudo ./create-disk-image.sh
#

set -e

# Configuration
IMAGE_NAME="platebridge-pod-v1.0.0"
IMAGE_DATE=$(date +%Y%m%d)
OUTPUT_DIR="/opt/platebridge-images"
COMPRESSION="xz" # or "gzip" or "none"

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

log_info "🖼️  Creating PlateBridge Golden Image"
log_info "Output directory: $OUTPUT_DIR"

# ============================================================================
# METHOD 1: Create DD Image (for exact cloning)
# ============================================================================

log_info "Creating raw disk image..."

# Get root partition
ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
ROOT_DISK=$(echo $ROOT_DEVICE | sed 's/[0-9]*$//')

log_info "Source disk: $ROOT_DISK"
log_info "WARNING: This will create a full disk image"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "Cancelled by user"
    exit 0
fi

# Create the image
OUTPUT_IMAGE="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_DATE}.img"
log_info "Creating image at: $OUTPUT_IMAGE"

dd if=$ROOT_DISK of=$OUTPUT_IMAGE bs=4M status=progress

log_success "Raw image created: $OUTPUT_IMAGE"

# Compress the image
if [ "$COMPRESSION" == "xz" ]; then
    log_info "Compressing with xz (best compression)..."
    xz -z -9 -v "$OUTPUT_IMAGE"
    FINAL_IMAGE="${OUTPUT_IMAGE}.xz"
elif [ "$COMPRESSION" == "gzip" ]; then
    log_info "Compressing with gzip (faster)..."
    gzip -9 "$OUTPUT_IMAGE"
    FINAL_IMAGE="${OUTPUT_IMAGE}.gz"
else
    FINAL_IMAGE="$OUTPUT_IMAGE"
fi

log_success "Final image: $FINAL_IMAGE"

# ============================================================================
# METHOD 2: Create ISO (for bootable USB/CD)
# ============================================================================

log_info "Creating bootable ISO..."

ISO_BUILD_DIR="/tmp/iso-build"
ISO_OUTPUT="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_DATE}.iso"

mkdir -p "$ISO_BUILD_DIR"

# Install required tools
apt-get install -y -qq squashfs-tools genisoimage isolinux syslinux

# Create filesystem squash
log_info "Creating squashfs filesystem..."
mksquashfs / "$ISO_BUILD_DIR/filesystem.squashfs" \
    -e proc sys dev tmp run mnt media "$ISO_BUILD_DIR" \
    -comp xz

# Create ISO structure
mkdir -p "$ISO_BUILD_DIR/iso/casper"
mkdir -p "$ISO_BUILD_DIR/iso/isolinux"

# Copy kernel and initrd
cp /boot/vmlinuz-* "$ISO_BUILD_DIR/iso/casper/vmlinuz"
cp /boot/initrd.img-* "$ISO_BUILD_DIR/iso/casper/initrd"

# Copy squashfs
mv "$ISO_BUILD_DIR/filesystem.squashfs" "$ISO_BUILD_DIR/iso/casper/"

# Create manifest
log_info "Creating manifest..."
dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_BUILD_DIR/iso/casper/filesystem.manifest"

# Create isolinux config
cat > "$ISO_BUILD_DIR/iso/isolinux/isolinux.cfg" <<EOF
DEFAULT platebridge
LABEL platebridge
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper automatic-ubiquity quiet splash ---
EOF

# Copy isolinux files
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_BUILD_DIR/iso/isolinux/"
cp /usr/lib/syslinux/modules/bios/*.c32 "$ISO_BUILD_DIR/iso/isolinux/"

# Create ISO
log_info "Building ISO image..."
genisoimage \
    -r -V "PlateBridge POD" \
    -cache-inodes -J -l \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o "$ISO_OUTPUT" \
    "$ISO_BUILD_DIR/iso"

# Make bootable
isohybrid "$ISO_OUTPUT"

log_success "ISO created: $ISO_OUTPUT"

# Cleanup
rm -rf "$ISO_BUILD_DIR"

# ============================================================================
# METHOD 3: Create Tar Archive (for container/VM deployment)
# ============================================================================

log_info "Creating tar archive..."

TAR_OUTPUT="$OUTPUT_DIR/${IMAGE_NAME}-${IMAGE_DATE}.tar"

tar -czf "$TAR_OUTPUT.gz" \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/tmp \
    --exclude=/run \
    --exclude=/mnt \
    --exclude=/media \
    --exclude="$OUTPUT_DIR" \
    /

log_success "Tar archive created: $TAR_OUTPUT.gz"

# ============================================================================
# Generate Checksums
# ============================================================================

log_info "Generating checksums..."

cd "$OUTPUT_DIR"
sha256sum * > SHA256SUMS.txt

log_success "Checksums generated"

# ============================================================================
# Create Documentation
# ============================================================================

log_info "Creating deployment documentation..."

cat > "$OUTPUT_DIR/DEPLOYMENT.md" <<EOF
# PlateBridge Golden Image Deployment Guide

## Image Information
- **Name:** $IMAGE_NAME
- **Build Date:** $IMAGE_DATE
- **OS:** Ubuntu 22.04 LTS
- **Version:** 1.0.0

## Available Images

### 1. Raw Disk Image (.img.xz)
**File:** \`${IMAGE_NAME}-${IMAGE_DATE}.img.xz\`

**Use Case:** Direct disk cloning for identical hardware

**Deployment:**
\`\`\`bash
# Extract
unxz ${IMAGE_NAME}-${IMAGE_DATE}.img.xz

# Flash to disk (replace /dev/sdX with target disk)
sudo dd if=${IMAGE_NAME}-${IMAGE_DATE}.img of=/dev/sdX bs=4M status=progress

# Expand partition to fill disk
sudo growpart /dev/sdX 1
sudo resize2fs /dev/sdX1
\`\`\`

### 2. Bootable ISO (.iso)
**File:** \`${IMAGE_NAME}-${IMAGE_DATE}.iso\`

**Use Case:** USB installation, VM deployment, CD/DVD

**Deployment:**
\`\`\`bash
# Create bootable USB (replace /dev/sdX with USB device)
sudo dd if=${IMAGE_NAME}-${IMAGE_DATE}.iso of=/dev/sdX bs=4M status=progress

# Or use with Rufus/Etcher/balenaEtcher on Windows/Mac
\`\`\`

### 3. Tar Archive (.tar.gz)
**File:** \`${IMAGE_NAME}-${IMAGE_DATE}.tar.gz\`

**Use Case:** VM/Container deployment, custom installations

**Deployment:**
\`\`\`bash
# Extract to target system
sudo tar -xzf ${IMAGE_NAME}-${IMAGE_DATE}.tar.gz -C /mnt/target

# Update fstab and bootloader
sudo chroot /mnt/target
update-grub
exit
\`\`\`

## Verification

Verify checksums before deployment:
\`\`\`bash
sha256sum -c SHA256SUMS.txt
\`\`\`

## First Boot Configuration

### Method 1: USB Configuration (Recommended)
1. Create \`platebridge-config.yaml\` on USB drive
2. Insert USB before first boot
3. POD will auto-configure

**config.yaml:**
\`\`\`yaml
portal_url: https://portal.platebridge.io
site_id: your-site-uuid-here
\`\`\`

### Method 2: Environment Variables
Set before first boot:
\`\`\`bash
export PLATEBRIDGE_PORTAL_URL="https://portal.platebridge.io"
export PLATEBRIDGE_SITE_ID="your-site-uuid-here"
\`\`\`

### Method 3: Interactive Setup
Connect to POD's WiFi hotspot and configure via web interface.

## Network Configuration

POD will attempt DHCP by default. For static IP:

Edit \`/etc/netplan/01-netcfg.yaml\`:
\`\`\`yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses: [192.168.1.100/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
\`\`\`

Apply: \`sudo netplan apply\`

## Remote Access (Tailscale)

Authenticate Tailscale:
\`\`\`bash
sudo tailscale up --authkey=YOUR_AUTH_KEY
\`\`\`

Or save authkey to:
\`\`\`bash
echo "YOUR_AUTH_KEY" | sudo tee /opt/platebridge/config/tailscale-authkey
sudo systemctl restart tailscaled
\`\`\`

## Troubleshooting

### View initialization logs
\`\`\`bash
sudo journalctl -u platebridge-init.service -f
\`\`\`

### Check POD status
\`\`\`bash
sudo systemctl status platebridge-init.service
sudo systemctl status platebridge-heartbeat.timer
\`\`\`

### Manual initialization
\`\`\`bash
sudo /opt/platebridge/bin/platebridge-init.sh
\`\`\`

### Reset POD
\`\`\`bash
sudo rm /var/lib/platebridge/initialized
sudo reboot
\`\`\`

## Support
- Documentation: https://docs.platebridge.io
- Support: support@platebridge.io
- Portal: https://portal.platebridge.io
EOF

log_success "Documentation created"

# ============================================================================
# Final Summary
# ============================================================================

log_success "================================================"
log_success "🎉 Image Creation Complete!"
log_success "================================================"

echo ""
log_info "Generated Files:"
ls -lh "$OUTPUT_DIR"
echo ""

log_info "Image Sizes:"
du -h "$OUTPUT_DIR"/* | grep -v SHA256SUMS
echo ""

log_info "Checksums:"
cat "$OUTPUT_DIR/SHA256SUMS.txt"
echo ""

log_success "Golden image ready for deployment!"
log_info "Location: $OUTPUT_DIR"
log_info "Deploy using: $OUTPUT_DIR/DEPLOYMENT.md"
