# Xilinx Firmware - Top Level Makefile
BUILDROOT_DIR := buildroot
EXTERNAL_DIR := br2_external_bitmain
BR2_EXTERNAL := $(CURDIR)/$(EXTERNAL_DIR)

# Use all CPU cores by default if -j is not specified
ifeq ($(filter -j%, $(MAKEFLAGS)),)
MAKEFLAGS += -j$(shell nproc)
endif

.PHONY: all menuconfig clean distclean help

all:
	@$(MAKE) $(MAKEFLAGS) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL)

menuconfig:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) menuconfig

# Ramdisk-only build
xilinx_ramdisk_defconfig:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) xilinx_ramdisk_defconfig

busybox-menuconfig:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) busybox-menuconfig

mujina-rebuild:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) mujina-rebuild

mujina-reconfigure:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) mujina-reconfigure

savedefconfig:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) savedefconfig
	@echo "Defconfig saved to $(EXTERNAL_DIR)/configs/xilinx_ramdisk_defconfig"

clean:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) clean

distclean:
	@$(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) distclean
