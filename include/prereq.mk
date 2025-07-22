# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2020 OpenWrt.org

# 防止重复包含
ifneq ($(__prereq_inc),1)
__prereq_inc:=1

# 定义 prereq 目标，用于检查编译前置条件: 如果存在错误文件，则显示错误信息并退出
prereq:
	if [ -f $(TMP_DIR)/.prereq-error ]; then \
		echo; \
		cat $(TMP_DIR)/.prereq-error; \
		rm -f $(TMP_DIR)/.prereq-error; \
		echo; \
		false; \
	fi

# 设置 prereq 目标为静默模式
.SILENT: prereq
endif

# 用于存储前一个检查项的名称
PREREQ_PREV=

# 1: display name
# 2: error message
# 定义 Require 函数，用于检查依赖项
# 1: 显示名称
# 2: 错误消息
define Require
  # 设置检查标志
  export PREREQ_CHECK=1
  # 如果该项未被检查过, 则将此检查添加到 prereq 目标的依赖中
  ifeq ($$(CHECK_$(1)),)
    # 将此检查添加到 prereq 目标的依赖中
    prereq: prereq-$(1)

	# 定义具体的检查目标，依赖于前一个检查项
    prereq-$(1): $(if $(PREREQ_PREV),prereq-$(PREREQ_PREV)) FORCE
		printf "Checking '$(1)'... "
		if $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'ok.'; \
		elif $(NO_TRACE_MAKE) -f $(firstword $(MAKEFILE_LIST)) check-$(1) PATH="$(ORIG_PATH)" >/dev/null 2>/dev/null; then \
			echo 'updated.'; \
		else \
			echo 'failed.'; \
			echo "$(PKG_NAME): $(strip $(2))" >> $(TMP_DIR)/.prereq-error; \
		fi

	# 定义实际的检查命令
    check-$(1): FORCE
	  $(call Require/$(1))
    CHECK_$(1):=1

	# 设置为静默模式并禁止并行执行
    .SILENT: prereq-$(1) check-$(1)
    .NOTPARALLEL:
  endif

  # 更新前一个检查项
  PREREQ_PREV=$(1)
endef

# 定义 RequireCommand 函数，用于检查命令是否存在
# 1: 命令名称
# 2: 错误消息
define RequireCommand
  define Require/$(1)
    command -v $(1)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 定义 RequireHeader 函数，用于检查头文件是否存在
# 1: 头文件路径
# 2: 错误消息
define RequireHeader
  define Require/$(1)
    [ -e "$(1)" ]
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 1: header to test
# 2: failure message
# 3: optional compile time test
# 4: optional link library test (example -lncurses)
# 定义 RequireCHeader 函数，用于检查 C 头文件并编译测试
# 1: 要测试的头文件
# 2: 错误消息
# 3: 可选的编译时测试代码
# 4: 可选的链接库测试（例如 -lncurses）
define RequireCHeader
  define Require/$(1)
    echo 'int main(int argc, char **argv) { $(3); return 0; }' | gcc -include $(1) -x c -o $(TMP_DIR)/a.out - $(4)
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 定义 QuoteHostCommand 函数，用于正确引用命令字符串
define QuoteHostCommand
'$(subst ','"'"',$(strip $(1)))'
endef

# 1: display name
# 2: failure message
# 3: test
# 定义 TestHostCommand 函数，用于测试主机命令
# 1: 显示名称
# 2: 错误消息
# 3: 测试命令
define TestHostCommand
  define Require/$(1)
	($(3)) >/dev/null 2>/dev/null
  endef

  $$(eval $$(call Require,$(1),$(2)))
endef

# 1: canonical name
# 2: failure message
# 3+: candidates
# 定义 SetupHostCommand 函数，用于设置主机命令
# 1: 规范名称
# 2: 错误消息
# 3+: 候选命令
define SetupHostCommand
  define Require/$(1)
	mkdir -p "$(STAGING_DIR_HOST)/bin"; \
	for cmd in $(call QuoteHostCommand,$(3)) $(call QuoteHostCommand,$(4)) \
	           $(call QuoteHostCommand,$(5)) $(call QuoteHostCommand,$(6)) \
	           $(call QuoteHostCommand,$(7)) $(call QuoteHostCommand,$(8)) \
	           $(call QuoteHostCommand,$(9)) $(call QuoteHostCommand,$(10)) \
	           $(call QuoteHostCommand,$(11)) $(call QuoteHostCommand,$(12)); do \
		if [ -n "$$$$$$$$cmd" ]; then \
			bin="$$$$$$$$(command -v "$$$$$$$${cmd%% *}")"; \
			if [ -x "$$$$$$$$bin" ] && eval "$$$$$$$$cmd" >/dev/null 2>/dev/null; then \
				case "$$$$$$$$(ls -dl -- $(STAGING_DIR_HOST)/bin/$(strip $(1)))" in \
					"-"* | \
					*" -> $$$$$$$$bin"* | \
					*" -> "[!/]*) \
						[ -x "$(STAGING_DIR_HOST)/bin/$(strip $(1))" ] && exit 0 \
						;; \
				esac; \
				ln -sf "$$$$$$$$bin" "$(STAGING_DIR_HOST)/bin/$(strip $(1))"; \
				exit 1; \
			fi; \
		fi; \
	done; \
	exit 1
  endef

  $$(eval $$(call Require,$(1),$(if $(2),$(2),Missing $(1) command)))
endef
