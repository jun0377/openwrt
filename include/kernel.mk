# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 检查是否为check目标，只检查不编译
ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK:=1
# 用于信息输出和调试
DUMP:=1
endif

# 编译时间戳
ifneq ($(SOURCE_DATE_EPOCH),)
  ifndef DUMP
    KBUILD_BUILD_TIMESTAMP:=$(shell perl -e 'print scalar gmtime($(SOURCE_DATE_EPOCH))')
  endif
endif

# 获取目标平台编译配置
ifeq ($(__target_inc),)
  ifndef CHECK
    include $(INCLUDE_DIR)/target.mk
  endif
endif

# 调试模式，变量默认值
ifeq ($(DUMP),1)
  KERNEL?=<KERNEL>
  BOARD?=<BOARD>
  LINUX_VERSION?=<LINUX_VERSION>
  LINUX_VERMAGIC?=<LINUX_VERMAGIC>
else
  ifeq ($(CONFIG_EXTERNAL_TOOLCHAIN),)
    export GCC_HONOUR_COPTS=s
  endif

  LINUX_KMOD_SUFFIX=ko

  # 交叉编译工具链, 查看BOADR变量是否包含"uml"字符串
  # UML 是 "User Mode Linux" 的缩写，是一种在用户空间运行的Linux内核,不需要交叉编译
  ifneq (,$(findstring uml,$(BOARD)))
    KERNEL_CC?=$(HOSTCC)
    KERNEL_CROSS?=
  else
    KERNEL_CC?=$(TARGET_CC)
    KERNEL_CROSS?=$(TARGET_CROSS)
  endif

  # 补丁目录
  ifeq ($(TARGET_BUILD),1)
    PATCH_DIR ?= $(CURDIR)/patches$(if $(wildcard ./patches-$(KERNEL_PATCHVER)),-$(KERNEL_PATCHVER))
    FILES_DIR ?= $(foreach dir,$(wildcard $(CURDIR)/files $(CURDIR)/files-$(KERNEL_PATCHVER)),"$(dir)")
  endif

  # 内核编译目录
  KERNEL_BUILD_DIR ?= $(BUILD_DIR)/linux-$(BOARD)_$(SUBTARGET)
  # 内核源码目录
  LINUX_DIR ?= $(KERNEL_BUILD_DIR)/linux-$(LINUX_VERSION)
  # 内核user api头文件目录
  LINUX_UAPI_DIR=uapi/
  # 内核版本魔数
  LINUX_VERMAGIC:=$(strip $(shell cat $(LINUX_DIR)/.vermagic 2>/dev/null))
  LINUX_VERMAGIC:=$(if $(LINUX_VERMAGIC),$(LINUX_VERMAGIC),unknown)

  # 内核版本号
  LINUX_UNAME_VERSION:=$(KERNEL_BASE)
  ifneq ($(findstring -rc,$(LINUX_VERSION)),)
    LINUX_UNAME_VERSION:=$(LINUX_UNAME_VERSION)-$(strip $(lastword $(subst -, ,$(LINUX_VERSION))))
  endif

  # 内核镜像vmlinux路径
  LINUX_KERNEL:=$(KERNEL_BUILD_DIR)/vmlinux
  
  # 尚未解压的内核源码目录
  ifneq (,$(findstring -rc,$(LINUX_VERSION)))
      LINUX_SOURCE:=linux-$(LINUX_VERSION).tar.gz
  else
      LINUX_SOURCE:=linux-$(LINUX_VERSION).tar.xz
  endif

  # 内核下载地址
  ifneq (,$(findstring -rc,$(LINUX_VERSION)))
      LINUX_SITE:=https://git.kernel.org/torvalds/t
  else ifeq ($(call qstrip,$(CONFIG_EXTERNAL_KERNEL_TREE))$(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),)
      LINUX_SITE:=@KERNEL/linux/kernel/v$(word 1,$(subst ., ,$(KERNEL_BASE))).x
  else
      LINUX_UNAME_VERSION:=$(strip $(shell cat $(LINUX_DIR)/include/config/kernel.release 2>/dev/null))
  endif

  # 内核模块目录
  MODULES_SUBDIR:=lib/modules/$(LINUX_UNAME_VERSION)
  # 内核模块编译后的保存路径
  TARGET_MODULES_DIR:=$(LINUX_TARGET_DIR)/$(MODULES_SUBDIR)

  # package编译目录
  ifneq ($(TARGET_BUILD),1)
    PKG_BUILD_DIR ?= $(KERNEL_BUILD_DIR)/$(if $(BUILD_VARIANT),$(PKG_NAME)-$(BUILD_VARIANT)/)$(PKG_NAME)$(if $(PKG_VERSION),-$(PKG_VERSION))
  endif
