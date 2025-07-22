# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 前置条件Makefile
include $(INCLUDE_DIR)/prereq.mk
# 依赖关系处理Makefile
include $(INCLUDE_DIR)/depends.mk

# 如果不是DUMP模式，默认目标为compile
ifneq ($(DUMP),1)
  all: compile
endif

$(info )
$(info )
$(info )
$(info ************** kernel path ******************)
$(info LINUX_DIR=$(LINUX_DIR))
$(info *********************************************)
$(info )
$(info )
$(info )

# 内核文件依赖目录列表 包括通用回移植目录、补丁目录、hack目录、补丁目录和文件目录
KERNEL_FILE_DEPENDS=$(GENERIC_BACKPORT_DIR) $(GENERIC_PATCH_DIR) $(GENERIC_HACK_DIR) $(PATCH_DIR) $(GENERIC_FILES_DIR) $(FILES_DIR)
# 定义准备阶段的时间戳文件，用于跟踪内核源码准备状态
# 如果启用了 QUILT 或 DUMP，不添加 MD5 后缀
# 否则根据内核文件依赖计算 MD5 值作为后缀
STAMP_PREPARED=$(LINUX_DIR)/.prepared$(if $(QUILT)$(DUMP),,_$(shell $(call $(if $(CONFIG_AUTOREMOVE),find_md5_reproducible,find_md5),$(KERNEL_FILE_DEPENDS),)))
# 定义配置阶段的时间戳文件
STAMP_CONFIGURED:=$(LINUX_DIR)/.configured

# 包含下载相关的 makefile
include $(INCLUDE_DIR)/download.mk
# 包含 quilt 补丁管理相关的 makefile
include $(INCLUDE_DIR)/quilt.mk
# 包含内核默认配置相关的 makefile
include $(INCLUDE_DIR)/kernel-defaults.mk

# 定义内核准备阶段的函数，调用默认的准备函数
define Kernel/Prepare
	$(call Kernel/Prepare/Default)
endef

# 定义内核配置阶段的函数，调用默认的配置函数
define Kernel/Configure
	$(call Kernel/Configure/Default)
endef

# 定义内核模块编译阶段的函数，调用默认的模块编译函数
define Kernel/CompileModules
	$(call Kernel/CompileModules/Default)
endef

# 内核镜像编译阶段的函数
## 先调用默认的镜像编译函数
## 然后编译 initramfs 镜像
define Kernel/CompileImage
	$(call Kernel/CompileImage/Default)
	$(call Kernel/CompileImage/Initramfs)
endef

# 定义内核清理阶段的函数，调用默认的清理函数
define Kernel/Clean
	$(call Kernel/Clean/Default)
endef

# 定义内核下载函数
# 指定下载 URL、文件名和校验哈希值
define Download/kernel
  URL:=$(LINUX_SITE)
  FILE:=$(LINUX_SOURCE)
  HASH:=$(LINUX_KERNEL_HASH)
endef

# 定义内核 Git 选项
# 如果配置了本地 Git 仓库，添加 --reference 选项指向本地仓库
KERNEL_GIT_OPTS:=
ifneq ($(strip $(CONFIG_KERNEL_GIT_LOCAL_REPOSITORY)),"")
  KERNEL_GIT_OPTS+=--reference $(CONFIG_KERNEL_GIT_LOCAL_REPOSITORY)
endif

# 定义从 Git 下载内核的规则
# 指定 Git 仓库 URL、协议、版本、文件名、子目录和选项
define Download/git-kernel
  URL:=$(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI))
  PROTO:=git
  SOURCE_VERSION:=$(CONFIG_KERNEL_GIT_REF)
  FILE:=$(LINUX_SOURCE)
  SUBDIR:=linux-$(LINUX_VERSION)
  OPTS:=$(KERNEL_GIT_OPTS)
endef

