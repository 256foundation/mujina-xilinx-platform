################################################################################
#
# mujina - Bitcoin ASIC miner software
#
# Build ASIC communication and mining protocol implementation
# Supports both GitHub releases and local builds
#
################################################################################

MUJINA_VERSION = $(call qstrip,$(BR2_PACKAGE_MUJINA_VERSION))

ifeq ($(BR2_PACKAGE_MUJINA_LOCAL_BUILD),y)
MUJINA_DEPENDENCIES = host-pkgconf host-rustc
endif

ifeq ($(BR2_PACKAGE_MUJINA_GITHUB_RELEASE),y)
# GitHub release download
ifeq ($(MUJINA_VERSION),latest)
MUJINA_VERSION = main
endif
MUJINA_SITE = https://github.com/256foundation/mujina/releases/download/$(MUJINA_VERSION)
MUJINA_SOURCE = mujina-arm-linux-gnueabihf.tar.gz
MUJINA_SITE_METHOD = wget

define MUJINA_EXTRACT_CMDS
	mkdir -p $(@D)/bin
	tar -xzf $(MUJINA_DL_DIR)/$(MUJINA_SOURCE) -C $(@D)/bin
endef

define MUJINA_BUILD_CMDS
	@echo "Using pre-built mujina binary from GitHub release $(MUJINA_VERSION)"
endef

else ifeq ($(BR2_PACKAGE_MUJINA_LOCAL_BUILD),y)
# Local build from source
MUJINA_SITE = $(call qstrip,$(BR2_PACKAGE_MUJINA_LOCAL_PATH))
MUJINA_SITE_METHOD = local

define MUJINA_BUILD_CMDS
	@echo "========================================"
	@echo "Building mujina from local source"
	@echo "========================================"
	@mkdir -p $(@D)/.cargo
	@echo '[target.arm-unknown-linux-gnueabihf]' > $(@D)/.cargo/config.toml
	@echo 'linker = "$(TARGET_CC)"' >> $(@D)/.cargo/config.toml
	cd $(@D) && \
		CARGO_TARGET_ARM_UNKNOWN_LINUX_GNUEABIHF_LINKER="$(TARGET_CC)" \
		OPENSSL_DIR="$(STAGING_DIR)/usr" \
		OPENSSL_LIB_DIR="$(STAGING_DIR)/usr/lib" \
		OPENSSL_INCLUDE_DIR="$(STAGING_DIR)/usr/include" \
		OPENSSL_NO_VENDOR=1 \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		PKG_CONFIG_SYSROOT_DIR="$(STAGING_DIR)" \
		PKG_CONFIG_LIBDIR="$(STAGING_DIR)/usr/lib/pkgconfig" \
		PKG_CONFIG_ALLOW_CROSS=1 \
		cargo build --release \
			--target arm-unknown-linux-gnueabihf \
			--target-dir $(@D)/target
	@mkdir -p $(@D)/bin
	@cp -f $(@D)/target/arm-unknown-linux-gnueabihf/release/mujina-minerd $(@D)/bin/mujina
	@cp -f $(@D)/target/arm-unknown-linux-gnueabihf/release/mujina-cli $(@D)/bin/
	@cp -f $(@D)/target/arm-unknown-linux-gnueabihf/release/mujina-tui $(@D)/bin/
endef

endif

define MUJINA_INSTALL_TARGET_CMDS
	@echo "Installing mujina binary..."
	$(INSTALL) -D -m 0755 $(@D)/bin/mujina \
		$(TARGET_DIR)/usr/bin/mujina

	@echo "Installing stock Bitmain kernel modules..."
	@mkdir -p $(TARGET_DIR)/lib/modules
	if [ -d "$(BR2_EXTERNAL_XILINX_BITMAIN_PATH)/board/xilinx/kernel_modules" ]; then \
		$(INSTALL) -D -m 0644 \
			$(BR2_EXTERNAL_XILINX_BITMAIN_PATH)/board/xilinx/kernel_modules/bitmain_axi.ko \
			$(TARGET_DIR)/lib/modules/bitmain_axi.ko; \
		$(INSTALL) -D -m 0644 \
			$(BR2_EXTERNAL_XILINX_BITMAIN_PATH)/board/xilinx/kernel_modules/fpga_mem_driver.ko \
			$(TARGET_DIR)/lib/modules/fpga_mem_driver.ko; \
		echo "Installed stock kernel modules to /lib/modules/"; \
	else \
		echo "WARNING: Stock Bitmain kernel modules not found"; \
		echo "Please extract from Bitmain firmware and place in:"; \
		echo "  $(BR2_EXTERNAL_XILINX_BITMAIN_PATH)/board/xilinx/kernel_modules/"; \
	fi
endef

$(eval $(generic-package))
