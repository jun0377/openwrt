# Shell script compatibility wrappers for /sbin/uci
#
# Copyright (C) 2008-2010  OpenWrt.org
# Copyright (C) 2008  Felix Fietkau <nbd@nbd.name>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

CONFIG_APPEND=

# 从UCI配置文件中读取配置并将其转换为shell环境变量
uci_load() {
	# 要加载的UCI配置包名称
	local PACKAGE="$1"
	local DATA
	local RET
	local VAR

	_C=0
	# 非追加模式,清理现有配置
	if [ -z "$CONFIG_APPEND" ]; then
		for VAR in $CONFIG_LIST_STATE; do
			export ${NO_EXPORT:+-n} CONFIG_${VAR}=
			export ${NO_EXPORT:+-n} CONFIG_${VAR}_LENGTH=
		done
		export ${NO_EXPORT:+-n} CONFIG_LIST_STATE=
		export ${NO_EXPORT:+-n} CONFIG_SECTIONS=
		export ${NO_EXPORT:+-n} CONFIG_NUM_SECTIONS=0
		export ${NO_EXPORT:+-n} CONFIG_SECTION=
	fi

	# 从UCI读取配置数据
	DATA="$(/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} ${LOAD_STATE:+-P /var/state} -S -n export "$PACKAGE" 2>/dev/null)"
	RET="$?"

	# 执行配置数据
	[ "$RET" != 0 -o -z "$DATA" ] || eval "$DATA"
	unset DATA

	# 如果设置了 CONFIG_SECTION ，则调用 config_cb 回调
	${CONFIG_SECTION:+config_cb}
	return "$RET"
}

# 如果指定的配置包不存在，则导入默认配置并提交。这通常用于确保系统中存在必要的配置文
uci_set_default() {
	local PACKAGE="$1"
	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} -q show "$PACKAGE" > /dev/null && return 0
	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} import "$PACKAGE"
	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} commit "$PACKAGE"
}

# 恢复状态配置到上一次提交的状态。这个函数操作的是 /var/state 目录下的状态文件，而不是主配置文
uci_revert_state() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} -P /var/state revert "$PACKAGE${CONFIG:+.$CONFIG}${OPTION:+.$OPTION}"
}

# 设置状态配置的值。状态配置存储在 /var/state 目录下，用于记录运行时状态，不会持久化到主配置文件中
uci_set_state() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	[ "$#" = 4 ] || return 0
	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} -P /var/state set "$PACKAGE.$CONFIG${OPTION:+.$OPTION}=$VALUE"
}

# 先恢复状态配置，然后再设置新值。这是一个组合操作，确保状态配置被正确更新
uci_toggle_state() {
	uci_revert_state "$1" "$2" "$3"
	uci_set_state "$1" "$2" "$3" "$4"
}

# 设置配置选项的值。这是修改配置的基本函数，会修改主配置文件
uci_set() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} set "$PACKAGE.$CONFIG.$OPTION=$VALUE"
}

# 向列表类型的配置选项添加一个值。UCI 支持列表类型的配置，这个函数用于向列表中添加元素
uci_add_list() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} add_list "$PACKAGE.$CONFIG.$OPTION=$VALUE"
}

# 获取状态配置的值。这是一个封装函数，调用 uci_get 并指定状态目录
uci_get_state() {
	uci_get "$1" "$2" "$3" "$4" "/var/state"
}

# 获取配置选项的值。如果获取失败且提供了默认值，则返回默认值。这是读取配置的基本函数
uci_get() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local DEFAULT="$4"
	local STATE="$5"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} ${STATE:+-P $STATE} -q get "$PACKAGE${CONFIG:+.$CONFIG}${OPTION:+.$OPTION}"
	RET="$?"
	[ "$RET" -ne 0 ] && [ -n "$DEFAULT" ] && echo "$DEFAULT"
	return "$RET"
}

# 添加一个新的配置节。如果未指定配置名称，则自动生成；否则使用指定的名称。添加后，将新节的名称存储在 CONFIG_SECTION 环境变量中
uci_add() {
	local PACKAGE="$1"
	local TYPE="$2"
	local CONFIG="$3"

	if [ -z "$CONFIG" ]; then
		export ${NO_EXPORT:+-n} CONFIG_SECTION="$(/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} add "$PACKAGE" "$TYPE")"
	else
		/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} set "$PACKAGE.$CONFIG=$TYPE"
		export ${NO_EXPORT:+-n} CONFIG_SECTION="$CONFIG"
	fi
}

# 重命名配置节或配置选项。可以用于重命名整个配置节或者单个配置选项
uci_rename() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} rename "$PACKAGE.$CONFIG${VALUE:+.$OPTION}=${VALUE:-$OPTION}"
}

# 删除配置节或配置选项。如果只指定了包和配置节，则删除整个配置节；如果还指定了选项，则只删除该选项
uci_remove() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} del "$PACKAGE.$CONFIG${OPTION:+.$OPTION}"
}

# 从列表类型的配置选项中删除指定的值。这是 uci_add_list 的反操作
uci_remove_list() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"
	local VALUE="$4"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} del_list "$PACKAGE.$CONFIG.$OPTION=$VALUE"
}

# 恢复配置到上一次提交的状态。这个函数操作的是主配置文件，而不是状态文件
uci_revert() {
	local PACKAGE="$1"
	local CONFIG="$2"
	local OPTION="$3"

	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} revert "$PACKAGE${CONFIG:+.$CONFIG}${OPTION:+.$OPTION}"
}

# 提交配置更改。
uci_commit() {
	local PACKAGE="$1"
	/sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} commit $PACKAGE
}
