#
# Copyright (C) 2006-2011 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
# Main makefile for the host tools
#

# 当前目录
curdir:=tools

# subdirectories to descend into
# 初始化变量，存储需要编译的工具列表
tools-y :=

# 如果使用外部的工具链，则需要编译出交叉编译工具链
ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
  BUILD_TOOLCHAIN := y
  ifdef CONFIG_GCC_USE_GRAPHITE
    BUILD_ISL = y
  endif
endif

# b43是一个开源项目，提供Broadcom 的某些无线芯片的支持
# 如果需要编译SDK/b43驱动/固件，则需要编译b43-tools
ifneq ($(CONFIG_SDK)$(CONFIG_PACKAGE_kmod-b43)$(CONFIG_BRCMSMAC_USE_FW_FROM_WL),)
  BUILD_B43_TOOLS = y
endif

# bzip2
ifneq ($(CONFIG_SDK)$(CONFIG_TARGET_INITRAMFS_COMPRESSION_BZIP2),)
  BUILD_BZIP2_TOOLS = y
endif
ifneq ($(CONFIG_SDK)$(CONFIG_TARGET_INITRAMFS_COMPRESSION_LZ4),)
  BUILD_LZ4_TOOLS = y
endif

# lz4,需要使用lz4来压缩initramfs
ifneq ($(CONFIG_SDK)$(CONFIG_TARGET_INITRAMFS_COMPRESSION_LZO),)
  BUILD_LZO_TOOLS = y
endif

tools-y += autoconf
tools-y += autoconf-archive
tools-y += automake
tools-y += bc
tools-y += bison
tools-y += cmake
tools-y += cpio
tools-y += dosfstools
tools-y += e2fsprogs
tools-y += elfutils
tools-y += expat
tools-y += fakeroot
tools-y += findutils
tools-y += firmware-utils
tools-y += flex
tools-y += gengetopt
tools-y += gnulib
tools-y += libressl
tools-y += libtool
tools-y += lzma
tools-y += m4
tools-y += make-ext4fs
tools-y += meson
tools-y += missing-macros
tools-y += mkimage
tools-y += mklibs
tools-y += mtd-utils
tools-y += mtools
tools-y += ninja
tools-y += padjffs2
tools-y += patch-image
tools-y += patchelf
tools-y += pkgconf
tools-y += quilt
tools-y += squashfs4
tools-y += sstrip
tools-y += util-linux
tools-y += xz
tools-y += zip
tools-y += zlib

# 如果启用了所有主机工具构建，则添加liblzo
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS),y) += liblzo
# 如果启用了所有主机工具构建或需要b43工具，则添加b43-tools
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_B43_TOOLS),y) += b43-tools
# 如果启用了所有主机工具构建或需要bzip2工具，则添加bzip2
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_BZIP2_TOOLS),y) += bzip2
# 如果启用了所有主机工具构建或需要ISL，则添加isl
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_ISL),y) += isl
# 如果启用了所有主机工具构建或需要LZ4工具，则添加lz4
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_LZ4_TOOLS),y) += lz4
# 如果启用了所有主机工具构建或需要LZO工具，则添加lzop
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_LZO_TOOLS),y) += lzop
# 如果启用了所有主机工具构建或需要工具链，则添加gmp、mpc、mpfr
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(BUILD_TOOLCHAIN),y) += gmp mpc mpfr
# 根据目标平台添加特定工具
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_TARGET_apm821xx)$(CONFIG_TARGET_gemini),y) += genext2fs
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_TARGET_ath79),y) += lzma-old squashfs3-lzma
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_TARGET_mxs),y) += elftosb sdimage
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_TARGET_realtek),y) += 7z
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_TARGET_tegra),y) += cbootimage cbootimage-configs
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_USES_MINOR),y) += yafut
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_USE_SPARSE),y) += sparse
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_USE_LLVM_BUILD),y) += llvm-bpf
tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_USE_MOLD),y) += mold