# 如果启用了内核调试信息收集
# 定义收集调试信息的函数：
# 1. 清理并创建调试目录
# 2. 复制 vmlinux 和内核模块
# 3. 提取调试信息
# 4. 打包压缩调试信息
ifdef CONFIG_COLLECT_KERNEL_DEBUG
  define Kernel/CollectDebug
	rm -rf $(KERNEL_BUILD_DIR)/debug
	mkdir -p $(KERNEL_BUILD_DIR)/debug/modules
	$(CP) $(LINUX_DIR)/vmlinux $(KERNEL_BUILD_DIR)/debug/
	-$(CP) \
		$(STAGING_DIR_ROOT)/lib/modules/$(LINUX_VERSION)/*.ko \
		$(KERNEL_BUILD_DIR)/debug/modules/
	$(FIND) $(KERNEL_BUILD_DIR)/debug -type f | $(XARGS) $(KERNEL_CROSS)strip --only-keep-debug
	$(TAR) c -C $(KERNEL_BUILD_DIR) debug \
		$(if $(SOURCE_DATE_EPOCH),--mtime="@$(SOURCE_DATE_EPOCH)") \
		| zstd -T0 -f -o $(BIN_DIR)/kernel-debug.tar.zst
  endef
endif

# 如果不是特殊目标且启用了自动重建
# 定义自动清理函数，用于处理依赖文件
ifeq ($(DUMP)$(filter prereq clean refresh update,$(MAKECMDGOALS)),)
  ifneq ($(if $(QUILT),,$(CONFIG_AUTOREBUILD)),)
    define Kernel/Autoclean
      $(PKG_BUILD_DIR)/.dep_files: $(STAMP_PREPARED)
      $(call rdep,$(KERNEL_FILE_DEPENDS),$(STAMP_PREPARED),$(PKG_BUILD_DIR)/.dep_files,-x "*/.dep_*")
    endef
  endif
endif

# 定义构建内核的主函数：
# 1. 如果使用 QUILT，执行 QUILT 构建
# 2. 如果有下载站点，下载内核源码
# 3. 如果有 Git 仓库，从 Git 下载
# 4. 禁用并行构建
# 5. 执行自动清理
# 6. 准备阶段：清理构建目录，创建新目录，准备内核源码
define BuildKernel
  $(if $(QUILT),$(Build/Quilt))
  $(if $(LINUX_SITE),$(call Download,kernel))
  $(if $(call qstrip,$(CONFIG_KERNEL_GIT_CLONE_URI)),$(call Download,git-kernel))

  .NOTPARALLEL:

  $(Kernel/Autoclean)
  $(STAMP_PREPARED): $(if $(LINUX_SITE),$(DL_DIR)/$(LINUX_SOURCE))
	-rm -rf $(KERNEL_BUILD_DIR)
	-mkdir -p $(KERNEL_BUILD_DIR)
	$(Kernel/Prepare)
	touch $$@

# 生成符号表头文件：
# 1. 编译 vmlinux
# 2. 收集模块符号
# 3. 收集内核符号
# 4. 生成需要保留和丢弃的符号列表
# 5. 生成符号表宏定义
  $(KERNEL_BUILD_DIR)/symtab.h: FORCE
	rm -f $(KERNEL_BUILD_DIR)/symtab.h
	touch $(KERNEL_BUILD_DIR)/symtab.h
	+$(KERNEL_MAKE) vmlinux
	find $(LINUX_DIR) $(STAGING_DIR_ROOT)/lib/modules -name \*.ko | \
		xargs $(TARGET_CROSS)nm | \
		awk '$$$$1 == "U" { print $$$$2 } ' | \
		sort -u > $(KERNEL_BUILD_DIR)/mod_symtab.txt
	$(TARGET_CROSS)nm -n $(LINUX_DIR)/vmlinux.o | awk '/^[0-9a-f]+ [rR] __ksymtab_/ {print substr($$$$3,11)}' > $(KERNEL_BUILD_DIR)/kernel_symtab.txt
	grep -Ff $(KERNEL_BUILD_DIR)/mod_symtab.txt $(KERNEL_BUILD_DIR)/kernel_symtab.txt > $(KERNEL_BUILD_DIR)/sym_include.txt
	grep -Fvf $(KERNEL_BUILD_DIR)/mod_symtab.txt $(KERNEL_BUILD_DIR)/kernel_symtab.txt > $(KERNEL_BUILD_DIR)/sym_exclude.txt
	( \
		echo '#define SYMTAB_KEEP \'; \
		cat $(KERNEL_BUILD_DIR)/sym_include.txt | \
			awk '{print "KEEP(*(___ksymtab+" $$$$1 ")) \\" }'; \
		echo; \
		echo '#define SYMTAB_KEEP_GPL \'; \
		cat $(KERNEL_BUILD_DIR)/sym_include.txt | \
			awk '{print "KEEP(*(___ksymtab_gpl+" $$$$1 ")) \\" }'; \
		echo; \
		echo '#define SYMTAB_DISCARD \'; \
		cat $(KERNEL_BUILD_DIR)/sym_exclude.txt | \
			awk '{print "*(___ksymtab+" $$$$1 ") \\" }'; \
		echo; \
		echo '#define SYMTAB_DISCARD_GPL \'; \
		cat $(KERNEL_BUILD_DIR)/sym_exclude.txt | \
			awk '{print "*(___ksymtab_gpl+" $$$$1 ") \\" }'; \
		echo; \
	) > $$@

