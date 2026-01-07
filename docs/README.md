# Rustica OS Installer

Automated build and validation system for Rustica OS installer images across multiple architectures.

## Overview

The installer creates bootable images that can install Rustux Kernel + Rustica Base System onto target disks for:
- **amd64** (x86_64)
- **arm64** (AArch64)
- **riscv64** (RISC-V 64-bit)

## Directory Structure

```
installer/
├── build/              # Temporary build directory
│   ├── rootfs/        # Root filesystem
│   ├── initramfs/     # Installer initramfs
│   ├── bootloader/    # Bootloader files
│   └── iso/           # ISO image staging
├── scripts/           # Build and automation scripts
│   ├── build-all.sh  # Main build script
│   └── build-arch.sh # Per-architecture build
├── images/           # Output installer images
│   ├── rustica-installer-amd64-0.1.0.iso
│   ├── rustica-installer-arm64-0.1.0.img
│   └── rustica-installer-riscv64-0.1.0.img
├── configs/          # Architecture-specific configs
│   ├── amd64/
│   │   └── grub.cfg
│   ├── arm64/
│   │   ├── boot.cmd
│   │   └── boot.scr
│   └── riscv64/
│       └── boot.cfg
├── validation/       # Testing and validation
│   └── qemu-test.sh  # QEMU validation script
└── docs/            # Documentation
    └── README.md     # This file
```

## Quick Start

### Prerequisites

```bash
# Required tools
sudo apt install -y \
    build-essential \
    grub-pc-bin \
    grub-efi-amd64 \
    grub2-common \
    xorriso \
    qemu-system-x86 \
    qemu-system-arm \
    qemu-system-riscv \
    u-boot-tools \
    mtools \
    parted \
    dosfstools \
    cpio \
    gzip

# Rust toolchain (for kernel/apps)
rustup target add x86_64-unknown-linux-gnu
rustup target add aarch64-unknown-linux-gnu
rustup target add riscv64gc-unknown-linux-gnu

# Cross-compilers (optional, for bootloader)
sudo apt install -y gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu
```

### Build All Installers

```bash
# Build all architectures
cd /var/www/rustux.com/prod/installer/scripts
./build-all.sh all

# Build specific architecture
./build-all.sh amd64

# Build and validate
./build-all.sh all --validate
```

### Build Options

```bash
# Clean build directories
./build-all.sh --clean

# Validate with QEMU after building
./build-all.sh amd64 --validate

# Set custom version
RUSTICA_VERSION=1.0.0 ./build-all.sh all
```

## Architecture Details

### amd64 (x86_64)

**Boot Method**: GRUB (BIOS/UEFI)
**Image Format**: ISO (for optical/USB boot)
**Bootloader**: GRUB2
**Kernel Args**: `console=ttyS0,115200`
**Partition Layout**:
- `/boot` - FAT32 EFI System Partition
- `/` - ext4 root filesystem

**Output**: `rustica-installer-amd64-VERSION.iso`

### arm64 (AArch64)

**Boot Method**: U-Boot + EFI
**Image Format**: Raw disk image
**Bootloader**: U-Boot
**Kernel Args**: `console=ttyAMA0,115200n8`
**Partition Layout**:
- `/boot` - FAT32 (U-Boot environment)
- `/` - ext4 root filesystem

**Output**: `rustica-installer-arm64-VERSION.img`

### riscv64 (RISC-V)

**Boot Method**: OpenSBI + EFI
**Image Format**: Raw disk image
**Bootloader**: OpenSBI + EFI loader
**Kernel Args**: `console=ttyS0,115200`
**Partition Layout**:
- `/boot` - FAT32 (firmware)
- `/` - ext4 root filesystem

**Output**: `rustica-installer-riscv64-VERSION.img`

## Installer Components

### Kernel Artifacts

Collected from: `/var/www/rustux.com/prod/kernel/target/<triple>/release/`

- `vmlinuz-rustica-<arch>` - Kernel binary
- `initramfs-rustica-<arch>.img` - Initial ramdisk

### Root Filesystem

Minimal Linux environment containing:

**Essential Binaries**:
- `/bin/rpg` - Package manager
- `/bin/pkg` - Package manager (compat)
- `/bin/login` - Login utility
- `/bin/rustica-installer` - Installer script
- `/bin/sh`, `/bin/bash` - Shells

**System Utilities**:
- `ip` - Network configuration
- `fwctl` - Firewall control
- `tar` - Archive utility
- `editor` - Text editor
- `capctl`, `sbctl`, `bootctl` - System tools

**Directory Structure**:
```
/
├── bin/        # User binaries
├── sbin/       # System binaries
├── etc/        # Configuration
├── home/       # User home directories
├── root/       # Root user home
├── usr/        # User data
│   ├── bin/
│   ├── sbin/
│   └── lib/
├── var/        # Variable data
│   ├── lib/
│   ├── cache/
│   └── log/
├── tmp/        # Temporary files
├── boot/       # Kernel and bootloader
├── proc/       # Kernel FS (mount point)
├── sys/        # Kernel FS (mount point)
├── dev/        # Device FS (mount point)
└── mnt/        # Mount points
```

