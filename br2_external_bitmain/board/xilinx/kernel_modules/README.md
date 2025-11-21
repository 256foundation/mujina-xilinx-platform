# Stock Bitmain Kernel Modules

This directory contains stock kernel modules extracted from Bitmain firmware, stored in the repository for convenience.

## Included Modules

-   `bitmain_axi.ko` (7.3KB) - FPGA register access driver (creates /dev/axi_fpga_dev)
-   `fpga_mem_driver.ko` (7.8KB) - FPGA memory buffer driver (creates /dev/fpga_mem)

These modules are **binary-only** and were extracted from stock Bitmain firmware.
They are included in this repository to simplify the build process.

## Module Details

### bitmain_axi.ko

-   Size: ~7.3 KB
-   Creates: `/dev/axi_fpga_dev` character device
-   Memory region: 4608 bytes of FPGA registers

### fpga_mem_driver.ko

-   Size: ~7.8 KB
-   Creates: `/dev/fpga_mem` character device
-   Memory region: 16 MB DMA buffer space
-   Load parameters: `mem_start=0x0F000000 mem_size=0x1000000` (for 256MB RAM)

## Loading

Modules are auto-loaded by `/etc/init.d/S10modules` during boot.
