#
# Copyright (C) 2006-2010 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

# 定义当前目录变量
curdir:=package

# 包含必要的Makefile片段
include $(INCLUDE_DIR)/feeds.mk
include $(INCLUDE_DIR)/rootfs.mk

# 包含包依赖关系文件
-include $(TMP_DIR)/.packagedeps
# 添加Linux内核包到编译列表
package-y += kernel/linux
# 设置自动移除标志
$(curdir)/autoremove:=1
# 设置构建目录列表，包括所有包类型(y:内置, m:模块, -:不编译)
$(curdir)/builddirs:=$(sort $(package-) $(package-y) $(package-m))
# 设置默认构建目录，包括内置包和模块包
$(curdir)/builddirs-default:=. $(sort $(package-y) $(package-m))
# 设置前置条件构建目录
$(curdir)/builddirs-prereq:=. $(sort $(prereq-y) $(prereq-m))

# 如果定义了CHECK_ALL，设置检查和下载目录
ifdef CHECK_ALL
$(curdir)/builddirs-check:=$($(curdir)/builddirs)
$(curdir)/builddirs-download:=$($(curdir)/builddirs)
endif

# 错误处理配置
ifneq ($(IGNORE_ERRORS),)
  # 过滤不同类型的包
  package-y-filter := $(package-y)
  package-m-filter := $(filter-out $(package-y),$(package-m))
  package-n-filter := $(filter-out $(package-y) $(package-m),$(package-))
  # 设置忽略错误的包类型
  package-ignore-errors := $(filter n m y,$(IGNORE_ERRORS))
  package-ignore-errors := $(if $(package-ignore-errors),$(package-ignore-errors),n m)
  # 设置忽略错误的子目录
  package-ignore-subdirs := $(sort $(foreach m,$(package-ignore-errors),$(package-$(m)-filter)))
  # 设置忽略下载和编译的目录
  $(curdir)/builddirs-ignore-download := $(package-ignore-subdirs)
  $(curdir)/builddirs-ignore-compile := $(package-ignore-subdirs)
  $(curdir)/builddirs-ignore-host-download := $(package-ignore-subdirs)
  $(curdir)/builddirs-ignore-host-compile := $(package-ignore-subdirs)
endif

# 定义安装文件列表，处理包变体
PACKAGE_INSTALL_FILES:= \
	$(foreach pkg,$(sort $(package-y)), \
		$(foreach variant, \
			$(if $(strip $(package/$(pkg)/variants)), \
				$(package/$(pkg)/variants), \
				$(if $(package/$(pkg)/default-variant), \
					$(package/$(pkg)/default-variant), \
					default \
				) \
			), \
			$(PKG_INFO_DIR)/$(lastword $(subst /,$(space),$(pkg))).$(variant).install \
		) \
	)

# 清理目标：删除暂存目录
$(curdir)/cleanup: $(TMP_DIR)/.build
	rm -rf $(STAGING_DIR_ROOT)

# 合并目标：合并所有包文件
$(curdir)/merge:
	rm -rf $(PACKAGE_DIR_ALL)
	mkdir -p $(PACKAGE_DIR_ALL)

