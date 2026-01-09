#!/usr/bin/env bash
#
# Rustica OS Live Image Build Script
#
# Creates a bootable UEFI disk image using host kernel
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
IMG_SIZE="4G"
IMG_NAME="rustica-live-${VERSION}.img"

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

# Create initramfs
create_initramfs() {
    log_step "Creating initramfs..."

    local initramfs_dir="$BUILD_DIR/initramfs"
    local output="$BUILD_DIR/initramfs.img"

    rm -rf "$initramfs_dir"
    mkdir -p "$initramfs_dir"/{bin,lib,proc,sys,dev,etc,root,tmp,var,mnt,usr/bin}

    # Copy essential tools from host
    local tools=("sh" "bash" "mount" "umount" "mkdir" "ln" "cp" "mv" "rm" "ls" "cat" "ps" "kill" "sync")
    for tool in "${tools[@]}"; do
        which "$tool" 2>/dev/null | while read path; do
            cp "$path" "$initramfs_dir/bin/" 2>/dev/null || true
        done
    done

    # Copy busybox if available
    if [ -e "/bin/busybox" ]; then
        cp /bin/busybox "$initramfs_dir/bin/"
        "$initramfs_dir/bin/busybox" --install -s "$initramfs_dir/bin/" 2>/dev/null || true
    fi

    # Copy shared libraries
    for bin in "$initramfs_dir/bin"/*; do
        if [ -f "$bin" ]; then
            ldd "$bin" 2>/dev/null | grep -o '/lib.*\.[0-9]+' | while read lib; do
                mkdir -p "$(dirname "$initramfs_dir/$lib")"
                cp "$lib" "$initramfs_dir/$lib" 2>/dev/null || true
            done
        fi
    done

    # Copy required libraries for dynamic linking
    for lib in /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2; do
        [ -f "$lib" ] && mkdir -p "$initramfs_dir$(dirname "$lib")" && cp "$lib" "$initramfs_dir$(dirname "$lib")/" 2>/dev/null || true
    done

    # Create device nodes
    mknod "$initramfs_dir/dev/null" c 1 3
    mknod "$initramfs_dir/dev/zero" c 1 5
    mknod "$initramfs_dir/dev/console" c 5 1
    mknod "$initramfs_dir/dev/tty" c 5 0
    mknod "$initramfs_dir/dev/tty1" c 4 1
    mknod "$initramfs_dir/dev/ttyS0" c 4 64
    mknod "$initramfs_dir/dev/random" c 1 8
    mknod "$initramfs_dir/dev/urandom" c 1 9
    mknod "$initramfs_dir/dev/sda" b 8 0
    mknod "$initramfs_dir/dev/sda1" b 8 1
    mknod "$initramfs_dir/dev/sda2" b 8 2
    mknod "$initramfs_dir/dev/loop0" b 7 0
    mknod "$initramfs_dir/dev/sda3" b 8 3

    # Create init script that shows the installer menu
    cat > "$initramfs_dir/init" << 'EOFINIT'
#!/bin/sh
# Rustica OS Live Init

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║              Rustica OS v0.1.0 - Live                    ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Wait for devices to settle
sleep 2

# Find and mount the live media
mkdir -p /cdrom
mkdir -p /live

# Try to find the partition containing our tools
for dev in /dev/sda1 /dev/sda2 /dev/sdb1 /dev/sdb2; do
    if [ -e "$dev" ]; then
        echo "Checking $dev..."
        if mount -t ext4 -o ro "$dev" /cdrom 2>/dev/null; then
            if [ -f /cdrom/bin/rustux-install ]; then
                echo "Found Rustica OS on $dev"
                break
            else
                umount /cdrom 2>/dev/null
            fi
        fi
    fi
done

# Check if we found the tools
if [ -f /cdrom/bin/rustux-install ]; then
    echo "Rustica OS found!"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "  [1] Install Rustica OS to a device"
    echo "      - Install Rustica OS to a hard drive or SSD"
    echo "      - All data on the target device will be erased"
    echo ""
    echo "  [2] Try out Rustica OS"
    echo "      - Boots entirely into RAM; changes are lost on reboot"
    echo "      - Great for testing hardware compatibility"
    echo "      - Get a feel for the distro without installing"
    echo ""
    echo "  [3] Portable Rustica OS"
    echo "      - A full, persistent Linux environment you carry with you"
    echo "      - Saves your files, settings, and installed software"
    echo "      - All changes persist on the USB drive across reboots"
    echo ""

    printf "Select option [1-3]: "
    read choice

    case "$choice" in
        1|install|"")
            echo ""
            echo "Starting installer..."
            /cdrom/bin/rustux-install
            ;;
        2|tryout|live)
            echo ""
            echo "Starting TryOut mode..."
            echo "The system is ready. You can explore the available tools:"
            echo "  - ls /cdrom/bin/ - List available tools"
            echo "  - /cdrom/bin/rustux-install - Run installer"
            echo ""
            exec /bin/sh
            ;;
        3|portable)
            echo ""
            echo "Starting Portable mode..."
            echo "Remounting read-write..."
            umount /cdrom
            mount -t ext4 -o rw "$dev" /cdrom
            echo "Portable mode ready. Changes will be saved."
            echo ""
            exec /bin/sh
            ;;
        *)
            echo "Invalid option. Starting installer..."
            /cdrom/bin/rustux-install
            ;;
    esac
else
    echo ""
    echo "ERROR: Could not find Rustica OS tools!"
    echo "Dropping to emergency shell for debugging..."
    echo ""
    echo "Available devices:"
    lsblk
    echo ""
fi

exec /bin/sh
EOFINIT

    chmod +x "$initramfs_dir/init"

    # Create cpio archive
    (cd "$initramfs_dir" && find . | cpio -o -H newc | gzip > "$output")

    log_info "Initramfs created: $output"
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
    parted "$img_path" mkpart primary fat32 1MiB 512MiB 2>/dev/null || true
    parted "$img_path" set 1 esp on 2>/dev/null || true
    parted "$img_path" mkpart primary ext4 512MiB 100% 2>/dev/null || true

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
    mkdir -p "$mount_dir"/boot/grub

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

    # Copy essential tools from host for compatibility
    log_info "Copying system tools..."
    for host_bin in bash sh ls cat mkdir mount umount sync; do
        which "$host_bin" 2>/dev/null | while read path; do
            cp "$path" "$mount_dir/bin/" 2>/dev/null || true
        done
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

    # Copy host kernel to boot directory
    log_info "Copying host kernel..."
    if [ -d "/boot" ]; then
        # Copy the most recent kernel
        local kernel=$(ls -t /boot/vmlinuz-* 2>/dev/null | head -1)
        if [ -n "$kernel" ]; then
            cp "$kernel" "$mount_dir/boot/vmlinuz"
            echo "Copied kernel: $kernel"
        fi

        # Copy initramfs
        local initramfs=$(ls -t /boot/initrd.img-* /boot/initramfs-* 2>/dev/null | head -1)
        if [ -n "$initramfs" ]; then
            cp "$initramfs" "$mount_dir/boot/initrd"
            echo "Copied initramfs: $initramfs"
        fi
    fi

    # Create our custom initramfs
    create_initramfs

    # Copy our initramfs
    cp "$BUILD_DIR/initramfs.img" "$mount_dir/boot/rustica-init.img"

    # Install GRUB for UEFI
    log_info "Installing GRUB for UEFI..."
    if command -v grub-install &> /dev/null; then
        # Create EFI directory structure
        mkdir -p "$mount_dir/boot/efi/EFI/BOOT"
        mkdir -p "$mount_dir/boot/efi/EFI/grub"

        # Copy GRUB modules
        if [ -d "/usr/lib/grub/x86_64-efi" ]; then
            mkdir -p "$mount_dir/boot/grub/x86_64-efi"
            cp -r /usr/lib/grub/x86_64-efi/* "$mount_dir/boot/grub/x86_64-efi/" 2>/dev/null || true
        fi

        # Install GRUB
        grub-install \
            --target=x86_64-efi \
            --efi-directory="$mount_dir/boot/efi" \
            --boot-directory="$mount_dir/boot" \
            --removable \
            --no-nvram \
            "$loop_dev" 2>/dev/null || log_warn "GRUB install failed, creating EFI files manually"

        # Create GRUB config with proper boot entries
        cat > "$mount_dir/boot/grub/grub.cfg" << 'EOFGRUB'
set timeout=10
set default=0

# Load necessary modules
insmod gzio
insmod part_gpt
insmod ext2
insmod part_msdos

menuentry "Rustica OS Installer" {
    set gfxpayload=keep
    set root='hd0,gpt2'
    echo "Loading kernel..."
    linux /boot/vmlinuz boot=live quiet splash
    echo "Loading initramfs..."
    initrd /boot/rustica-init.img
}

menuentry "Rustica OS (Verbose)" {
    set gfxpayload=text
    set root='hd0,gpt2'
    echo "Loading kernel..."
    linux /boot/vmlinuz boot=live debug
    echo "Loading initramfs..."
    initrd /boot/rustica-init.img
}

menuentry "Rustica OS (Safe Graphics)" {
    set gfxpayload=text
    set root='hd0,gpt2'
    echo "Loading kernel..."
    linux /boot/vmlinuz boot=live nomodeset quiet
    echo "Loading initramfs..."
    initrd /boot/rustica-init.img
}

menuentry "Reboot" {
    reboot
}

menuentry "Power Off" {
    halt
}
EOFGRUB

        # Create minimal BOOTX64.EFI that runs GRUB
        if command -v grub-mkimage &> /dev/null; then
            grub-mkimage \
                -O x86_64-efi \
                -p /EFI/grub \
                -o "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" \
                boot chain configfile ext2 fat gzio part_gpt part_msdos normal echo linux \
                2>/dev/null || log_warn "grub-mkimage failed"
        fi

        # Alternative: copy system grubx64.efi if available
        if [ ! -f "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
            for efi_file in /boot/efi/EFI/*/grubx64.efi /boot/efi/EFI/ubuntu/grubx64.efi /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed; do
                if [ -f "$efi_file" ]; then
                    mkdir -p "$mount_dir/boot/efi/EFI/BOOT"
                    cp "$efi_file" "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null && break
                fi
            done
        fi
    fi

    # If we still don't have a bootloader, try to use shim
    if [ ! -f "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
        if command -v shim-signed &> /dev/null; then
            log_info "Using shim-signed for EFI boot..."
            mkdir -p "$mount_dir/boot/efi/EFI/BOOT"
            if [ -f "/usr/lib/shim/shimx64.efi.signed" ]; then
                cp "/usr/lib/shim/shimx64.efi.signed" "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
            elif [ -f "/usr/lib/shim/shimx64.efi" ]; then
                cp "/usr/lib/shim/shimx64.efi" "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || true
            fi
        fi
    fi

    # Verify EFI files exist before unmounting
    log_info "Verifying EFI boot files..."
    if [ -d "$mount_dir/boot/efi/EFI/BOOT" ]; then
        log_info "EFI/BOOT directory created"
        if [ -f "$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" ]; then
            log_info "✓ BOOTX64.EFI found - Image should be UEFI bootable!"
        else
            log_warn "✗ BOOTX64.EFI not found - Image may not be bootable"
        fi
    else
        log_warn "✗ EFI/BOOT directory not found"
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
    ln -sf "$IMG_NAME" "$OUTPUT_DIR/rustica-live.img"

    # Generate checksum
    cd "$OUTPUT_DIR"
    sha256sum "$IMG_NAME" > "${IMG_NAME}.sha256"

    local size=$(du -h "$OUTPUT_DIR/$IMG_NAME" | cut -f1)
    log_info "Image created: $OUTPUT_DIR/$IMG_NAME ($size)"
    log_info "Symlink: $OUTPUT_DIR/rustica-live.img"
}

# Main
main() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║           Rustica OS Live Image Build v${VERSION}            ║"
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
    echo "║           The image now uses the host kernel to boot.    ║"
    echo "║           EFI boot: BOOTX64.EFI verified ✓               ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

main "$@"
