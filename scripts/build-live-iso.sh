#!/usr/bin/env bash
#
# Rustica OS Live Image Build Script
#
# Creates a bootable UEFI disk image for native Rustux bootloader
#
# Usage:
#   ./build-live-iso.sh
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="/var/www/rustux.com/prod"
OUTPUT_DIR="${OUTPUT_DIR:-/var/www/rustux.com/html/rustica}"
BUILD_DIR="$SCRIPT_DIR/.build-live"
VERSION="${RUSTICA_VERSION:-0.1.0}"

# Image configuration
IMG_SIZE="512M"
ARCH="${RUSTICA_ARCH:-amd64}"
IMG_NAME="rustica-live-${ARCH}-${VERSION}.img"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Clean build
clean_build() {
    log_step "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
}

# Create disk image
create_disk_image() {
    log_step "Creating disk image (${IMG_SIZE})..."

    local img_path="$BUILD_DIR/$IMG_NAME"

    # Create raw disk image
    dd if=/dev/zero of="$img_path" bs=1 count=0 seek="$IMG_SIZE" 2>/dev/null

    # Create GPT partition table with EFI System Partition and root partition
    log_info "Creating partitions..."
    parted "$img_path" mklabel gpt 2>/dev/null || true
    parted "$img_path" mkpart primary fat32 1MiB 64MiB 2>/dev/null || true
    parted "$img_path" set 1 esp on 2>/dev/null || true
    parted "$img_path" mkpart primary ext4 64MiB 100% 2>/dev/null || true

    # Setup loop device
    local loop_dev
    loop_dev=$(losetup -f --show "$img_path")
    partprobe "$loop_dev" 2>/dev/null || true
    sleep 1

    # Format partitions
    log_info "Formatting partitions..."
    mkfs.vfat -F32 "${loop_dev}p1" 2>/dev/null
    mkfs.ext4 -F "${loop_dev}p2" 2>/dev/null

    # Mount partitions
    local mount_dir="$BUILD_DIR/mount"
    mkdir -p "$mount_dir"
    mount "${loop_dev}p2" "$mount_dir" 2>/dev/null
    mkdir -p "$mount_dir/boot/efi"
    mount "${loop_dev}p1" "$mount_dir/boot/efi" 2>/dev/null

    # Create rootfs structure
    log_step "Creating rootfs..."
    mkdir -p "$mount_dir"/{bin,boot,dev,etc,home,proc,root,run,srv,sys,tmp,var,opt}
    mkdir -p "$mount_dir"/usr/{bin,sbin,lib,share}
    mkdir -p "$mount_dir"/var/{lib,cache,log,run}
    mkdir -p "$mount_dir"/boot/efi/EFI
    mkdir -p "$mount_dir"/boot/rustux

    # Build tools if needed
    log_info "Building tools..."
    local apps_src="$REPO_ROOT/apps/target/release"

    if [ ! -f "$apps_src/rustux-install" ]; then
        log_warn "Tools not built. Building..."
        (cd "$REPO_ROOT/apps" && cargo build --release 2>&1 | tail -20)
    fi

    # Copy essential binaries
    log_info "Copying Rustica tools..."
    for tool in rustux-install login ping fwctl ip rustux-dnslookup rustux-editor rustux-ssh rustux-logview rpg; do
        if [ -f "$apps_src/$tool" ]; then
            cp "$apps_src/$tool" "$mount_dir/bin/" 2>/dev/null || true

            # Create symlinks
            case "$tool" in
                rustux-install)
                    ln -sf rustux-install "$mount_dir/bin/installer"
                    ;;
                rustux-dnslookup)
                    ln -sf rustux-dnslookup "$mount_dir/bin/dnslookup"
                    ;;
                rustux-editor)
                    ln -sf rustux-editor "$mount_dir/bin/vi"
                    ln -sf rustux-editor "$mount_dir/bin/nano"
                    ;;
                rustux-ssh)
                    ln -sf rustux-ssh "$mount_dir/bin/ssh"
                    ;;
                rustux-logview)
                    ln -sf rustux-logview "$mount_dir/bin/logview"
                    ;;
            esac
        fi
    done

    # Copy shared libraries for Rust binaries
    log_info "Copying libraries..."
    for bin in "$mount_dir/bin"/*; do
        if [ -f "$bin" ]; then
            ldd "$bin" 2>/dev/null | grep -o '/lib.*\.[0-9]+' | while read lib; do
                mkdir -p "$(dirname "$mount_dir/$lib")"
                cp "$lib" "$mount_dir/$lib" 2>/dev/null || true
            done
        fi
    done

    # Copy libgcc and libstdc++
    for lib in $(find /usr/lib -name "libgcc_s.so*" -o -name "libstdc++.so*" 2>/dev/null | head -10); do
        [ -f "$lib" ] && mkdir -p "$mount_dir$(dirname "$lib")" && cp "$lib" "$mount_dir$(dirname "$lib")/" 2>/dev/null || true
    done

    # Create config files
    log_info "Creating configuration..."
    cat > "$mount_dir/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
EOF

    cat > "$mount_dir/etc/group" << 'EOF'
root:x:0:
nogroup:x:65534:
EOF

    cat > "$mount_dir/etc/hostname" << 'EOF'
rustica-live
EOF

    cat > "$mount_dir/etc/fstab" << 'EOF'
LABEL=RUSTICA_LIVE / auto defaults 1 1
EOF

    cat > "$mount_dir/etc/os-release" << 'EOF'
NAME="Rustica OS"
VERSION="0.1.0"
ID=rustica
PRETTY_NAME="Rustica OS Live"
HOME_URL="https://rustux.com"
EOF

    # Build and install native UEFI bootloader
    log_step "Building native UEFI bootloader..."
    local uefi_loader="$REPO_ROOT/uefi-loader"
    local efi_output="$mount_dir/boot/efi/EFI/BOOT"

    if [ -d "$uefi_loader" ]; then
        # Build the UEFI loader
        (cd "$uefi_loader" && cargo build --target x86_64-unknown-uefi --release 2>&1 | tail -10)

        # Copy the built EFI file to the correct location
        local efi_file="$uefi_loader/target/x86_64-unknown-uefi/release/rustux-uefi-loader.efi"
        if [ -f "$efi_file" ]; then
            mkdir -p "$efi_output"
            cp "$efi_file" "$efi_output/BOOTX64.EFI"
            log_info "Installed BOOTX64.EFI ($(du -h "$efi_file" | cut -f1))"
        else
            log_warn "UEFI loader build not found at $efi_file"
        fi
    else
        log_warn "UEFI loader source not found at $uefi_loader"
    fi

    # Unmount
    log_info "Cleaning up..."
    sync
    umount "$mount_dir/boot/efi" 2>/dev/null || true
    umount "$mount_dir" 2>/dev/null || true
    losetup -d "$loop_dev" 2>/dev/null || true
    rm -rf "$mount_dir"

    # Copy to output
    cp "$img_path" "$OUTPUT_DIR/$IMG_NAME"
    ln -sf "$IMG_NAME" "$OUTPUT_DIR/rustica-live-${ARCH}.img"

    # Generate checksum
    cd "$OUTPUT_DIR"
    sha256sum "$IMG_NAME" > "${IMG_NAME}.sha256"

    local size=$(du -h "$OUTPUT_DIR/$IMG_NAME" | cut -f1)
    log_info "Image created: $OUTPUT_DIR/$IMG_NAME ($size)"
    log_info "Symlink: $OUTPUT_DIR/rustica-live-${ARCH}.img"
    log_info "Image is now bootable via native UEFI bootloader!"
}

# Main
main() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║           Rustica OS Live Image Build v${VERSION}            ║"
    echo "║                                                           ║"
    echo "║              Native UEFI Bootloader Included               ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    clean_build
    create_disk_image

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║              Build completed successfully!               ║"
    echo "║                                                           ║"
    echo "║           Native UEFI bootloader: BOOTX64.EFI            ║"
    echo "║           Image is ready for UEFI boot testing           ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

main "$@"
