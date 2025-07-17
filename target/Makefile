# 
# Copyright (C) 2007 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

# 设置目录为target目录
curdir:=target

# 定义一系列目录变量
$(curdir)/subtargets:=install
$(curdir)/builddirs:=linux sdk imagebuilder toolchain llvm-bpf
$(curdir)/builddirs-default:=linux
$(curdir)/builddirs-install:=\
	linux \
	$(if $(CONFIG_SDK),sdk) \
	$(if $(CONFIG_IB),imagebuilder) \
	$(if $(CONFIG_MAKE_TOOLCHAIN),toolchain) \
	$(if $(CONFIG_SDK_LLVM_BPF),llvm-bpf)

$(curdir)/sdk/install:=$(curdir)/linux/install
$(curdir)/imagebuilder/install:=$(curdir)/linux/install

$(curdir)//compile = $(STAGING_DIR)/.prepared $(BIN_DIR)

# 生成时间戳文件：调用 stampfile 函数，生成与 prereq 相关的时间戳文件，确保在配置文件 .config 更新后重新执行相关操作
$(eval $(call stampfile,$(curdir),target,prereq,.config))
# 生成编译时间戳文件：调用 stampfile 函数，生成与编译相关的时间戳文件，依赖于 $(TMP_DIR)/.build
$(eval $(call stampfile,$(curdir),target,compile,$(TMP_DIR)/.build))
# 生成安装时间戳文件：调用 stampfile 函数，生成与安装相关的时间戳文件，依赖于 $(TMP_DIR)/.build
$(eval $(call stampfile,$(curdir),target,install,$(TMP_DIR)/.build))
# 定义安装依赖：设置 stamp-install 目标依赖于 stamp-compile，在安装之前必须先完成编译
$($(curdir)/stamp-install): $($(curdir)/stamp-compile) 
# 处理子目录：调用 subdir 函数，处理当前目录的子目录，通常用于递归构建子模
$(eval $(call subdir,$(curdir)))
