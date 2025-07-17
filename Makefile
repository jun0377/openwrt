# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2007 OpenWrt.org

TOPDIR:=${CURDIR}

# C语言环境
LC_ALL:=C
LANG:=C

# 使用UTC时区
TZ:=UTC
export TOPDIR LC_ALL LANG TZ

# 空格的定义
empty:=
space:= $(empty) $(empty)

# 检查TOPDIR是否包括空格
$(if $(findstring $(space),$(TOPDIR)),$(error ERROR: The path to the OpenWrt directory must not include any spaces))

# 空目标，最为构建起始点
world:

# 获取包配置
DISTRO_PKG_CONFIG:=$(shell $(TOPDIR)/scripts/command_all.sh pkg-config | grep -e '/usr' -e '/nix/store' -m 1)

# 如果 ORIG_PATH 已定义，则使用其值，否则使用当前 PATH 变量。
export ORIG_PATH:=$(if $(ORIG_PATH),$(ORIG_PATH),$(PATH))
# 根据是否定义了 STAGING_DIR，设置 PATH 变量，优先使用 staging_dir 中的 host/bin
export PATH:=$(if $(STAGING_DIR),$(abspath $(STAGING_DIR)/../host/bin),$(TOPDIR)/staging_dir/host/bin):$(PATH)

# 当 OPENWRT_BUILD 不等于 1 时，意味着这可能是第一次执行构建，随后会设置一些环境变量、导入必要的配置文件等
ifneq ($(OPENWRT_BUILD),1)

  _SINGLE=export MAKEFLAGS=$(space);					# 定义变量 _SINGLE，设置 MAKEFLAGS 为包含空格的字符串

  override OPENWRT_BUILD=1								# 将 OPENWRT_BUILD 变量强制设置为 1
  export OPENWRT_BUILD
  GREP_OPTIONS=
  export GREP_OPTIONS
  CDPATH=
  export CDPATH
  include $(TOPDIR)/include/debug.mk
  include $(TOPDIR)/include/depends.mk
  include $(TOPDIR)/include/toplevel.mk
else
  include rules.mk
  include $(INCLUDE_DIR)/depends.mk
  include $(INCLUDE_DIR)/subdir.mk
  include target/Makefile
  include package/Makefile
  include tools/Makefile
  include toolchain/Makefile

# Include the test suite Makefile if it exists
-include tests/Makefile

# 定义 toolchain/stamp-compile 目标，依赖于 tools/stamp-compile 和可选的 toolchain_rebuild_check
$(info CONFIG_BUILDBOT value: $(CONFIG_BUILDBOT))
$(toolchain/stamp-compile): $(tools/stamp-compile) $(if $(CONFIG_BUILDBOT),toolchain_rebuild_check)

# 定义 target/stamp-compile 目标，依赖于 toolchain/stamp-compile、tools/stamp-compile 和 BUILD_DIR/.prepared
$(target/stamp-compile): $(toolchain/stamp-compile) $(tools/stamp-compile) $(BUILD_DIR)/.prepared

# 定义 package/stamp-compile 目标，依赖于 target/stamp-compile 和 package/stamp-cleanup
$(package/stamp-compile): $(target/stamp-compile) $(package/stamp-cleanup)

# 定义 package/stamp-install 目标，依赖于 package/stamp-compile
$(package/stamp-install): $(package/stamp-compile)

# 定义 target/stamp-install 目标，依赖于 package/stamp-compile 和 package/stamp-install
$(target/stamp-install): $(package/stamp-compile) $(package/stamp-install)

# 定义 check 目标，依赖于工具链和包的检查目标
check: $(tools/stamp-check) $(toolchain/stamp-check) $(package/stamp-check)

# 定义一个名为 printdb 的目标，执行的命令始终返回成功，不做任何事情
printdb:
	@true

# 定义 prepare 目标，依赖于 target/stamp-compile
prepare: $(target/stamp-compile)

# 定义伪目标 _clean，强制执行，执行删除操作以清理构建目录
_clean: FORCE
	rm -rf $(BUILD_DIR) $(STAGING_DIR) $(BIN_DIR) $(OUTPUT_DIR)/packages/$(ARCH_PACKAGES) $(TOPDIR)/staging_dir/packages

# 定义 clean 目标，依赖于 _clean，执行额外的删除操作以清理构建日志目录
clean: _clean
	rm -rf $(BUILD_LOG_DIR)

# 定义 targetclean 目标，依赖于 _clean，执行删除操作以清理工具链和主机包目录
targetclean: _clean
	rm -rf $(TOOLCHAIN_DIR) $(BUILD_DIR_BASE)/hostpkg $(BUILD_DIR_TOOLCHAIN)

