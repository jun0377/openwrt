# 
# Copyright (C) 2007-2009 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
# Main makefile for the toolchain
# 文件说明：这是工具链的主要Makefile文件
#
# Steps:
# 1) toolchain/binutils/compile
#    build & install binutils
#    编译并安装二进制工具集(binutils)
# 2) toolchain/gcc/minimal/compile
#    build & install a minimal gcc, needed for steps 3 & 4
#    编译并安装最小版本的gcc，用于步骤3和4
# 3) toolchain/kernel-headers/compile
#    install kernel headers, needed for step 4
#    安装内核头文件，用于步骤4
# 4) toolchain/libc/headers/compile
#    build & install libc headers & support files, needed for step 5
#    编译并安装libc头文件和支持文件，用于步骤5
# 5) toolchain/gcc/initial/compile
#    build & install an initial gcc, needed for step 6
#    编译并安装初始版本的gcc，用于步骤6
# 6) toolchain/libc/compile
#    build & install the final libc
#    编译并安装最终版本的libc
# 7) toolchain/gcc/final/compile
#    build & install the final gcc
#    编译并安装最终版本的gcc
#
# For musl, steps 2 and 4 are skipped, and step 3 is done after 5
# 对于musl libc，步骤2和4被跳过，步骤3在步骤5之后执行

curdir:=toolchain

# subdirectories to descend into
$(curdir)/builddirs := $(if $(CONFIG_GDB),gdb) $(if $(CONFIG_EXTERNAL_TOOLCHAIN),wrapper,kernel-headers binutils gcc/initial gcc/final $(LIBC) fortify-headers) $(if $(CONFIG_NASM),nasm) $(if $(CONFIG_USE_MOLD),mold)

# builddir dependencies
ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
  ifdef CONFIG_USE_MUSL
    $(curdir)/gcc/initial/compile:=$(curdir)/binutils/compile
    $(curdir)/kernel-headers/compile:=$(curdir)/gcc/initial/compile
  else
    $(curdir)/builddirs += $(LIBC)/headers gcc/minimal
    $(curdir)/gcc/minimal/compile:=$(curdir)/binutils/compile
    $(curdir)/kernel-headers/compile:=$(curdir)/gcc/minimal/compile
    $(curdir)/$(LIBC)/headers/compile:=$(curdir)/kernel-headers/compile
    $(curdir)/gcc/initial/compile:=$(curdir)/$(LIBC)/headers/compile
  endif

  $(curdir)/$(LIBC)/compile:=$(curdir)/gcc/initial/compile $(curdir)/kernel-headers/compile
  $(curdir)/gcc/final/compile:=$(curdir)/$(LIBC)/compile
endif

ifndef DUMP_TARGET_DB
ifneq ($(ARCH),)
  $(TOOLCHAIN_DIR)/info.mk: .config
	@for dir in $(TOOLCHAIN_DIR); do ( \
		$(if $(QUIET),,set -x;) \
		mkdir -p "$$dir"; \
		cd "$$dir"; \
		ln -nsf lib lib64; \
		ln -nsf lib lib32; \
		mkdir -p stamp lib usr/include usr/lib ; \
	); done
	@grep GCC_VERSION $@ >/dev/null 2>&1 || $(INSTALL_DATA) $(TOPDIR)/toolchain/info.mk $@
	@touch $@
endif
endif

ifdef CONFIG_BUILDBOT
ifneq ($(wildcard $(TOPDIR)/.git),)
  $(TOOLCHAIN_DIR)/stamp/.ver_check: $(TMP_DIR)/.build
	cd "$(TOPDIR)"; git log --format=%h -1 toolchain > $(TMP_DIR)/.ver_check
	cmp -s $(TMP_DIR)/.ver_check $@ || { \
		rm -rf $(BUILD_DIR) $(STAGING_DIR) $(TOOLCHAIN_DIR) $(BUILD_DIR_TOOLCHAIN); \
		mkdir -p $(TOOLCHAIN_DIR)/stamp; \
		mv $(TMP_DIR)/.ver_check $@; \
	}

$(TOOLCHAIN_DIR)/info.mk $(STAGING_DIR)/.prepared: $(TOOLCHAIN_DIR)/stamp/.ver_check
endif
endif

# prerequisites for the individual targets
$(curdir)/ := .config prereq
$(curdir)//compile = $(STAGING_DIR)/.prepared $(TOOLCHAIN_DIR)/info.mk $(tools/stamp-compile)

ifndef DUMP_TARGET_DB
$(TOOLCHAIN_DIR)/stamp/.gcc_final_installed:
endif

$(curdir)/install: $(curdir)/compile

$(eval $(call stampfile,$(curdir),toolchain,compile,$(TOOLCHAIN_DIR)/stamp/.gcc_final_installed,,$(TOOLCHAIN_DIR)))
$(eval $(call stampfile,$(curdir),toolchain,check,$(TMP_DIR)/.build))
$(eval $(call subdir,$(curdir)))