# 配置阶段：依赖于准备阶段和配置文件
# 执行内核配置，更新时间戳
  $(STAMP_CONFIGURED): $(STAMP_PREPARED) $(LINUX_KCONFIG_LIST) $(TOPDIR)/.config FORCE
	$(Kernel/Configure)
	touch $$@

# 模块编译阶段：
# 1. 设置环境变量
# 2. 依赖于配置阶段
# 3. 编译模块，更新时间戳
  $(LINUX_DIR)/.modules: export STAGING_PREFIX=$$(STAGING_DIR_HOST)
  $(LINUX_DIR)/.modules: export PKG_CONFIG_PATH=$$(STAGING_DIR_HOST)/lib/pkgconfig
  $(LINUX_DIR)/.modules: export PKG_CONFIG_LIBDIR=$$(STAGING_DIR_HOST)/lib/pkgconfig
  $(LINUX_DIR)/.modules: export FAIL_ON_UNCONFIGURED=1
  $(LINUX_DIR)/.modules: $(STAMP_CONFIGURED) $(LINUX_DIR)/.config FORCE
	$(Kernel/CompileModules)
	touch $$@

# 镜像编译阶段：
# 1. 设置环境变量
# 2. 依赖于配置阶段和符号表（如果启用）
# 3. 编译镜像，收集调试信息，更新时间戳
  $(LINUX_DIR)/.image: export STAGING_PREFIX=$$(STAGING_DIR_HOST)
  $(LINUX_DIR)/.image: export PKG_CONFIG_PATH=$$(STAGING_DIR_HOST)/lib/pkgconfig
  $(LINUX_DIR)/.image: export PKG_CONFIG_LIBDIR=$$(STAGING_DIR_HOST)/lib/pkgconfig
  $(LINUX_DIR)/.image: $(STAMP_CONFIGURED) $(if $(CONFIG_STRIP_KERNEL_EXPORTS),$(KERNEL_BUILD_DIR)/symtab.h) FORCE
	$(Kernel/CompileImage)
	$(Kernel/CollectDebug)
	touch $$@
	
# 清理目标：执行内核清理
  mostlyclean: FORCE
	$(Kernel/Clean)

  define BuildKernel
  endef

# 定义主要目标：
# - download：下载内核源码
# - prepare：准备内核源码
# - compile：编译内核模块和镜像
  download: $(if $(LINUX_SITE),$(DL_DIR)/$(LINUX_SOURCE))
  prepare: $(STAMP_PREPARED)
  compile: $(LINUX_DIR)/.modules
	+$(MAKE) -C image compile TARGET_BUILD=

# dtb 目标：编译设备树二进制文件
  dtb: $(STAMP_CONFIGURED)
	$(_SINGLE)$(KERNEL_MAKE) scripts_dtc
	$(MAKE) -C image compile-dtb TARGET_BUILD=

# 配置界面目标：
# 1. 删除旧配置
# 2. 生成新配置
# 3. 运行配置工具
# 4. 保存配置差异
  oldconfig menuconfig nconfig xconfig: $(STAMP_PREPARED) $(STAMP_CHECKED) FORCE
	rm -f $(LINUX_DIR)/.config.prev
	rm -f $(STAMP_CONFIGURED)
	$(LINUX_RECONF_CMD) > $(LINUX_DIR)/.config
	$(_SINGLE)$(KERNEL_MAKE) \
		$(if $(findstring Darwin,$(HOST_OS)), \
			HOSTLDLIBS_mconf="-L$(STAGING_DIR_HOST)/lib -lncurses" \
			filechk_conf_cfg="	:" \
		) \
		YACC=$(STAGING_DIR_HOST)/bin/bison \
		$$@
	$(call LINUX_RECONF_DIFF,$(LINUX_DIR)/.config) > $(LINUX_RECONFIG_TARGET)

# 安装目标：安装编译好的内核镜像
  install: $(LINUX_DIR)/.image
	+$(MAKE) -C image compile install TARGET_BUILD=

# 清理目标：删除整个内核构建目录
  clean: FORCE
	rm -rf $(KERNEL_BUILD_DIR)

# 镜像前置条件目标
  image-prereq:
	@+$(NO_TRACE_MAKE) -s -C image prereq TARGET_BUILD=

# 前置条件目标：依赖于镜像前置条件
  prereq: image-prereq

endef
