#!/bin/bash
#
# Mujina Xilinx - NAND Installer with Signature Update
#
# Installs custom ramdisk to mtd1 and patches mtd3 signature partition
# Works with all Xilinx Zynq-based Bitmain miners
# Usage: ./bitmain_ramdisk_install.sh [miner_ip]
#

set -euo pipefail

# Configuration
readonly MINER_IP="${1:-}"
if [[ -z "$MINER_IP" ]]; then
    echo "Usage: $0 <miner_ip>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi
readonly MINER_USER="miner"
readonly MINER_PASS="miner"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly RAMDISK_PATH="$PROJECT_ROOT/buildroot/output/images/ramdisk.itb"
readonly BOARD_DIR="$PROJECT_ROOT/br2_external_bitmain/board/xilinx"

# SSH options
readonly SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Colors
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' NC='\033[0m'

# Helper functions
log() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; exit 1; }
step() { warn "[$1/6] $2"; }

ssh_exec() { sshpass -p "$MINER_PASS" ssh $SSH_OPTS "${MINER_USER}@${MINER_IP}" "$@"; }
ssh_sudo() { ssh_exec "sudo $*"; }
upload() { cat "$1" | ssh_exec "cat > $2 ${3:+&& chmod +x $2}"; }

# Validate ramdisk
[[ -f "$RAMDISK_PATH" ]] || error "Ramdisk not found at $RAMDISK_PATH\nRun 'make' first"

log "==================================================="
log "  Mujina Xilinx - NAND Installer"
log "  Target: $MINER_IP"
log "==================================================="
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

# Step 1: Unlock sudo via daemonc exploit
warn "\nStep 1: Unlocking sudo access..."
ssh_exec << 'EOF'
daemonc ';chown miner /etc/sudoers'
daemonc ';chmod 777 /etc/sudoers'
echo "miner ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
daemonc ';chmod 700 /etc/sudoers'
daemonc ';chown root /etc/sudoers'
EOF

# Step 2: Upload ramdisk, signature, and NAND tools
warn "\nStep 2: Uploading ramdisk and tools..."
upload "$RAMDISK_PATH" /tmp/ramdisk.itb
upload /tmp/ramdisk.sig /tmp/ramdisk.sig
upload "$BOARD_DIR/nandwrite" /tmp/nandwrite exec
upload "$BOARD_DIR/nanddump" /tmp/nanddump exec
upload "$BOARD_DIR/flash_erase" /tmp/flash_erase exec

# Step 3: Install to NAND
warn "\nStep 3: Installing to NAND..."
step 1 "Erasing mtd1 (ramdisk partition)..."
ssh_sudo /tmp/flash_erase /dev/mtd1 0 0 2>&1 | tail -1

step 2 "Writing ramdisk to mtd1..."
ssh_sudo /tmp/nandwrite -p -s 0x0 /dev/mtd1 /tmp/ramdisk.itb 2>&1 | tail -1

step 3 "Dumping current mtd3 (signature partition)..."
ssh_sudo /tmp/nanddump /dev/mtd3 -f /tmp/mtd3.bin 2>&1 | grep -E '(ECC|bad)' || echo "  → Dump complete"

step 4 "Patching mtd3 with new ramdisk signature..."
ssh_exec << 'EOF'
sudo head -c 1024 /tmp/mtd3.bin > /tmp/sig_head
sudo tail -c +1281 /tmp/mtd3.bin > /tmp/sig_tail
sudo cat /tmp/sig_head /tmp/ramdisk.sig /tmp/sig_tail > /tmp/mtd3_new.bin
echo "  → mtd3 patched successfully"
EOF

step 5 "Writing patched signatures to mtd3..."
ssh_sudo /tmp/flash_erase /dev/mtd3 0 0 2>&1 | tail -1
ssh_sudo /tmp/nandwrite -p -s 0x0 /dev/mtd3 /tmp/mtd3_new.bin 2>&1 | tail -1

step 6 "Verifying installation..."
ssh_exec << 'EOF'
sudo /tmp/nanddump /dev/mtd3 -s 0 -l 2048 -f /tmp/mtd3_head.bin 2>&1 | grep -E "(ECC|bad)" || true
tail -c +1025 /tmp/mtd3_head.bin | head -c 256 > /tmp/sig_from_nand.bin

SIG_MD5=$(md5sum /tmp/ramdisk.sig | awk '{print $1}')
NAND_SIG_MD5=$(md5sum /tmp/sig_from_nand.bin | awk '{print $1}')

[[ "$SIG_MD5" == "$NAND_SIG_MD5" ]] && echo "  ✓ Signature verification passed (MD5: $SIG_MD5)" || {
    echo "  ✗ Signature verification FAILED!"
    exit 1
}

# Cleanup
sudo rm -f /tmp/{ramdisk.itb,ramdisk.sig,nandwrite,nanddump,flash_erase,mtd3.bin,sig_head,sig_tail,mtd3_new.bin,ramdisk_verify.bin,mtd3_head.bin,sig_from_nand.bin}
echo -e "\n  Installation complete!"
EOF

log "\n==================================================="
log "  Installation Successful!"
log "==================================================="
echo "Rebooting miner in 3 seconds..."
echo "Watch UART console for boot messages"
echo "After boot, SSH to root@$MINER_IP (password: root)"
echo
sleep 3

echo "Rebooting..."
ssh_exec "sudo reboot" || true
log "Miner is rebooting. Watch UART console."
