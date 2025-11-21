# Mujina Xilinx Platform

Buildroot-based firmware packaging for Xilinx Zynq-7007S based Bitmain miners using **stock kernel + custom ramdisk** architecture to bypass RSA signature verification.

**ASIC mining software**: See [mujina](https://github.com/256foundation/mujina) repository
**Status**: Production packaging system - packages mujina binary for deployment

---

## Quick Facts

| Component           | Status                                                                  |
| ------------------- | ----------------------------------------------------------------------- |
| **Platform**        | Xilinx Zynq-7007S (ARM Cortex-A9 + FPGA)                                |
| **Approach**        | Stock kernel 4.6.0-xilinx + Custom ramdisk                              |
| **Build System**    | Buildroot BR2_EXTERNAL                                                  |
| **Ramdisk Size**    | ~10MB (FIT image format)                                                |
| **Boot Method**     | NAND flash (mtd1 + mtd3 signature update)                               |
| **Key Constraint**  | RSA eFuse lock prevents bootloader/kernel replacement                   |
| **Mining Software** | [Mujina](https://github.com/256foundation/mujina) (separate repository) |

---

## Architecture

### Critical Hardware Constraint

Xilinx control boards have RSA authentication **permanently enabled** in eFuses:

```
EfusePS status bits: 0xC0013C8D
Expected RSA Key Hash: 3545B6DE1FF44EE4295270CC6D0FF730F861DB9CE32F70F2980619FAF0F34DC1
```

**Consequence**: Cannot replace BOOT.bin (bootloader) or kernel - only ramdisk can be customized.

### Solution: Stock Kernel + Custom Ramdisk

```
Boot Chain (RSA-locked components preserved):
┌─────────────────────────────────────┐
│ FSBL (ROM)           ✓ RSA Verified │
│ ├─> FPGA Bitstream   ✓ RSA Verified │
│ ├─> U-Boot           ✓ RSA Verified │
│ └─> Kernel 4.6.0     ✓ RSA Verified │
│      └─> Ramdisk     ✓ SHA256 Only  │ ← Custom firmware
└─────────────────────────────────────┘
```

**Key Insight**: U-Boot verifies ramdisk via SHA256 (not RSA) against mtd3 signature partition. By updating both ramdisk and signature, custom firmware boots successfully.

### NAND Flash Layout

```
Offset         Size    Partition  Content                     Status
──────────────────────────────────────────────────────────────────────
0x00000000     40MB    mtd0       BOOT.bin + kernel           PRESERVED
0x02800000     32MB    mtd1       ramdisk.itb                 REPLACED
0x04800000     8MB     mtd2       configs                     -
0x05000000     2MB     mtd3       signatures (SHA256 @ 1024)  PATCHED
0x05200000     171MB   mtd4       reserve                     -
```

**Installation Method**:

1. Write custom ramdisk to mtd1 (0x2800000)
2. Compute SHA256 hash of ramdisk
3. Update mtd3 bytes 1024-1279 with new SHA256 + zero padding
4. Reboot → U-Boot verifies SHA256 → boot succeeds

---

## Project Structure

This repository **packages** the complete firmware for Xilinx-based Bitmain miners:

```
mujina-xilinx-platform/
├── buildroot/                      # Mainline Buildroot (submodule)
├── br2_external_bitmain/           # BR2_EXTERNAL tree
│   ├── configs/
│   │   └── xilinx_ramdisk_defconfig
│   ├── packages/
│   │   └── mujina/                 # Mujina package definition
│   │       ├── Config.in           # Buildroot package config
│   │       └── mujina.mk           # Package build rules
│   └── board/xilinx/
│       ├── rootfs-overlay/         # Files copied to ramdisk
│       │   ├── lib/modules/        # Stock kernel modules (binaries)
│       │   └── etc/init.d/S10modules
│       ├── kernel_modules/         # Stock .ko files (extract from Bitmain)
│       ├── ramdisk-fit.its         # FIT image template
│       ├── post-build.sh
│       └── post-image-ramdisk.sh
├── scripts/
│   ├── bitmain_ramdisk_install.sh  # First-time installation
│   └── mujina_ramdisk_update.sh    # Update existing install
└── docs/
    └── *.pdf, *.log                # Reverse engineering documentation
```

**Mujina Integration**:

-   **GitHub Releases** (default): Downloads pre-built `mujina` binary
-   **Local Build**: Builds from local mujina repository (requires Rust toolchain)

---

## Quick Start

### Prerequisites

```bash
# Install build dependencies (Ubuntu/Debian)
sudo apt-get install -y \
    build-essential git bc bison flex libssl-dev \
    libncurses5-dev wget cpio python3 unzip rsync

# Clone this repository
git clone https://github.com/256foundation/mujina-xilinx-platform.git
cd mujina-xilinx-platform

# Initialize buildroot submodule
git submodule update --init --recursive
```

### Option 1: Use Pre-built Mujina Binary (Recommended)

```bash
# Configure for ramdisk build with GitHub release
make xilinx_ramdisk_defconfig

# Build firmware (uses pre-built mujina from GitHub)
make  # Uses all CPU cores by default

# Output: buildroot/output/images/ramdisk.itb
```

**Build Time**: 15-30 minutes (16-core desktop, first build)

### Option 2: Build Mujina from Source

```bash
# Clone mujina repository alongside this project
cd ..
git clone https://github.com/256foundation/mujina.git
cd mujina-xilinx-platform

# Configure for local build
make xilinx_ramdisk_defconfig

# Edit .config to use local build
make menuconfig
# Navigate to: External options -> mujina
# Select: "Local build (from source)"
# Save and exit

# Enable Rust toolchain
# (This will be added to config automatically for local build)

# Build firmware
make

# Output: buildroot/output/images/ramdisk.itb
```

---

## Installation to Miner

### First-Time Install (Bitmain → Mujina)

```bash
./scripts/bitmain_ramdisk_install.sh <miner_ip>
# Default IP: 192.168.0.192
# Unlocks sudo via daemonc, installs ramdisk, updates signature, reboots
```

### Update Existing (Mujina → Mujina)

```bash
./scripts/mujina_ramdisk_update.sh <miner_ip>
# Faster update path, assumes root access already configured
```

### After Reboot

```bash
ssh root@<miner_ip>
# Password: root

# Check mujina installation
mujina --version

# Start mining (configure pool settings first)
mujina start
```

---

## Development

### Build Commands

```bash
# Initial setup
make xilinx_ramdisk_defconfig
make                              # Full build

# Incremental builds
make mujina-rebuild               # Rebuild mujina package only (~1 min)
make busybox-menuconfig           # Configure Busybox
make savedefconfig                # Save config changes

# Clean builds
make clean                        # Clean build artifacts
make distclean                    # Complete clean (removes config)
```

### Buildroot Configuration

**Key Settings** (xilinx_ramdisk_defconfig):

-   **Architecture**: ARM Cortex-A9, NEON, VFPv3D16
-   **Toolchain**: Linaro GCC 7.2-2017.11 (ABI compatibility with stock kernel)
-   **Kernel Headers**: 4.6.x (for kernel module compatibility)
-   **Optimization**: `-Os`, LTO enabled (size-critical)
-   **Rootfs**: ext2, 32MB max, gzip compressed → FIT image
-   **Packages**: Minimal (busybox, dropbear, i2c-tools, mtd-utils, gdb)

**Patches Applied**:

-   Dropbear: Disable `getrandom()` to avoid boot blocking (kernel 4.6 has incomplete entropy)

---

## Serial Console Access

**Hardware**: USB-to-TTL adapter (3.3V logic, **NOT 5V**)

**Connection**:

```
Adapter  →  XILINX UART Header
GND      →  GND
RX       →  TX
TX       →  RX
```

**WARNING**: Do NOT connect VCC/5V pin

**Terminal**:

```bash
minicom -D /dev/ttyUSB0 -b 115200
# or
screen /dev/ttyUSB0 115200
```

**Settings**: 115200 baud, 8N1, no flow control

---

## How It Works (Installation Method)

### SHA256 Signature Update

U-Boot verifies ramdisk SHA256 against mtd3 signature partition:

-   **Offset 0-1023**: Kernel signature (RSA, not modified)
-   **Offset 1024-1279**: Ramdisk signature (SHA256, UPDATED)
-   **Offset 1280+**: Additional signatures

**Installation Process**:

1. Compute SHA256 hash of custom ramdisk
2. Create 256-byte signature: SHA256 (32 bytes) + zero padding (224 bytes)
3. Upload ramdisk, signature, NAND tools to miner
4. Erase mtd1, write custom ramdisk
5. Dump mtd3, patch bytes 1024-1279, write back
6. Verify with MD5 checksums
7. Reboot

**Why This Works**:

-   Stock bootloader/kernel remain intact (RSA-signed)
-   U-Boot verifies ramdisk via SHA256 (not RSA)
-   No private RSA key needed - only SHA256 hash update
-   Same method used by other open-source miner firmware projects

**Script**: `scripts/bitmain_ramdisk_install.sh` (automated, includes verification)

---

## Stock Kernel Modules

**Critical**: Using stock kernel 4.6.0-xilinx-g03c746f7 (RSA-signed). Custom modules cannot be compiled without exact kernel source + toolchain match.

**Modules** (extracted from stock firmware):

-   `bitmain_axi.ko` (7.3KB) - FPGA register access via `/dev/axi_fpga_dev`
-   `fpga_mem_driver.ko` (7.8KB) - FPGA memory mapping via `/dev/fpga_mem`

**Init Script** (`S10modules`):

-   Auto-detects RAM size (256MB or 512MB)
-   Loads modules with correct memory offset (0x0F000000 for 256MB RAM)
-   Runs early in boot sequence

---

## Contributing

**Firmware Packaging**: Submit PRs to this repository

**Mining Software**: Submit PRs to [mujina](https://github.com/256foundation/mujina) repository

### Repository Separation

-   **mujina-xilinx-platform** (this repo): Buildroot configuration, rootfs overlay, installation scripts
-   **mujina**: ASIC communication, mining protocol, hardware control, pool connectivity

---

## References

-   [Buildroot User Manual](https://buildroot.org/downloads/manual/manual.html)
-   [Mujina - Bitcoin ASIC Miner](https://github.com/256foundation/mujina)
