#!/bin/sh
# Copyright (C) 2011 OpenWrt.org

# OpenWrt 的 核心网络工具库, 被其他脚本通过 . /lib/network/config.sh 引入。它提供了与 netifd 交互的基础设施函数

# boot流程中的角色
# /etc/init.d/boot
#  └─ /bin/board_detect (硬件探测)
#  └─ . /lib/network/config.sh
#  └─ scan_interfaces         ← 扫描所有接口, 修正 ifname
#  └─ setup_switch            ← 配置交换机
#  └─ 遍历 lan/wan 接口:
#       prepare_interface_bridge lan   ← 创建 br-lan

. /usr/share/libubox/jshn.sh

# 根据网络设备名反查对应的 netifd interface 名称
# 通过 ubus 查询所有接口状态, 匹配 device 或 l3_device
# 参数: $1 = Linux 设备名 (如 eth1)
# 输出: matching interface 名 (如 wan)
find_config() {
	local device="$1"
	local ifdev ifl3dev ifobj
	for ifobj in $(ubus list network.interface.\*); do
		interface="${ifobj##network.interface.}"
		(
			json_load "$(ifstatus $interface)"
			json_get_var ifdev device
			json_get_var ifl3dev l3_device
			if [ "$device" = "$ifdev" ] || [ "$device" = "$ifl3dev" ]; then
				echo "$interface"
				exit 0
			else
				exit 1
			fi
		) && return
	done
}

unbridge() {
	return
}

# 标准 ubus 调用封装: json 初始化 → 调用 → 加载结果
# 参数: $1 = ubus 路径 (如 network.interface.wan), $2 = 方法名 (如 status)
# 返回值: 0=成功, 1=失败
ubus_call() {
	json_init
	local _data="$(ubus -S call "$1" "$2")"
	[ -z "$_data" ] && return 1
	json_load "$_data"
	return 0
}


# 修复接口的 ifname 属性: bridge 类型前缀 br-, 其他类型用 l3_device
# 由 scan_interfaces 通过 config_foreach 对每个 interface 回调
# 参数: $1 = config section 名
fixup_interface() {
	local config="$1"
	local ifname type device l3dev

	config_get type "$config" type
	config_get ifname "$config" ifname
	[ "bridge" = "$type" ] && ifname="br-$config"
	ubus_call "network.interface.$config" status || return 0
	json_get_var l3dev l3_device
	[ -n "$l3dev" ] && ifname="$l3dev"
	json_init
	config_set "$config" ifname "$ifname"
}

# 遍历所有配置接口并修正 ifname (加载 network 配置 → 逐个 fixup)
scan_interfaces() {
	config_load network
	config_foreach fixup_interface interface
}

# 准备 bridge 接口 (触发 netifd 创建 bridge 设备且上线)
# 参数: $1 = config section 名
prepare_interface_bridge() {
	local config="$1"

	[ -n "$config" ] || return 0
	ubus call network.interface."$config" prepare
}

# 将物理设备添加到 netifd 接口 (用于 tap/tun 等虚拟设备绑定)
# 参数: $1 = Linux 设备名, $2 = config section 名
setup_interface() {
	local iface="$1"
	local config="$2"

	[ -n "$config" ] || return 0
	ubus call network.interface."$config" add_device "{ \"name\": \"$iface\" }"
}

# sysctl 读写封装: 有值则写, 无值则读
# 参数: $1 = sysctl 键名, $2 = 要设置的值 (可选)
do_sysctl() {
	[ -n "$2" ] && \
		sysctl -n -e -w "$1=$2" >/dev/null || \
		sysctl -n -e "$1"
}
