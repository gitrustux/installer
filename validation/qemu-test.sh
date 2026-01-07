#!/usr/bin/env bash
#
# QEMU Validation Script for Rustica OS Installer
#
# Tests installer images in QEMU and verifies installation
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="$(dirname "$SCRIPT_DIR")/images"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Architecture-specific QEMU configurations
qemu_cmd() {
    local arch=$1

    case "$arch" in
        amd64)
            echo "qemu-system-x86_64"
            ;;
        arm64)
            echo "qemu-system-aarch64"
            ;;
        riscv64)
            echo "qemu-system-riscv64"
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

# Test installer for architecture
test_installer() {
    local arch=$1
    local qemucmd=$(qemu_cmd "$arch")

    log_info "Testing $arch installer..."

    # Find installer image
    local installer_img
    installer_img=$(ls -1 "$IMAGES_DIR"/rustica-installer-${arch}-*.img 2>/dev/null | head -1)
    installer_iso=$(ls -1 "$IMAGES_DIR"/rustica-installer-${arch}-*.iso 2>/dev/null | head -1)

    if [ -z "$installer_img" ] && [ -z "$installer_iso" ]; then
        log_error "No installer image found for $arch"
        return 1
    fi

    # Create test disk
    local test_disk="$IMAGES_DIR/test-${arch}-disk.img"
    rm -f "$test_disk"
    qemu-img create -f raw "$test_disk" 4G 2>/dev/null || true

    # QEMU common options
    local qemu_opts=(
        -m 1G
        -smp 2
        -nographic
        -serial mon:stdio
    )

    # Architecture-specific boot
    case "$arch" in
        amd64)
            if [ -n "$installer_iso" ]; then
                log_test "Booting from ISO: $installer_iso"
                timeout 60 $qemucmd "${qemu_opts[@]}" \
                    -cdrom "$installer_iso" \
                    -drive "file=$test_disk,format=raw" \
                    -boot d \
                    2>&1 | tee "/tmp/qemu-${arch}-boot.log" || true
            else
                log_test "Booting from disk image: $installer_img"
                timeout 60 $qemucmd "${qemu_opts[@]}" \
                    -drive "file=$installer_img,format=raw" \
                    -drive "file=$test_disk,format=raw" \
                    -boot c \
                    2>&1 | tee "/tmp/qemu-${arch}-boot.log" || true
            fi
            ;;

        arm64)
            log_test "Booting ARM64 image: $installer_img"
            timeout 60 $qemucmd "${qemu_opts[@]}" \
                -M virt \
                -cpu cortex-a57 \
                -drive "if=virtio,file=$installer_img,format=raw" \
                -drive "if=virtio,file=$test_disk,format=raw" \
                -netdev user,id=net0 \
                -device virtio-net-pci,netdev=net0 \
                -device virtio-rng-pci \
                2>&1 | tee "/tmp/qemu-${arch}-boot.log" || true
            ;;

        riscv64)
            log_test "Booting RISC-V image: $installer_img"
            timeout 60 $qemucmd "${qemu_opts[@]}" \
                -M virt \
                -bios default \
                -drive "if=virtio,file=$installer_img,format=raw" \
                -drive "if=virtio,file=$test_disk,format=raw" \
                -netdev user,id=net0 \
                -device virtio-net-pci,netdev=net0 \
                -device virtio-rng-pci \
                2>&1 | tee "/tmp/qemu-${arch}-boot.log" || true
            ;;
    esac

    # Analyze boot log
    analyze_boot_log "$arch"
}