endif

# 内核架构
ifneq (,$(findstring uml,$(BOARD)))
  LINUX_KARCH=um
else ifneq (,$(findstring $(ARCH) , aarch64 aarch64_be ))
  LINUX_KARCH := arm64
else ifneq (,$(findstring $(ARCH) , arceb ))
  LINUX_KARCH := arc
else ifneq (,$(findstring $(ARCH) , armeb ))
  LINUX_KARCH := arm
else ifneq (,$(findstring $(ARCH) , loongarch64 ))
  LINUX_KARCH := loongarch
else ifneq (,$(findstring $(ARCH) , mipsel mips64 mips64el ))
  LINUX_KARCH := mips
else ifneq (,$(findstring $(ARCH) , powerpc64 ))
  LINUX_KARCH := powerpc
else ifneq (,$(findstring $(ARCH) , riscv64 ))
  LINUX_KARCH := riscv
else ifneq (,$(findstring $(ARCH) , sh2 sh3 sh4 ))
  LINUX_KARCH := sh
else ifneq (,$(findstring $(ARCH) , i386 x86_64 ))
  LINUX_KARCH := x86
else
  LINUX_KARCH := $(ARCH)
endif

# 内核编译命令: make + 编译选项
KERNEL_MAKE = $(MAKE) $(KERNEL_MAKEOPTS)

# 内核编译选项
## KCFLAGS ：内核编译标志，包含路径重映射、优化选项和自定义内核编译标志
## HOSTCFLAGS ：主机编译器标志，添加了警告选项
## CROSS_COMPILE ：交叉编译工具链前缀
## ARCH ：目标架构（如 arm64、x86 等）
## KBUILD_HAVE_NLS ：禁用国际化支持
## KBUILD_BUILD_USER/HOST ：构建用户和主机信息
## KBUILD_BUILD_TIMESTAMP/VERSION ：构建时间戳和版本
## KBUILD_HOSTLDFLAGS ：主机链接器标志
## CONFIG_SHELL ：指定使用的shell（bash）
## V=1/V='' ：根据详细输出设置控制编译输出详细程度
## LDFLAGS_MODULE ：模块链接标志（包含构建ID）
## cmd_syscalls ：系统调用相关（置空）
## KBUILD_EXTRA_SYMBOLS ：额外的符号表文件
KERNEL_MAKE_FLAGS = \
	KCFLAGS="$(call iremap,$(BUILD_DIR),$(notdir $(BUILD_DIR))) $(filter-out -fno-plt,$(call qstrip,$(CONFIG_EXTRA_OPTIMIZATION))) $(call qstrip,$(CONFIG_KERNEL_CFLAGS))" \
	HOSTCFLAGS="$(HOST_CFLAGS) -Wall -Wmissing-prototypes -Wstrict-prototypes" \
	CROSS_COMPILE="$(KERNEL_CROSS)" \
	ARCH="$(LINUX_KARCH)" \
	KBUILD_HAVE_NLS=no \
	KBUILD_BUILD_USER="$(call qstrip,$(CONFIG_KERNEL_BUILD_USER))" \
	KBUILD_BUILD_HOST="$(call qstrip,$(CONFIG_KERNEL_BUILD_DOMAIN))" \
	KBUILD_BUILD_TIMESTAMP="$(KBUILD_BUILD_TIMESTAMP)" \
	KBUILD_BUILD_VERSION="0" \
	KBUILD_HOSTLDFLAGS="-L$(STAGING_DIR_HOST)/lib" \
	CONFIG_SHELL="$(BASH)" \
	$(if $(findstring c,$(OPENWRT_VERBOSE)),V=1,V='') \
	$(if $(PKG_BUILD_ID),LDFLAGS_MODULE=--build-id=0x$(PKG_BUILD_ID)) \
	cmd_syscalls= \
	$(if $(__package_mk),KBUILD_EXTRA_SYMBOLS="$(wildcard $(PKG_SYMVERS_DIR)/*.symvers)")

# 交叉编译工具链
ifneq (,$(KERNEL_CC))
  KERNEL_MAKE_FLAGS += CC="$(KERNEL_CC)"
endif

# 内核编译时的头文件包含标志
## -nostdinc ：告诉编译器不要使用标准的系统头文件目录，这是交叉编译的关键设置
## -isystem $(shell $(TARGET_CC) -print-file-name=include) ：使用目标架构编译器（TARGET_CC）查找其内置的 include 目录
## 如果是 DUMP 模式（配置检查模式），则不添加额外的头文件路径
KERNEL_NOSTDINC_FLAGS = \
	-nostdinc $(if $(DUMP),, -isystem $(shell $(TARGET_CC) -print-file-name=include))

