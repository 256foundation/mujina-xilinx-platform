#!/bin/bash
#
# Mujina Xilinx - Ramdisk Update Script
#
# Updates an already-installed Mujina system with a new ramdisk
# Works with all Xilinx Zynq-based Bitmain miners
# Usage: ./mujina_ramdisk_update.sh [miner_ip]
#

set -euo pipefail

# Configuration
readonly MINER_IP="${1:-}"
if [[ -z "$MINER_IP" ]]; then
    echo "Usage: $0 <miner_ip>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi
readonly MINER_USER="root"
readonly MINER_PASS="root"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly RAMDISK_PATH="$PROJECT_ROOT/buildroot/output/images/ramdisk.itb"

# SSH options
readonly SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'

# Helper functions
log() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; exit 1; }
step() { warn "[$1/5] $2"; }

ssh_exec() { sshpass -p "$MINER_PASS" ssh $SSH_OPTS "${MINER_USER}@${MINER_IP}" "$@"; }
upload() { cat "$1" | ssh_exec "cat > $2"; }

# Validate ramdisk
[[ -f "$RAMDISK_PATH" ]] || error "Ramdisk not found at $RAMDISK_PATH\nRun 'make' first"

echo -e "${CYAN}===================================================${NC}"
echo -e "${CYAN}  Mujina Xilinx - Ramdisk Update${NC}"
echo -e "${CYAN}  Target: $MINER_IP${NC}"
echo -e "${CYAN}===================================================${NC}"
echo

RAMDISK_SIZE=$(stat -c%s "$RAMDISK_PATH")
RAMDISK_SHA256=$(sha256sum "$RAMDISK_PATH" | awk '{print $1}')

echo "Ramdisk: $RAMDISK_PATH ($RAMDISK_SIZE bytes, $((RAMDISK_SIZE / 1024 / 1024))MB)"
echo "SHA256: $RAMDISK_SHA256"
echo

# Create 256-byte signature (SHA256 hash + zero padding)
{
    echo -n "$RAMDISK_SHA256" | xxd -r -p
    dd if=/dev/zero bs=1 count=$((256 - 32)) 2>/dev/null
} > /tmp/ramdisk.sig

# Upload ramdisk and signature
warn "\nUploading ramdisk and signature..."
upload "$RAMDISK_PATH" /tmp/ramdisk.itb
upload /tmp/ramdisk.sig /tmp/ramdisk.sig

# Install to NAND
warn "\nInstalling to NAND..."
step 1 "Erasing mtd1 (ramdisk partition)..."
ssh_exec "flash_erase /dev/mtd1 0 0 2>&1 | tail -1"

step 2 "Writing ramdisk to mtd1..."
ssh_exec "nandwrite -p -s 0x0 /dev/mtd1 /tmp/ramdisk.itb 2>&1 | tail -1"

step 3 "Dumping current mtd3 (signature partition)..."
ssh_exec "nanddump /dev/mtd3 -f /tmp/mtd3.bin 2>&1 | grep -E '(ECC|bad)' || echo '  → Dump complete'"

step 4 "Patching mtd3 with new ramdisk signature..."
ssh_exec << 'EOF'
head -c 1024 /tmp/mtd3.bin > /tmp/sig_head
tail -c +1281 /tmp/mtd3.bin > /tmp/sig_tail
cat /tmp/sig_head /tmp/ramdisk.sig /tmp/sig_tail > /tmp/mtd3_new.bin
echo "  → mtd3 patched successfully"
EOF

step 5 "Writing patched signatures to mtd3..."
ssh_exec "flash_erase /dev/mtd3 0 0 2>&1 | tail -1"
ssh_exec "nandwrite -p -s 0x0 /dev/mtd3 /tmp/mtd3_new.bin 2>&1 | tail -1"

# Verify installation
warn "\nVerifying installation..."
ssh_exec << 'EOF'
nanddump /dev/mtd3 -s 0 -l 2048 -f /tmp/mtd3_head.bin 2>&1 | grep -E "(ECC|bad)" || true
tail -c +1025 /tmp/mtd3_head.bin | head -c 256 > /tmp/sig_from_nand.bin

SIG_MD5=$(md5sum /tmp/ramdisk.sig | awk '{print $1}')
NAND_SIG_MD5=$(md5sum /tmp/sig_from_nand.bin | awk '{print $1}')

[[ "$SIG_MD5" == "$NAND_SIG_MD5" ]] && echo "  ✓ Signature verification passed (MD5: $SIG_MD5)" || {
    echo "  ✗ Signature verification FAILED!"
    exit 1
}

# Cleanup
rm -f /tmp/{ramdisk.itb,ramdisk.sig,mtd3.bin,sig_head,sig_tail,mtd3_new.bin,mtd3_head.bin,sig_from_nand.bin}
echo -e "\n  Update complete!"
EOF

log "\n==================================================="
log "  Update Successful!"
log "==================================================="
echo "Rebooting miner in 3 seconds..."
echo "SSH will be available at root@$MINER_IP (password: root)"
echo
sleep 3

echo "Rebooting..."
ssh_exec "reboot" || true
log "Miner is rebooting."
