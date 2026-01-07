# Rustica OS Installer

Automated build system for creating bootable Rustica OS installer images across multiple architectures.

## Quick Start

```bash
# Build all installers
cd scripts
./build-all.sh all

# Validate with QEMU
cd ../validation
./qemu-test.sh all
```

## Documentation

See [docs/README.md](docs/README.md) for comprehensive documentation.

## Architectures

- **amd64** (x86_64) - GRUB BIOS/UEFI boot, ISO image
- **arm64** (AArch64) - U-Boot + EFI, disk image
- **riscv64** (RISC-V) - OpenSBI + EFI, disk image

## Build Scripts

- `build-all.sh` - Build all architectures
- `build-arch.sh` - Per-architecture builder
- `quick-start.sh` - Interactive menu

## Validation

- `validation/qemu-test.sh` - Automated QEMU testing

## License

MIT License - See LICENSE file for details.

## Repository

- **Homepage**: https://rustux-os.org
- **Source**: https://github.com/gitrustux/installer