# 根据内核源码来源的配置，有条件地设置内核版本标识
## 标准内核构建 ：当使用 OpenWrt 默认的内核源码时，明确设置内核版本号
## 外部内核兼容 ：当使用外部内核树或从Git仓库克隆内核时，不强制设置版本号，让外部内核自己管理版本信息
ifeq ($(call qstrip,$(CONFIG_EXTERNAL_KERNEL_TREE))$(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),)
  KERNEL_MAKE_FLAGS += \
	KERNELRELEASE=$(LINUX_VERSION)
endif

# 编译主机是linux
ifneq ($(HOST_OS),Linux)
  KERNEL_MAKE_FLAGS += CONFIG_STACK_VALIDATION=
  export SKIP_STACK_VALIDATION:=1
endif

# 内核编译选项
KERNEL_MAKEOPTS = -C $(LINUX_DIR) $(KERNEL_MAKE_FLAGS)

# Sparse静态代码分析工具
ifdef CONFIG_USE_SPARSE
  KERNEL_MAKEOPTS += C=1 CHECK=$(STAGING_DIR_HOST)/bin/sparse
endif

PKG_EXTMOD_SUBDIRS ?= .

PKG_SYMVERS_DIR = $(KERNEL_BUILD_DIR)/symvers

# 收集内核模块符号表
define collect_module_symvers
	for subdir in $(PKG_EXTMOD_SUBDIRS); do \
		realdir=$$$$(readlink -f $(PKG_BUILD_DIR)); \
		grep -F $(PKG_BUILD_DIR) $(PKG_BUILD_DIR)/$$$$subdir/Module.symvers >> $(PKG_BUILD_DIR)/Module.symvers.tmp; \
		[ "$(PKG_BUILD_DIR)" = "$$$$realdir" ] || \
			grep -F $$$$realdir $(PKG_BUILD_DIR)/$$$$subdir/Module.symvers >> $(PKG_BUILD_DIR)/Module.symvers.tmp; \
	done; \
	sort -u $(PKG_BUILD_DIR)/Module.symvers.tmp > $(PKG_BUILD_DIR)/Module.symvers; \
	mkdir -p $(PKG_SYMVERS_DIR); \
	mv $(PKG_BUILD_DIR)/Module.symvers $(PKG_SYMVERS_DIR)/$(PKG_NAME).symvers
endef

# 内核模块编译后的钩子函数，这里将其设置为内核模块编译完成后，自动收集符号模块表
define KernelPackage/hooks
  ifneq ($(PKG_NAME),kernel)
    Hooks/Compile/Post += collect_module_symvers
  endif
  define KernelPackage/hooks
  endef
endef

# 为内核模块包定义默认配置参数
define KernelPackage/Defaults
  FILES:=
  AUTOLOAD:=
  MODPARAMS:=
  PKGFLAGS+=nonshared
endef

# 1: name
# 2: install prefix
# 3: module priority prefix
# 4: required for boot
# 5: module list
define ModuleAutoLoad
  $(if $(5), \
    mkdir -p $(2)/etc/modules.d; \
    ($(foreach mod,$(5), \
      echo "$(mod)$(if $(MODPARAMS.$(mod)), $(MODPARAMS.$(mod)),$(if $(MODPARAMS), $(MODPARAMS)))"; )) > $(2)/etc/modules.d/$(3)$(1); \
    $(if $(4), \
      mkdir -p $(2)/etc/modules-boot.d; \
      ln -sf ../modules.d/$(3)$(1) $(2)/etc/modules-boot.d/;))
endef

ifeq ($(DUMP)$(TARGET_BUILD),)
  -include $(LINUX_DIR)/.config
endif

define KernelPackage/depends
  $(STAMP_BUILT): $(LINUX_DIR)/.config
  define KernelPackage/depends
  endef
endef

define KernelPackage
  NAME:=$(1)
  $(eval $(call Package/Default))
  $(eval $(call KernelPackage/Defaults))
  $(eval $(call KernelPackage/$(1)))
  $(eval $(call KernelPackage/$(1)/$(BOARD)))
  $(eval $(call KernelPackage/$(1)/$(BOARD)/$(SUBTARGET)))

  define Package/kmod-$(1)
    TITLE:=$(TITLE)
    SECTION:=kernel
    CATEGORY:=Kernel modules
    DESCRIPTION:=$(DESCRIPTION)
    EXTRA_DEPENDS:=kernel (=$(LINUX_VERSION)~$(LINUX_VERMAGIC)-r$(LINUX_RELEASE))
    VERSION:=$(LINUX_VERSION)$(if $(PKG_VERSION),.$(PKG_VERSION))-r$(if $(PKG_RELEASE),$(PKG_RELEASE),$(LINUX_RELEASE))
    PKGFLAGS:=$(PKGFLAGS)
    $(call KernelPackage/$(1))
    $(call KernelPackage/$(1)/$(BOARD))
    $(call KernelPackage/$(1)/$(BOARD)/$(SUBTARGET))
  endef

  ifdef KernelPackage/$(1)/conffiles
    define Package/kmod-$(1)/conffiles
