#!/usr/bin/env bash
#
# Rustica OS Installer Build Script
#
# Creates bootable installer images for amd64, arm64, and riscv64
#
# Usage:
#   ./build-all.sh              # Build all architectures
#   ./build-all.sh amd64        # Build specific architecture
#   ./build-all.sh --validate   # Build and validate with QEMU
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
IMAGES_DIR="$SCRIPT_DIR/images"
CONFIGS_DIR="$SCRIPT_DIR/configs"
VALIDATION_DIR="$SCRIPT_DIR/validation"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version info
VERSION="${RUSTICA_VERSION:-0.1.0}"
BUILD_DATE="$(date +%Y%m%d-%H%M%S)"

# Architecture configurations
declare -A ARCH_CONFIG=(
    ["amd64"]="x86_64-unknown-linux-gnu|qemu-system-x86_64| grub"
    ["arm64"]="aarch64-unknown-linux-gnu|qemu-system-aarch64| uboot"
    ["riscv64"]="riscv64gc-unknown-linux-gnu|qemu-system-riscv64| opensbi"
)

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [ARCH] [--validate] [--clean]

Arguments:
  ARCH              Architecture to build (amd64, arm64, riscv64, or 'all')
                    Default: all

Options:
  --validate        Run QEMU validation after building
  --clean           Clean build directories before building
  --help            Show this help message

Environment Variables:
  RUSTICA_VERSION   Version string (default: 0.1.0)
  REPO_ROOT         Path to Rustica repository root

Examples:
  $0                    # Build all architectures
  $0 amd64              # Build only amd64
  $0 all --validate     # Build all and validate

EOF
}

