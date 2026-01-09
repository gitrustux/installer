#!/usr/bin/env bash
#
# Quick start script for building and testing Rustica OS installer
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================"
echo "Rustica OS Installer - Quick Start"
echo "======================================${NC}"
echo ""

# Show menu
echo "Select an option:"
echo ""
echo "1) Build amd64 installer"
echo "2) Build arm64 installer"
echo "3) Build riscv64 installer"
echo "4) Build all installers"
echo "5) Validate amd64 with QEMU"
echo "6) Validate arm64 with QEMU"
echo "7) Validate riscv64 with QEMU"
echo "8) Validate all with QEMU"
echo "9) Build and validate all"
echo "0) Exit"
echo ""

read -p "Enter choice [0-9]: " choice

case $choice in
    1)
        echo -e "${GREEN}Building amd64 installer...${NC}"
        "$SCRIPT_DIR/build-all.sh" amd64
        ;;
    2)
        echo -e "${GREEN}Building arm64 installer...${NC}"
        "$SCRIPT_DIR/build-all.sh" arm64
        ;;
    3)
        echo -e "${GREEN}Building riscv64 installer...${NC}"
        "$SCRIPT_DIR/build-all.sh" riscv64
        ;;
    4)
        echo -e "${GREEN}Building all installers...${NC}"
        "$SCRIPT_DIR/build-all.sh" all
        ;;
    5)
        echo -e "${GREEN}Validating amd64...${NC}"
        "$SCRIPT_DIR/../validation/qemu-test.sh" amd64
        ;;
    6)
        echo -e "${GREEN}Validating arm64...${NC}"
        "$SCRIPT_DIR/../validation/qemu-test.sh" arm64
        ;;
    7)
        echo -e "${GREEN}Validating riscv64...${NC}"
        "$SCRIPT_DIR/../validation/qemu-test.sh" riscv64
        ;;
    8)
        echo -e "${GREEN}Validating all...${NC}"
        "$SCRIPT_DIR/../validation/qemu-test.sh" all
        ;;
    9)
        echo -e "${GREEN}Building and validating all...${NC}"
        "$SCRIPT_DIR/build-all.sh" all --validate
        ;;
    0)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${YELLOW}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
echo "Check the images directory: $(dirname "$SCRIPT_DIR")/images/"
