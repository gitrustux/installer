#!/usr/bin/env bash
#
# Per-architecture installer build script
# Called by build-all.sh for each architecture
#

set -e

ARCH="${1}"
VERSION="${RUSTICA_VERSION:-0.1.0}"
BUILD_DIR="$(dirname "$0")/../build"
IMAGES_DIR="$(dirname "$0")/../images"

echo "======================================"
echo "Building $ARCH Installer"
echo "======================================"
echo "Version: $VERSION"
echo "Build Directory: $BUILD_DIR"
echo "Output Directory: $IMAGES_DIR"
echo ""

# Validate architecture
case "$ARCH" in
    amd64|arm64|riscv64)
        ;;
    *)
        echo "Error: Unknown architecture: $ARCH"
        echo "Supported: amd64, arm64, riscv64"
        exit 1
        ;;
esac

# Check for kernel binary
KERNEL_BIN="/var/www/rustux.com/prod/kernel/target/*/release/rustux"
if [ ! -f "$KERNEL_BIN" ]; then
    echo "Warning: Kernel binary not found"
    echo "Building kernel..."
    (cd /var/www/rustux.com/prod/kernel && cargo build --release)
fi

# Check for installer binary
INSTALLER_BIN="/var/www/rustux.com/prod/apps/target/release/installer"
INSTALLER_BIN_ALT="/var/www/rustux.com/prod/apps/target/release/rustux-install"

if [ ! -f "$INSTALLER_BIN" ] && [ ! -f "$INSTALLER_BIN_ALT" ]; then
    echo "Warning: Installer binary not found"
    echo "Building installer..."
    (cd /var/www/rustux.com/prod/apps && cargo build --release -p installer)
fi

# Create output directories
mkdir -p "$BUILD_DIR"/{rootfs,initramfs,bootloader,isolinux}
mkdir -p "$IMAGES_DIR"

echo "Build environment ready for $ARCH"
echo "Run: ../scripts/build-all.sh $ARCH"