# builddir dependencies
# 定义工具之间的编译依赖关系
# autoconf依赖m4
$(curdir)/autoconf/compile := $(curdir)/m4/compile
# automake依赖autoconf、pkgconf和xz
$(curdir)/automake/compile := $(curdir)/autoconf/compile $(curdir)/pkgconf/compile $(curdir)/xz/compile
# b43-tools依赖bison
$(curdir)/b43-tools/compile := $(curdir)/bison/compile
# bc依赖bison和libtool
$(curdir)/bc/compile := $(curdir)/bison/compile $(curdir)/libtool/compile
# bison依赖flex
$(curdir)/bison/compile := $(curdir)/flex/compile
# cbootimage依赖automake
$(curdir)/cbootimage/compile += $(curdir)/automake/compile
# dwarves依赖cmake
$(curdir)/dwarves/compile += $(curdir)/cmake/compile
# cmake依赖多个工具
$(curdir)/cmake/compile += $(curdir)/libressl/compile $(curdir)/ninja/compile $(curdir)/expat/compile $(curdir)/xz/compile $(curdir)/zlib/compile $(curdir)/zstd/compile
# dosfstools依赖automake
$(curdir)/dosfstools/compile := $(curdir)/automake/compile
# e2fsprogs依赖libtool和util-linux
$(curdir)/e2fsprogs/compile := $(curdir)/libtool/compile $(curdir)/util-linux/compile
# elfutils依赖多个工具
$(curdir)/elfutils/compile := $(curdir)/m4/compile $(curdir)/zlib/compile $(curdir)/gnulib/compile $(curdir)/libtool/compile
# fakeroot依赖libtool
$(curdir)/fakeroot/compile := $(curdir)/libtool/compile
# findutils依赖bison
$(curdir)/findutils/compile := $(curdir)/bison/compile
# firmware-utils依赖cmake
$(curdir)/firmware-utils/compile += $(curdir)/cmake/compile
# flex依赖libtool
$(curdir)/flex/compile := $(curdir)/libtool/compile
# genext2fs依赖libtool
$(curdir)/genext2fs/compile := $(curdir)/libtool/compile
# gengetopt依赖libtool
$(curdir)/gengetopt/compile := $(curdir)/libtool/compile
$(curdir)/gmp/compile := $(curdir)/libtool/compile
$(curdir)/isl/compile := $(curdir)/gmp/compile
$(curdir)/liblzo/compile := $(curdir)/cmake/compile
$(curdir)/libressl/compile := $(curdir)/pkgconf/compile
$(curdir)/libtool/compile := $(curdir)/automake/compile $(curdir)/gnulib/compile $(curdir)/missing-macros/compile
$(curdir)/lz4/compile := $(curdir)/meson/compile
$(curdir)/lzma-old/compile := $(curdir)/zlib/compile
$(curdir)/lzop/compile := $(curdir)/cmake/compile $(curdir)/liblzo/compile
$(curdir)/llvm-bpf/compile := $(curdir)/cmake/compile
$(curdir)/make-ext4fs/compile := $(curdir)/zlib/compile
$(curdir)/meson/compile := $(curdir)/ninja/compile
$(curdir)/missing-macros/compile := $(curdir)/autoconf/compile
$(curdir)/mkimage/compile += $(curdir)/bison/compile $(curdir)/libressl/compile
$(curdir)/mklibs/compile := $(curdir)/libtool/compile
$(curdir)/mold/compile := $(curdir)/cmake/compile $(curdir)/zlib/compile $(curdir)/zstd/compile
$(curdir)/mpc/compile := $(curdir)/mpfr/compile $(curdir)/gmp/compile
$(curdir)/mpfr/compile := $(curdir)/gmp/compile
$(curdir)/mtd-utils/compile := $(curdir)/libtool/compile $(curdir)/zlib/compile $(curdir)/util-linux/compile
$(curdir)/padjffs2/compile := $(curdir)/findutils/compile
$(curdir)/patchelf/compile := $(curdir)/libtool/compile
$(curdir)/pkgconf/compile := $(curdir)/meson/compile
$(curdir)/quilt/compile := $(curdir)/autoconf/compile $(curdir)/findutils/compile
$(curdir)/sdcc/compile := $(curdir)/bison/compile
$(curdir)/squashfs3-lzma/compile := $(curdir)/lzma-old/compile
$(curdir)/squashfs4/compile := $(curdir)/xz/compile $(curdir)/zlib/compile
$(curdir)/util-linux/compile := $(curdir)/bison/compile $(curdir)/automake/compile
$(curdir)/yafut/compile := $(curdir)/cmake/compile

# 非Linux系统特定的编译依赖
ifneq ($(HOST_OS),Linux)
  # coreutils在非Linux系统上需要额外的依赖
  $(curdir)/coreutils/compile += $(curdir)/automake/compile $(curdir)/bison/compile $(curdir)/gnulib/compile
  $(curdir)/squashfs4/compile += $(curdir)/coreutils/compile
  tools-y += coreutils
endif

# Darwin(macOS)系统特定的编译依赖
ifeq ($(HOST_OS),Darwin)
  tools-y += bash
else
  # 非Darwin系统上dwarves依赖elfutils
  $(curdir)/dwarves/compile += $(curdir)/elfutils/compile
  tools-$(if $(CONFIG_BUILD_ALL_HOST_TOOLS)$(CONFIG_DWARVES),y) += dwarves
endif

# 如果启用了ccache或SDK，添加ccache相关的依赖
ifneq ($(CONFIG_CCACHE)$(CONFIG_SDK),)
$(foreach tool, $(filter-out zstd zlib xz pkgconf patch ninja meson libressl expat cmake,$(tools-y)), $(eval $(curdir)/$(tool)/compile += $(curdir)/ccache/compile))
tools-y += ccache xxhash
$(curdir)/xxhash/compile := $(curdir)/cmake/compile
$(curdir)/ccache/compile := $(curdir)/xxhash/compile
endif