# Analyze boot log for success/failure
analyze_boot_log() {
    local arch=$1
    local logfile="/tmp/qemu-${arch}-boot.log"

    log_info "Analyzing boot log for $arch..."

    if [ ! -f "$logfile" ]; then
        log_error "Boot log not found"
        return 1
    fi

    local checks=0
    local passed=0

    # Check 1: Kernel loaded
    checks=$((checks + 1))
    if grep -q "Loading kernel" "$logfile"; then
        log_info "✓ Kernel loaded"
        passed=$((passed + 1))
    else
        log_warn "✗ Kernel load not detected"
    fi

    # Check 2: Initramfs loaded
    checks=$((checks + 1))
    if grep -q "Loading initramfs\|initrd" "$logfile"; then
        log_info "✓ Initramfs loaded"
        passed=$((passed + 1))
    else
        log_warn "✗ Initramfs load not detected"
    fi

    # Check 3: Installer started
    checks=$((checks + 1))
    if grep -q "Rustica OS Installer\|installer" "$logfile"; then
        log_info "✓ Installer detected"
        passed=$((passed + 1))
    else
        log_warn "✗ Installer not detected"
    fi

    # Check 4: No kernel panics
    checks=$((checks + 1))
    if grep -qi "kernel panic\|panic" "$logfile"; then
        log_error "✗ Kernel panic detected"
    else
        log_info "✓ No kernel panics"
        passed=$((passed + 1))
    fi

    # Check 5: System responsive
    checks=$((checks + 1))
    if grep -q "root@\|login\|shell" "$logfile"; then
        log_info "✓ System reached shell/login"
        passed=$((passed + 1))
    else
        log_warn "✗ System did not reach shell"
    fi

    # Summary
    echo ""
    log_info "Test Results: $passed/$checks checks passed"

    if [ $passed -eq $checks ]; then
        log_info "✓ All checks passed for $arch"
        return 0
    else
        log_warn "⚠ Some checks failed for $arch"
        return 1
    fi
}

# Automated installation test
test_installation() {
    local arch=$1

    log_info "Testing automated installation for $arch..."

    # This would involve:
    # 1. Booting installer
    # 2. Sending automated commands via serial
    # 3. Rebooting into installed system
    # 4. Verifying installed system

    log_warn "Full installation test not yet implemented"
    log_warn "Would require expect/serial automation"

    return 0
}

# Generate test report
generate_report() {
    local report="$IMAGES_DIR/test-report-$(date +%Y%m%d-%H%M%S).txt"

    cat > "$report" << EOFREPORT
Rustica OS Installer Test Report
================================

Test Date: $(date)
Test Host: $(hostname)

Architecture Tests:
EOFREPORT

    for arch in amd64 arm64 riscv64; do
        local logfile="/tmp/qemu-${arch}-boot.log"

        if [ -f "$logfile" ]; then
            echo "" >> "$report"
            echo "## $arch" >> "$report"
            echo "--------" >> "$report"

            # Extract key info
            echo "Boot Log: $logfile" >> "$report"
            echo "" >> "$report"

            # Summary from log
            if grep -q "Loading kernel" "$logfile"; then
                echo "Kernel: ✓ Loaded" >> "$report"
            else
                echo "Kernel: ✗ Not loaded" >> "$report"
            fi

            if grep -qi "panic\|error" "$logfile"; then
                echo "Status: ⚠ Errors detected" >> "$report"
            else
                echo "Status: ✓ No critical errors" >> "$report"
            fi
        fi
    done

    cat >> "$report" << EOFREPORT

Next Steps:
- Review boot logs in /tmp/qemu-*-boot.log
- Run interactive QEMU tests for detailed debugging
- Test automated installation sequence

Test Environment:
- QEMU Version: $(qemu-system-x86_64 --version 2>&1 | head -1)
- Architecture: $(uname -m)
EOFREPORT

    log_info "Test report created: $report"
}

# Main
main() {
    local arch="${1:-amd64}"

    echo "======================================"
    echo "QEMU Validation for Rustica OS"
    echo "======================================"
    echo ""

    if [ "$arch" = "all" ]; then
        for a in amd64 arm64 riscv64; do
            test_installer "$a"
            echo ""
            sleep 2
        done
    else
        test_installer "$arch"
        echo ""
    fi

    generate_report

    echo ""
    log_info "Validation complete!"
    echo "Logs: /tmp/qemu-*-boot.log"
}

main "$@"