$(call KernelPackage/$(1)/conffiles)
    endef
  endif

  ifdef KernelPackage/$(1)/description
    define Package/kmod-$(1)/description
$(call KernelPackage/$(1)/description)
    endef
  endif

  ifdef KernelPackage/$(1)/config
    define Package/kmod-$(1)/config
$(call KernelPackage/$(1)/config)
    endef
  endif

  $(call KernelPackage/depends)
  $(call KernelPackage/hooks)

  ifneq ($(if $(filter-out %=y %=n %=m,$(KCONFIG)),$(filter m y,$(foreach c,$(call version_filter,$(filter-out %=y %=n %=m,$(KCONFIG))),$($(c)))),.),)
    define Package/kmod-$(1)/install
		  @for mod in $$(call version_filter,$$(FILES)); do \
			if grep -q "$$$$$$$${mod##$(LINUX_DIR)/}" "$(LINUX_DIR)/modules.builtin"; then \
				echo "NOTICE: module '$$$$$$$$mod' is built-in."; \
			elif [ -e $$$$$$$$mod ]; then \
				mkdir -p $$(1)/$(MODULES_SUBDIR) ; \
				$(CP) -L $$$$$$$$mod $$(1)/$(MODULES_SUBDIR)/ ; \
			else \
				echo "ERROR: module '$$$$$$$$mod' is missing." >&2; \
				exit 1; \
			fi; \
		  done;
		  $(call ModuleAutoLoad,$(1),$$(1),$(filter-out 0-,$(word 1,$(AUTOLOAD))-),$(filter-out 0,$(word 2,$(AUTOLOAD))),$(sort $(wordlist 3,99,$(AUTOLOAD))))
		  $(call KernelPackage/$(1)/install,$$(1))
    endef
  $(if $(CONFIG_PACKAGE_kmod-$(1)),
    else
      compile: $(1)-disabled
      $(1)-disabled:
		@echo "WARNING: kmod-$(1) is not available in the kernel config - generating empty package" >&2

      define Package/kmod-$(1)/install
		true
      endef
  )
  endif
  $$(eval $$(call BuildPackage,kmod-$(1)))

  $$(IPKG_kmod-$(1)): $$(wildcard $$(call version_filter,$$(FILES)))

endef

version_filter=$(if $(findstring @,$(1)),$(shell $(SCRIPT_DIR)/package-metadata.pl version_filter $(KERNEL_PATCHVER) $(1)),$(1))

# 1: priority (optional)
# 2: module list
# 3: boot flag
define AutoLoad
  $(if $(1),$(1),0) $(if $(3),1,0) $(call version_filter,$(2))
endef

# 1: module list
# 2: boot flag
define AutoProbe
  $(call AutoLoad,,$(1),$(2))
endef

version_field=$(if $(word $(1),$(2)),$(word $(1),$(2)),0)
kernel_version_merge=$$(( ($(call version_field,1,$(1)) << 24) + ($(call version_field,2,$(1)) << 16) + ($(call version_field,3,$(1)) << 8) + $(call version_field,4,$(1)) ))

ifdef DUMP
  kernel_version_cmp=
else
  kernel_version_cmp=$(shell [ $(call kernel_version_merge,$(call split_version,$(2))) $(1) $(call kernel_version_merge,$(call split_version,$(3))) ] && echo 1 )
endif

CompareKernelPatchVer=$(if $(call kernel_version_cmp,-$(2),$(1),$(3)),1,0)

kernel_patchver_gt=$(call kernel_version_cmp,-gt,$(KERNEL_PATCHVER),$(1))
kernel_patchver_ge=$(call kernel_version_cmp,-ge,$(KERNEL_PATCHVER),$(1))
kernel_patchver_eq=$(call kernel_version_cmp,-eq,$(KERNEL_PATCHVER),$(1))
kernel_patchver_le=$(call kernel_version_cmp,-le,$(KERNEL_PATCHVER),$(1))
kernel_patchver_lt=$(call kernel_version_cmp,-lt,$(KERNEL_PATCHVER),$(1))