# in case there is no patch tool on the host we need to make patch tool a
# dependency for tools which have patches directory

# 为所有带patches目录的工具添加patch工具依赖
$(foreach tool, $(tools-y), $(if $(wildcard $(curdir)/$(tool)/patches),$(eval $(curdir)/$(tool)/compile += $(curdir)/patch/compile)))

# 为除zstd外的所有工具添加zstd依赖
$(foreach tool, $(filter-out zstd,$(tools-y)), $(eval $(curdir)/$(tool)/compile += $(curdir)/zstd/compile))

# make any tool depend on the following to ensure that archives can be unpacked and patched properly
# 定义核心工具列表，这些工具用于确保能正确解压和打补丁
tools-core += libdeflate
tools-core += patch
tools-core += tar
tools-core += zstd

# 为所有工具添加核心工具依赖
$(foreach tool, $(tools-y), $(eval $(curdir)/$(tool)/compile += $(patsubst %,$(curdir)/%/compile,$(tools-core))))
tools-y += $(tools-core)

# make some core tools depend on sed and flock

# 为核心工具添加sed和flock依赖
$(curdir)/patch/compile += $(curdir)/sed/compile
$(curdir)/tar/compile += $(curdir)/sed/compile
$(curdir)/zstd/compile += $(curdir)/libdeflate/compile

# 设置sed的编译依赖
$(curdir)/sed/compile := $(curdir)/flock/compile $(curdir)/zstd/compile
tools-y += flock sed

# 设置自动移除标志
$(curdir)/autoremove := 1
# 设置构建目录列表
$(curdir)/builddirs := $(tools-y) $(tools-dep) $(tools-)
$(curdir)/builddirs-default := $(tools-y)

# 如果定义了CHECK_ALL，设置检查和下载目录
ifdef CHECK_ALL
$(curdir)/builddirs-check:=$($(curdir)/builddirs)
$(curdir)/builddirs-download:=$($(curdir)/builddirs)
endif

# 如果未定义DUMP_TARGET_DB，定义准备阶段的函数和规则
ifndef DUMP_TARGET_DB
# 定义PrepareStaging函数，用于创建必要的目录结构
define PrepareStaging
	@for dir in $(1); do ( \
		$(if $(QUIET),,set -x;) \
		mkdir -p "$$dir"; \
		cd "$$dir"; \
		mkdir -p bin lib stamp usr/include usr/lib; \
	); done
endef

# 创建BIN_DIR目录的规则
$(BIN_DIR):
	mkdir -p $@

# preparatory work
# 准备规则
$(STAGING_DIR)/.prepared: $(TMP_DIR)/.build
	$(call PrepareStaging,$(STAGING_DIR))
	mkdir -p $(BUILD_DIR)/stamp
	touch $@

# 准备主机工具目录的规则
$(STAGING_DIR_HOST)/.prepared: $(TMP_DIR)/.build
	$(call PrepareStaging,$(STAGING_DIR_HOST))
	mkdir -p $(BUILD_DIR_HOST)/stamp $(STAGING_DIR_HOST)/include/sys
	$(INSTALL_DATA) $(TOPDIR)/tools/include/*.h $(STAGING_DIR_HOST)/include/
	$(INSTALL_DATA) $(TOPDIR)/tools/include/sys/*.h $(STAGING_DIR_HOST)/include/sys/
ifneq ($(HOST_OS),Linux)
	mkdir -p $(STAGING_DIR_HOST)/include/asm
	$(INSTALL_DATA) $(TOPDIR)/tools/include/asm/*.h $(STAGING_DIR_HOST)/include/asm/
endif
	ln -snf lib $(STAGING_DIR_HOST)/lib64
	touch $@

endif

# 设置准备和编译阶段的依赖
$(curdir)//prepare = $(STAGING_DIR)/.prepared $(STAGING_DIR_HOST)/.prepared $(BIN_DIR)
$(curdir)//compile = $(STAGING_DIR)/.prepared $(STAGING_DIR_HOST)/.prepared $(BIN_DIR)

# prerequisites for the individual targets
# 设置个别目标的先决条件
$(curdir)/ := .config prereq

# 设置安装目标依赖于编译目标
$(curdir)/install: $(curdir)/compile

# tools_enabled 记录每个工具的启用状态
tools_enabled = $(foreach tool,$(sort $(tools-y) $(tools-)),$(if $(filter $(tool),$(tools-y)),y,n))
# 为编译过程创建时间戳文件，用于追踪编译状态
$(eval $(call stampfile,$(curdir),tools,compile,,_$(subst $(space),,$(tools_enabled)),$(STAGING_DIR_HOST)))
# 为检查过程创建时间戳文件，基于构建目录的状态
$(eval $(call stampfile,$(curdir),tools,check,$(TMP_DIR)/.build,,$(STAGING_DIR_HOST)))
# 处理当前目录，递归进入子目录处理
$(eval $(call subdir,$(curdir)))