### Initramfs

Installer initramfs includes:
- Essential binaries (installer, shell, tools)
- Shared libraries
- Device nodes
- Init script to launch installer
- Storage tools (lsblk, blkid, mkfs, mount)

## Validation

### Automated QEMU Testing

```bash
cd /var/www/rustux.com/prod/installer/validation

# Test specific architecture
./qemu-test.sh amd64

# Test all architectures
./qemu-test.sh all
```

### QEMU Configuration

**amd64**:
```bash
qemu-system-x86_64 \
  -m 1G \
  -smp 2 \
  -nographic \
  -serial mon:stdio \
  -cdrom rustica-installer-amd64.iso \
  -boot d
```

**arm64**:
```bash
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a57 \
  -m 1G \
  -smp 2 \
  -nographic \
  -serial mon:stdio \
  -drive file=rustica-installer-arm64.img,format=raw,if=virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

**riscv64**:
```bash
qemu-system-riscv64 \
  -M virt \
  -bios default \
  -m 1G \
  -smp 2 \
  -nographic \
  -serial mon:stdio \
  -drive file=rustica-installer-riscv64.img,format=raw,if=virtio \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0
```

## Manual Installation Process

1. **Boot Installer** - Boot from USB/CD/image
2. **Select Target Disk** - Choose installation target
3. **Partition Disk** - Create partition table and partitions
4. **Format Partitions** - Create filesystems
5. **Install Files** - Copy rootfs and kernel
6. **Install Bootloader** - Configure boot manager
7. **Configure System** - Generate /etc/fstab, network config
8. **Reboot** - Reboot into installed system

## Bootloader Configuration

### GRUB (amd64)

Config file: `configs/amd64/grub.cfg`

```grub
set timeout=5
set default=0

menuentry "Rustica OS" {
    linux /boot/vmlinuz-rustica-amd64 root=/dev/sda2 ro quiet
    initrd /boot/initramfs-rustica-amd64.img
}
```

### U-Boot (arm64)

Config file: `configs/arm64/boot.scr`

```
setenv bootargs 'console=ttyAMA0,115200n8 root=/dev/mmcblk0p2 rw'
load mmc 0:1 ${kernel_addr} /boot/vmlinuz-rustica-arm64
bootz ${kernel_addr}
```

### OpenSBI (riscv64)

Config file: `configs/riscv64/boot.cfg`

```
setenv fw_payload_path /boot/vmlinuz-rustica-riscv64
setenv fw_payload_args 'console=ttyS0,115200 root=/dev/vda2 rw'
```

## Troubleshooting

### Build Issues

**Kernel binary not found**:
```bash
# Build kernel first
cd /var/www/rustux.com/prod/kernel
cargo build --release --target x86_64-unknown-linux-gnu
```

**Missing GRUB tools**:
```bash
sudo apt install grub-pc-bin grub-efi-amd64 xorriso
```

**Permission denied creating device nodes**:
```bash
# Run build script with sudo
sudo ./build-all.sh amd64
```

### QEMU Issues

**QEMU not installed**:
```bash
sudo apt install qemu-system-x86 qemu-system-arm qemu-system-riscv
```

**Image too large**:
```bash
# Increase disk size
DISK_SIZE=4G ./build-all.sh arm64
```

**Boot hangs**:
- Check serial console output
- Verify initramfs includes all required binaries
- Test with `-serial file:/tmp/debug.log` for capturing output

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build Installers

on:
  push:
    paths:
      - 'kernel/**'
      - 'apps/**'
      - 'installer/**'

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        arch: [amd64, arm64, riscv64]

    steps:
      - uses: actions/checkout@v2

      - name: Install dependencies
        run: |
          sudo apt update
          sudo apt install -y grub-pc-bin xorriso qemu-system-x86

      - name: Install Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          targets: ${{ matrix.arch }}

      - name: Build installer
        run: |
          cd installer/scripts
          ./build-all.sh ${{ matrix.arch }}

      - name: Validate with QEMU
        run: |
          cd installer/validation
          ./qemu-test.sh ${{ matrix.arch }}

      - name: Upload artifacts
        uses: actions/upload-artifact@v2
        with:
          name: rustica-installer-${{ matrix.arch }}
          path: installer/images/*.{iso,img}
```

## Future Enhancements

### Phase 2: GUI Installer
- Graphical installation using GTK/WebKit
- Mouse-driven partitioning
- Visual progress indicators

### Phase 3: Advanced Features
- LUKS encryption support
- Network installation (HTTP/FTP)
- Automated/unattended installation
- Dual-boot detection and configuration
- Recovery partition creation

### Phase 4: Cloud Integration
- Cloud image builds (AWS, Azure, GCP)
- OpenStack images
- Container images (Docker, Podman)

## Contributing

To add support for new architectures:

1. Add configuration to `ARCH_CONFIG` in `build-all.sh`
2. Create config files in `configs/<arch>/`
3. Add QEMU test configuration to `qemu-test.sh`
4. Update this README

## License

MIT License - See LICENSE file for details

---

**Last Updated**: January 7, 2025
**Version**: 0.1.0