# 根据包类型(APK或IPK)创建软链接
ifneq ($(CONFIG_USE_APK),)
	-$(foreach pdir,$(PACKAGE_SUBDIRS),$(if $(wildcard $(pdir)/*.apk),ln -s $(pdir)/*.apk $(PACKAGE_DIR_ALL);))
else
	-$(foreach pdir,$(PACKAGE_SUBDIRS),$(if $(wildcard $(pdir)/*.ipk),ln -s $(pdir)/*.ipk $(PACKAGE_DIR_ALL);))
endif

# 生成APK密钥对
$(BUILD_KEY_APK_SEC):
	$(STAGING_DIR_HOST)/bin/openssl ecparam -name prime256v1 -genkey -noout -out $(BUILD_KEY_APK_SEC)

$(BUILD_KEY_APK_PUB): $(BUILD_KEY_APK_SEC)
	$(STAGING_DIR_HOST)/bin/openssl ec -in $(BUILD_KEY_APK_SEC) -pubout > $(BUILD_KEY_APK_PUB)

# 合并索引目标：生成包索引
$(curdir)/merge-index: $(curdir)/merge
ifneq ($(CONFIG_USE_APK),)
	(cd $(PACKAGE_DIR_ALL) && $(STAGING_DIR_HOST)/bin/apk mkndx \
			--root $(TOPDIR) \
			--keys-dir $(TOPDIR) \
			--sign $(BUILD_KEY_APK_SEC) \
			--output packages.adb \
			*.apk; \
	)
else
	(cd $(PACKAGE_DIR_ALL) && $(SCRIPT_DIR)/ipkg-make-index.sh . 2>&1 > Packages; )
endif

# 编译目标配置
ifndef SDK
  $(curdir)//compile = $(STAGING_DIR)/.prepared $(BIN_DIR)
ifneq ($(CONFIG_USE_APK),)
  $(curdir)//compile += $(curdir)/system/apk/host/compile $(BUILD_KEY_APK_SEC) $(BUILD_KEY_APK_PUB)
else
  $(curdir)/compile: $(curdir)/system/opkg/host/compile
endif
else
ifneq ($(CONFIG_USE_APK),)
  $(curdir)//compile += $(BUILD_KEY_APK_SEC) $(BUILD_KEY_APK_PUB)
endif
endif

# 安装目标：安装所有包
$(curdir)/install: $(TMP_DIR)/.build $(curdir)/merge $(curdir)/merge-index
	- find $(STAGING_DIR_ROOT) -type d | $(XARGS) chmod 0755
	rm -rf $(TARGET_DIR) $(TARGET_DIR_ORIG)
	mkdir -p $(TARGET_DIR)/tmp

# 根据包类型执行不同的安装命令
ifneq ($(CONFIG_USE_APK),)
	$(file >$(TMP_DIR)/apk_install_list,\
	    $(foreach pkg,$(shell cat $(PACKAGE_INSTALL_FILES) 2>/dev/null),$(pkg)$(call GetABISuffix,$(pkg))))
	$(call apk,$(TARGET_DIR)) add --initdb --no-scripts --arch $(ARCH_PACKAGES) \
		--repositories-file /dev/zero --repository file://$(PACKAGE_DIR_ALL)/packages.adb \
		$$(cat $(TMP_DIR)/apk_install_list)
else
	$(file >$(TMP_DIR)/opkg_install_list,\
	  $(call opkg_package_files,\
	    $(foreach pkg,$(shell cat $(PACKAGE_INSTALL_FILES) 2>/dev/null),$(pkg)$(call GetABISuffix,$(pkg)))))
	$(call opkg,$(TARGET_DIR)) install $$(cat $(TMP_DIR)/opkg_install_list)
	@for file in $(PACKAGE_INSTALL_FILES); do \
		[ -s $$file.flags ] || continue; \
		for flag in `cat $$file.flags`; do \
			$(call opkg,$(TARGET_DIR)) flag $$flag `cat $$file`; \
		done; \
	done || true
endif

	$(CP) $(TARGET_DIR) $(TARGET_DIR_ORIG)

	$(call prepare_rootfs,$(TARGET_DIR),$(TOPDIR)/files)

# 索引目标：生成包索引
$(curdir)/index: FORCE
	@echo Generating package index...
ifneq ($(CONFIG_USE_APK),)
	@for d in $(PACKAGE_SUBDIRS); do \
		mkdir -p $$d; \
		cd $$d || continue; \
		ls *.apk >/dev/null 2>&1 || continue; \
		$(STAGING_DIR_HOST)/bin/apk mkndx \
			--root $(TOPDIR) \
			--keys-dir $(TOPDIR) \
			--sign $(BUILD_KEY_APK_SEC) \
			--output packages.adb \
			$$(ls *.apk | grep -v 'kernel\|libc'); \
	done
else
	@for d in $(PACKAGE_SUBDIRS); do ( \
		mkdir -p $$d; \
		cd $$d || continue; \
		$(SCRIPT_DIR)/ipkg-make-index.sh . 2>&1 > Packages.manifest; \
		grep -vE '^(Maintainer|LicenseFiles|Source|SourceName|Require|SourceDateEpoch)' Packages.manifest > Packages; \
		case "$$(((64 + $$(stat -L -c%s Packages)) % 128))" in 110|111) \
			$(call ERROR_MESSAGE,WARNING: Applying padding in $$d/Packages to workaround usign SHA-512 bug!); \
			{ echo ""; echo ""; } >> Packages;; \
		esac; \
		echo -n '{"architecture": "$(ARCH_PACKAGES)", "packages":{' > index.json; \
		sed -n -e 's/^Package: \(.*\)$$/"\1":/p' -e 's/^Version: \(.*\)$$/"\1",/p' Packages | tr '\n' ' ' >> index.json; \
		echo '}}' >> index.json; \
		sed -i 's/, }}/}}/' index.json; \
		gzip -9nc Packages > Packages.gz; \
	); done

# 如果启用了包签名，对索引进行签名
ifdef CONFIG_SIGNED_PACKAGES
	@echo Signing package index...
	@for d in $(PACKAGE_SUBDIRS); do ( \
		[ -d $$d ] && \
			cd $$d || continue; \
		$(STAGING_DIR_HOST)/bin/usign -S -m Packages -s $(BUILD_KEY); \
	); done
endif

# 如果启用了CycloneDX SBOM，创建软件物料清单
ifdef CONFIG_JSON_CYCLONEDX_SBOM
	@echo Creating CycloneDX package SBOMs...
	@for d in $(PACKAGE_SUBDIRS); do ( \
		[ -d $$d ] && \
			cd $$d || continue; \
		$(SCRIPT_DIR)/package-metadata.pl pkgcyclonedxsbom Packages.manifest > Packages.bom.cdx.json || true; \
	); done
endif
endif

# 安装标志设置
$(curdir)/flags-install:= -j1

# 生成各种构建阶段的时间戳文件
# 前置依赖检查
$(eval $(call stampfile,$(curdir),package,prereq,.config))
# 清理
$(eval $(call stampfile,$(curdir),package,cleanup,$(TMP_DIR)/.build))
# 编译
$(eval $(call stampfile,$(curdir),package,compile,$(TMP_DIR)/.build))
#安装
$(eval $(call stampfile,$(curdir),package,install,$(TMP_DIR)/.build))
# 校验
$(eval $(call stampfile,$(curdir),package,check,$(TMP_DIR)/.build))

# 将当前目录注册为构建系统的子模块，对子目录中的Makefile递归处理
$(eval $(call subdir,$(curdir)))