# Clean build directories
clean_build() {
    log_step "Cleaning build directories..."
    rm -rf "$BUILD_DIR"/*
    rm -rf "$IMAGES_DIR"/*
    log_info "Build directories cleaned"
}

# Initialize directories
init_dirs() {
    mkdir -p "$BUILD_DIR"/{rootfs,initramfs,bootloader,isolinux}
    mkdir -p "$IMAGES_DIR"
    mkdir -p "$CONFIGS_DIR"
    log_info "Build directories initialized"
}

# Collect kernel artifacts
collect_kernel() {
    local arch=$1
    local target_triple=$(echo "${ARCH_CONFIG[$arch]}" | cut -d'|' -f1)

    log_step "Collecting kernel artifacts for $arch..."

    local kernel_src="$REPO_ROOT/kernel/target/$target_triple/release"
    local kernel_dst="$BUILD_DIR/rootfs/boot"

    mkdir -p "$kernel_dst"

    if [ -f "$kernel_src/rustux" ]; then
        cp -v "$kernel_src/rustux" "$kernel_dst/vmlinuz-rustica-$arch"
        log_info "Kernel binary copied"
    else
        log_warn "Kernel binary not found at $kernel_src/rustux"
        log_warn "Building kernel..."
        (cd "$REPO_ROOT/kernel" && cargo build --release --target "$target_triple")
    fi
}

# Collect rootfs artifacts
collect_rootfs() {
    local arch=$1

    log_step "Collecting rootfs artifacts for $arch..."

    local apps_src="$REPO_ROOT/apps/target/release"
    local rootfs_dst="$BUILD_DIR/rootfs"

    # Create basic directory structure
    mkdir -p "$rootfs_dst"/{bin,sbin,etc,home,root,usr/{bin,sbin,lib},var/{lib,cache,log},opt,proc,sys,dev,tmp,mnt,media}

    # Copy CLI tools
    local tools=(
        "rpg"
        "pkg"
        "apt"
        "apt-get"
        "login"
        "ping"
        "fwctl"
        "ip"
        "tar"
        "dnslookup"
        "editor"
        "ssh"
        "logview"
        "capctl"
        "sbctl"
        "bootctl"
    )

    for tool in "${tools[@]}"; do
        if [ -f "$apps_src/$tool" ] || [ -f "$apps_src/rustux-$tool" ]; then
            if [ -f "$apps_src/$tool" ]; then
                cp -v "$apps_src/$tool" "$rootfs_dst/bin/"
            else
                cp -v "$apps_src/rustux-$tool" "$rootfs_dst/bin/$tool"
            fi
        fi
    done

    # Copy installer
    if [ -f "$apps_src/installer" ]; then
        cp -v "$apps_src/installer" "$rootfs_dst/bin/rustica-installer"
    elif [ -f "$apps_src/rustux-install" ]; then
        cp -v "$apps_src/rustux-install" "$rootfs_dst/bin/rustica-installer"
    fi

    # Create essential symlinks
    ln -sf /bin/rpg "$rootfs_dst/bin/pkg"
    ln -sf /bin/editor "$rootfs_dst/bin/vi"
    ln -sf /bin/editor "$rootfs_dst/bin/nano"

    log_info "Rootfs artifacts collected"
}

# Create initramfs
create_initramfs() {
    local arch=$1

    log_step "Creating initramfs for $arch..."

    local initramfs_dir="$BUILD_DIR/initramfs"
    local initramfs_dst="$BUILD_DIR/rootfs/boot/initramfs-rustica-$arch.img"

    # Create initramfs directory structure
    mkdir -p "$initramfs_dir"/{bin,lib,proc,sys,dev,etc,root,tmp,var}

    # Copy essential binaries
    cp -v "$BUILD_DIR/rootfs/bin/rustica-installer" "$initramfs_dir/bin/"

    # Copy shell and essential tools from host
    local essential_bins=(
        "/bin/sh"
        "/bin/bash"
        "/bin/busybox"  # or standalone tools
    )

    for bin in "${essential_bins[@]}"; do
        if [ -e "$bin" ]; then
            cp -v "$bin" "$initramfs_dir/bin/" 2>/dev/null || true
        fi
    done

    # Copy required libraries
    for bin in "$initramfs_dir/bin"/*; do
        if [ -f "$bin" ]; then
            ldd "$bin" 2>/dev/null | grep -o '/lib.*\.[0-9]+' | while read lib; do
                mkdir -p "$(dirname "$initramfs_dir/$lib")"
                cp -v "$lib" "$initramfs_dir/$lib" 2>/dev/null || true
            done
        fi
    done

    # Create device nodes
    mknod "$initramfs_dir/dev/null" c 1 3
    mknod "$initramfs_dir/dev/zero" c 1 5
    mknod "$initramfs_dir/dev/console" c 5 1
    mknod "$initramfs_dir/dev/tty" c 5 0
    mknod "$initramfs_dir/dev/random" c 1 8
    mknod "$initramfs_dir/dev/urandom" c 1 9

    # Create init script
    cat > "$initramfs_dir/init" << 'EOFINIT'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "Rustica OS Installer"
echo "====================="
echo ""
echo "Starting installer..."
/bin/rustica-installer

# Shell for debugging
exec /bin/sh
EOFINIT

    chmod +x "$initramfs_dir/init"

    # Create initramfs cpio archive
    (cd "$initramfs_dir" && find . | cpio -o -H newc | gzip > "$initramfs_dst")

    log_info "Initramfs created: $initramfs_dst"
}

# Configure bootloader
configure_bootloader() {
    local arch=$1

    log_step "Configuring bootloader for $arch..."

    local bootloader_type=$(echo "${ARCH_CONFIG[$arch]}" | cut -d'|' -f3)
    local boot_dir="$BUILD_DIR/rootfs/boot"
    local config_dir="$CONFIGS_DIR/$arch"

    mkdir -p "$config_dir"

    case "$bootloader_type" in
        grub)
            configure_grub "$arch"
            ;;
        uboot)
            configure_uboot "$arch"
            ;;
        opensbi)
            configure_opensbi "$arch"
            ;;
    esac
}

# Configure GRUB for amd64
configure_grub() {
    local arch=$1
    local config_dir="$CONFIGS_DIR/$arch"
    local boot_dir="$BUILD_DIR/rootfs/boot/grub"

    mkdir -p "$boot_dir"

    cat > "$config_dir/grub.cfg" << 'EOFGRUB'
set timeout=5
set default=0

menuentry "Rustica OS Installer" {
    insmod gzio
    insmod part_gpt
    insmod ext2

    echo "Loading kernel..."
    linux /boot/vmlinuz-rustica-amd64 console=ttyS0,115200 quiet
    echo "Loading initramfs..."
    initrd /boot/initramfs-rustica-amd64.img
}

menuentry "Rustica OS Installed System" {
    insmod gzio
    insmod part_gpt
    insmod ext2

    echo "Loading kernel..."
    linux /boot/vmlinuz-rustica root=/dev/sda2 ro quiet
    echo "Loading initramfs..."
    initrd /boot/initramfs-rustica.img
}
EOFGRUB

    cp "$config_dir/grub.cfg" "$boot_dir/grub.cfg"

    log_info "GRUB configured for $arch"
}

# Configure U-Boot for ARM64
configure_uboot() {
    local arch=$1
    local config_dir="$CONFIGS_DIR/$arch"

    cat > "$config_dir/boot.cmd" << 'EOFUBOOT'
# U-Boot boot script for Rustica OS ARM64

setenv bootargs 'console=ttyAMA0,115200n8 root=/dev/mmcblk0p2 rootfstype=ext4 rw quiet'
setenv kernel_addr 0x80080000
setenv initrd_addr 0x84000000

echo "Loading Rustica OS kernel..."
load mmc 0:1 ${kernel_addr} /boot/vmlinuz-rustica-arm64
load mmc 0:1 ${initrd_addr} /boot/initramfs-rustica-arm64.img

echo "Booting..."
bootz ${kernel_addr} - ${initrd_addr}
EOFUBOOT

    mkimage -A arm64 -O linux -T script -C none -a 0 -e 0 -n "Rustica OS Boot" -d "$config_dir/boot.cmd" "$config_dir/boot.scr" 2>/dev/null || true

    log_info "U-Boot configured for $arch"
}

# Configure OpenSBI for RISC-V
configure_opensbi() {
    local arch=$1
    local config_dir="$CONFIGS_DIR/$arch"

    cat > "$config_DIR/boot.cfg" << 'EOFOPENSBI'
# OpenSBI + EFI Boot configuration for Rustica OS RISC-V

# Platform-specific settings
setenv platform riscv64
setenv fw_payload_path /boot/vmlinuz-rustica-riscv64
setenv fw_payload_args 'console=ttyS0,115200 root=/dev/vda2 rootfstype=ext4 ro quiet'
EOFOPENSBI

    log_info "OpenSBI configured for $arch"
}

# Build ISO image for amd64
build_iso_amd64() {
    log_step "Building amd64 ISO image..."

    local iso_dir="$BUILD_DIR/iso"
    local iso_output="$IMAGES_DIR/rustica-installer-amd64-${VERSION}.iso"

    mkdir -p "$iso_dir"

    # Copy bootloader and kernel
    cp -r "$BUILD_DIR/rootfs/boot" "$iso_dir/"

    # Create EFI directory structure
    mkdir -p "$iso_dir/EFI/BOOT"

    # Create GRUB EFI image
    if command -v grub-mkrescue &> /dev/null; then
        grub-mkrescue -o "$iso_output" \
            --boot_catalog boot/catalog \
            --boot-load-size 4 \
            -V "RUSTICA_INSTALLER_AMD64" \
            -boot-load-segment 0 \
            -boot-catalog-hidden \
            -boot-info-table \
            -iso-level 3 \
            "$iso_dir" 2>/dev/null || {
            log_warn "grub-mkrescue failed, using genisoimage..."
            genisoimage -o "$iso_output" \
                -V "RUSTICA_INSTALLER_AMD64" \
                -b boot/grub/grub_eltorito.img \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -iso-level 3 \
                "$iso_dir"
        }
    else
        log_error "Neither grub-mkrescue nor genisoimage found"
        log_warn "Creating raw disk image instead..."
        build_disk_image "amd64"
        return 0
    fi

    # Generate checksum
    sha256sum "$iso_output" > "${iso_output}.sha256"

    log_info "amd64 ISO created: $iso_output"
}

# Build disk image for ARM64/RISC-V
build_disk_image() {
    local arch=$1
    local disk_size="${DISK_SIZE:-2G}"
    local img_output="$IMAGES_DIR/rustica-installer-${arch}-${VERSION}.img"

    log_step "Building $arch disk image ($disk_size)..."

    # Create raw disk image
    dd if=/dev/zero of="$img_output" bs=1 count=0 seek="$disk_size" 2>/dev/null

    # Create partition table
    parted "$img_output" mklabel gpt 2>/dev/null || true
    parted "$img_output" mkpart primary fat32 1MiB 256MiB 2>/dev/null || true
    parted "$img_output" mkpart primary ext4 256MiB 100% 2>/dev/null || true
    parted "$img_output" set 1 boot on 2>/dev/null || true

    # Setup loop device
    local loop_dev
    loop_dev=$(losetup -f)
    losetup "$loop_dev" "$img_output"
    partprobe "$loop_dev" 2>/dev/null || true

    # Format partitions
    mkfs.vfat -F32 "${loop_dev}p1" 2>/dev/null || true
    mkfs.ext4 -F "${loop_dev}p2" 2>/dev/null || true

    # Mount partitions
    local mount_dir="$BUILD_DIR/mount"
    mkdir -p "$mount_dir"
    mount "${loop_dev}p2" "$mount_dir" 2>/dev/null || true
    mkdir -p "$mount_dir/boot"
    mount "${loop_dev}p1" "$mount_dir/boot" 2>/dev/null || true

    # Copy files
    cp -r "$BUILD_DIR/rootfs"/* "$mount_dir/"

    # Install bootloader
    case "$arch" in
        amd64)
            if command -v grub-install &> /dev/null; then
                grub-install --boot-directory="$mount_dir/boot" --target=i386-pc "$loop_dev" 2>/dev/null || true
            fi
            ;;
        arm64|riscv64)
            # Copy U-Boot or OpenSBI files
            cp "$CONFIGS_DIR/$arch/"* "$mount_dir/boot/" 2>/dev/null || true
            ;;
    esac

    # Unmount and cleanup
    umount "$mount_dir/boot" 2>/dev/null || true
    umount "$mount_dir" 2>/dev/null || true
    losetup -d "$loop_dev" 2>/dev/null || true
    rm -rf "$mount_dir"

    # Generate checksum
    sha256sum "$img_output" > "${img_output}.sha256"

    log_info "$arch disk image created: $img_output"
}

# Build specific architecture
build_arch() {
    local arch=$1

    log_step "Building $arch installer..."
    echo ""

    init_dirs
    collect_kernel "$arch"
    collect_rootfs "$arch"
    create_initramfs "$arch"
    configure_bootloader "$arch"

    if [ "$arch" = "amd64" ]; then
        build_iso_amd64
    else
        build_disk_image "$arch"
    fi

    echo ""
    log_info "$arch installer build complete!"
}

# Run QEMU validation
run_validation() {
    local arch="${1:-amd64}"

    log_step "Running QEMU validation for $arch..."

    if [ -x "$VALIDATION_DIR/qemu-test.sh" ]; then
        "$VALIDATION_DIR/qemu-test.sh" "$arch"
    else
        log_warn "Validation script not found"
    fi
}

# Generate build manifest
generate_manifest() {
    local manifest="$IMAGES_DIR/MANIFEST-${BUILD_DATE}.txt"

    cat > "$manifest" << EOFMANIFEST
Rustica OS Installer Build Manifest
===================================

Version: $VERSION
Build Date: $(date -d "$BUILD_DATE" '+%Y-%m-%d %H:%M:%S')
Build Host: $(hostname)

Architectures Built:
$(cd "$IMAGES_DIR" && ls -1 *.iso *.img 2>/dev/null | while read f; do echo "  - $f"; done)

Checksums:
EOFMANIFEST

    for img in "$IMAGES_DIR"/*.{iso,img}; do
        if [ -f "$img" ]; then
            local checksum=$(sha256sum "$img" | cut -d' ' -f1)
            echo "  $(basename $img): $checksum" >> "$manifest"
        fi
    done

    cat >> "$manifest" << EOFMANIFEST

Build Configuration:
  - Kernel: $REPO_ROOT/kernel
  - Apps: $REPO_ROOT/apps
  - Installer: $SCRIPT_DIR

Testing:
  - Validation: $VALIDATION_DIR/qemu-test.sh

Supported Architectures:
  - amd64: GRUB BIOS/UEFI boot
  - arm64: U-Boot + EFI boot
  -riscv64: OpenSBI + EFI boot
EOFMANIFEST

    log_info "Build manifest created: $manifest"
}

# Main build function
main() {
    local arch="${1:-all}"
    local validate=false
    local clean=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --validate)
                validate=true
                shift
                ;;
            --clean)
                clean=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                arch="$1"
                shift
                ;;
        esac
    done

    # Clean if requested
    if [ "$clean" = true ]; then
        clean_build
    fi

    echo "======================================"
    echo "Rustica OS Installer Build"
    echo "======================================"
    echo "Version: $VERSION"
    echo "Architecture: $arch"
    echo "Build Date: $(date)"
    echo ""

    # Build specified architectures
    if [ "$arch" = "all" ]; then
        for a in amd64 arm64 riscv64; do
            build_arch "$a"
            echo ""
        done
    else
        build_arch "$arch"
        echo ""
    fi

    # Generate manifest
    generate_manifest

    # Run validation if requested
    if [ "$validate" = true ]; then
        if [ "$arch" = "all" ]; then
            for a in amd64 arm64 riscv64; do
                run_validation "$a"
            done
        else
            run_validation "$arch"
        fi
    fi

    echo ""
    echo "======================================"
    echo "Build Complete!"
    echo "======================================"
    echo ""
    echo "Images location: $IMAGES_DIR"
    echo ""
    ls -lh "$IMAGES_DIR"/*.{iso,img} 2>/dev/null || echo "No images found"
    echo ""
}

# Run main
main "$@"
