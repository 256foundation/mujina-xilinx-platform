#!/bin/bash
#
# Post-image script for ramdisk-only build
#

set -euo pipefail

readonly BOARD_DIR="$(dirname "$0")"

echo "==================================="
echo "  Ramdisk Build"
echo "==================================="
echo

# Validate rootfs exists
[[ -f "${BINARIES_DIR}/rootfs.ext2" ]] || { echo "ERROR: rootfs.ext2 not found!"; exit 1; }

# Compress rootfs
echo "Compressing rootfs.ext2..."
gzip -9 -f "${BINARIES_DIR}/rootfs.ext2" -c > "${BINARIES_DIR}/rootfs.ext2.gz"
echo "  Created: rootfs.ext2.gz ($(stat -c%s ${BINARIES_DIR}/rootfs.ext2.gz) bytes)"

# Create FIT ramdisk
echo
echo "Creating FIT ramdisk image..."
cp "${BOARD_DIR}/ramdisk-fit.its" "${BINARIES_DIR}/"
mkimage -f "${BINARIES_DIR}/ramdisk-fit.its" "${BINARIES_DIR}/ramdisk.itb" > /dev/null

RAMDISK_SIZE=$(stat -c%s "${BINARIES_DIR}/ramdisk.itb")
echo "  Created: ramdisk.itb (${RAMDISK_SIZE} bytes, FIT format)"
echo

# Create build info
cat > "${BINARIES_DIR}/BUILD_INFO.txt" << EOF
Ramdisk Build
==========================================

Build Date: $(date)
Build Type: Stock Kernel + Custom Ramdisk

Output Files:
  ramdisk.itb               - FIT image for NAND installation
  rootfs.ext2               - Uncompressed ext2 filesystem
  rootfs.ext2.gz            - Compressed ramdisk
  rootfs.tar                - TAR archive of rootfs

Installation:
  ./scripts/bitmain_ramdisk_install.sh [miner_ip]    # First-time install (stock firmware)
  ./scripts/mujina_ramdisk_update.sh [miner_ip]      # Update existing Mujina installation

Stock Kernel: 4.6.0-xilinx-g03c746f7 (from NAND @ 0x2000000)
Stock Modules:
  - bitmain_axi.ko (7.3KB)
  - fpga_mem_driver.ko (7.8KB)

NAND Memory Layout:
  0x00000000 - Stock BOOT.bin (FSBL + bitstream + U-Boot) - PRESERVED
  0x001A0000 - Stock devicetree.dtb - PRESERVED
  0x02000000 - Stock uImage (kernel 4.6.0) - PRESERVED
  0x02800000 - Custom ramdisk.itb - REPLACED (mtd1)

Custom Ramdisk Size: ${RAMDISK_SIZE} bytes
EOF

echo "==================================="
echo "  Build Complete"
echo "==================================="
echo
echo "Output directory: ${BINARIES_DIR}"
echo "Ramdisk FIT image: ramdisk.itb (${RAMDISK_SIZE} bytes)"
echo