# 定义 dirclean 目标，依赖于 targetclean 和 clean，执行更多的删除操作并调用子目录的清理
dirclean: targetclean clean
	rm -rf $(STAGING_DIR_HOST) $(STAGING_DIR_HOSTPKG) $(BUILD_DIR_BASE)/host
	rm -rf $(TMP_DIR)
	$(MAKE) -C $(TOPDIR)/scripts/config clean

# 定义 toolchain_rebuild_check 目标，执行检查工具链的脚本
toolchain_rebuild_check:
	$(SCRIPT_DIR)/check-toolchain-clean.sh

# 定义 cacheclean 目标，如果 CONFIG_CCACHE 被定义，则清理 ccache 缓存
cacheclean:
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -C
endif

# 检查 DUMP_TARGET_DB 是否未定义，创建 BUILD_DIR/.prepared 文件，确保存在该目录。
ifndef DUMP_TARGET_DB
$(BUILD_DIR)/.prepared: Makefile
	@mkdir -p $$(dirname $@)
	@touch $@

# 定义 tmp/.prereq_packages 目标，检查所有包的先决条件，并在失败时返回错误
tmp/.prereq_packages: .config
	unset ERROR; \
	for package in $(sort $(prereq-y) $(prereq-m)); do \
		$(_SINGLE)$(NO_TRACE_MAKE) -s -r -C package/$$package prereq || ERROR=1; \
	done; \
	if [ -n "$$ERROR" ]; then \
		echo "Package prerequisite check failed."; \
		false; \
	fi
	touch $@
endif

# check prerequisites before starting to build
# 定义 prereq 目标，检查构建前的先决条件，包括特定架构的配置文件
prereq: $(target/stamp-prereq) tmp/.prereq_packages
	@if [ ! -f "$(INCLUDE_DIR)/site/$(ARCH)" ]; then \
		echo 'ERROR: Missing site config for architecture "$(ARCH)" !'; \
		echo '       The missing file will cause configure scripts to fail during compilation.'; \
		echo '       Please provide a "$(INCLUDE_DIR)/site/$(ARCH)" file and restart the build.'; \
		exit 1; \
	fi

$(BIN_DIR)/profiles.json: FORCE
	$(if $(CONFIG_JSON_OVERVIEW_IMAGE_INFO), \
		WORK_DIR=$(BUILD_DIR)/json_info_files \
			$(SCRIPT_DIR)/json_overview_image_info.py $@ \
	)

# 定义 json_overview_image_info 目标，依赖于 profiles.json
json_overview_image_info: $(BIN_DIR)/profiles.json

# 定义 checksum 目标，强制执行，调用 sha256sums 函数计算 checksum
checksum: FORCE
	$(call sha256sums,$(BIN_DIR),$(CONFIG_BUILDBOT))

# 定义 buildversion 目标，调用脚本获取版本并输出到 version.buildinfo 文件
buildversion: FORCE
	$(SCRIPT_DIR)/getver.sh > $(BIN_DIR)/version.buildinfo

# 定义 feedsversion 目标，调用脚本获取 feeds 列表并输出到 feeds.buildinfo 文件
feedsversion: FORCE
	$(SCRIPT_DIR)/feeds list -fs > $(BIN_DIR)/feeds.buildinfo

# 定义 diffconfig 目标，生成构建配置的差异信息并输出到 config.buildinfo 文件
diffconfig: FORCE
	mkdir -p $(BIN_DIR)
	$(SCRIPT_DIR)/diffconfig.sh > $(BIN_DIR)/config.buildinfo

# 定义 buildinfo 目标，强制执行并依赖于 diffconfig、buildversion 和 feedsversion
buildinfo: FORCE
	$(_SINGLE)$(SUBMAKE) -r diffconfig buildversion feedsversion

# 定义 prepare 目标，依赖于 .config、工具的编译和工具链的编译，调用子 Makefile 生成构建信息
prepare: .config $(tools/stamp-compile) $(toolchain/stamp-compile)
	$(_SINGLE)$(SUBMAKE) -r buildinfo

# 定义 world 目标，依赖于 prepare 和其他编译目标，执行索引生成、JSON 信息生成和 checksum 计算
world: prepare $(target/stamp-compile) $(package/stamp-compile) $(package/stamp-install) $(target/stamp-install) FORCE
	$(_SINGLE)$(SUBMAKE) -r package/index
	$(_SINGLE)$(SUBMAKE) -r json_overview_image_info
	$(_SINGLE)$(SUBMAKE) -r checksum
ifneq ($(CONFIG_CCACHE),)
	$(STAGING_DIR_HOST)/bin/ccache -s
endif

# 声明一组伪目标，这些目标不对应实际文件。它们在每次调用时都会被执行
.PHONY: clean dirclean prereq prepare world package/symlinks package/symlinks-install package/symlinks-clean

endif
