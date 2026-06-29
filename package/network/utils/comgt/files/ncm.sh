#!/bin/sh

# NCM协议处理脚本，用于OpenWrt系统中管理NCM调制解调器连接

[ -n "$INCLUDE_ONLY" ] || {
	
	logger -t "NCM" "Init..."

	# 加载OpenWrt通用函数库
	. /lib/functions.sh
	# 加载网络接口守护进程协议处理函数
	. ../netifd-proto.sh

	# 初始化协议处理器
	logger -t "NCM" "$@"
	init_proto "$@"
}

# NCM协议配置初始化函数
proto_ncm_init_config() {
	
	logger -t "NCM" "$FUNCNAME Enter proto_ncm_init_config"

	# 标记此协议不需要物理设备
	no_device=1
	# 标记协议可用
	available=1
	# 添加设备路径配置项
	proto_config_add_string "device:device"
	# 添加接口名称配置项
	proto_config_add_string ifname
	# 添加接入点名称配置项
	proto_config_add_string apn
	# 添加认证方式配置项
	proto_config_add_string auth
	# 添加用户名配置项
	proto_config_add_string username
	# 添加密码配置项
	proto_config_add_string password
	# 添加PIN码配置项
	proto_config_add_string pincode
	# 添加延迟时间配置项
	proto_config_add_string delay
	# 添加工作模式配置项
	proto_config_add_string mode
	# 添加PDP类型配置项（IP/IPV6/IPV4V6）
	proto_config_add_string pdptype
	# 添加源过滤配置项
	proto_config_add_boolean sourcefilter
	# 添加委托配置项
	proto_config_add_boolean delegate
	# 添加配置文件编号配置项
	proto_config_add_int profile
	# 添加默认配置项
	proto_config_add_defaults

	logger -t "NCM" "<${ifname}:${device}> $FUNCNAME Exit proto_ncm_init_config"
}

ncm_mask2prefix() {
	local mask="$1"
	local prefix=0
	local octet old_ifs

	old_ifs="$IFS"
	IFS=.
	set -- $mask
	IFS="$old_ifs"

	for octet in "$@"; do
		case "$octet" in
			255) prefix=$((prefix + 8)) ;;
			254) prefix=$((prefix + 7)) ;;
			252) prefix=$((prefix + 6)) ;;
			248) prefix=$((prefix + 5)) ;;
			240) prefix=$((prefix + 4)) ;;
			224) prefix=$((prefix + 3)) ;;
			192) prefix=$((prefix + 2)) ;;
			128) prefix=$((prefix + 1)) ;;
			0) ;;
			*) return 1 ;;
		esac
	done

	echo "$prefix"
}

# 停止track-sim procd实例
function sim_procd_stop()
{
	local ifname="$1"
	[ -n "$ifname" ] || return 1

	. /lib/functions/service.sh

	local service_name="tracker-sim-${ifname}"
	local pid_file="/var/run/${service_name}.pid"

	local SERVICE_NAME="$service_name"
	local SERVICE_PID_FILE="$pid_file"
	local SERVICE_USE_PID=1
	local SERVICE_MATCH_EXEC=

	if service_check /bin/tracker-sim "$ifname"; then
		logger -t "NCM" "stop ${service_name}"
		service_stop /bin/tracker-sim "$ifname"
		rm -f "$pid_file"
	fi
}

# 创建track-sim procd实例
function sim_procd_start()
{
	local ifname="$1"
	[ -n "$ifname" ] || return 1

	. /lib/functions/service.sh

	local service_name="tracker-sim-${ifname}"
	local pid_file="/var/run/${service_name}.pid"

	local SERVICE_NAME="$service_name"
	local SERVICE_PID_FILE="$pid_file"
	local SERVICE_DAEMONIZE=1
	local SERVICE_WRITE_PID=1
	local SERVICE_USE_PID=
	local SERVICE_MATCH_EXEC=

	if service_check /bin/tracker-sim "$ifname"; then
		logger -t "NCM" "${service_name} already running"
		return 0
	fi

	logger -t "NCM" "start ${service_name}"
	service_start /bin/tracker-sim "$ifname"
}

# NCM协议连接建立函数
proto_ncm_setup() {

	logger -t "NCM" "Enter proto_ncm_setup"

	# 获取接口名称参数
	local ifname="$1"
	logger -t "NCM" "ifname:${ifname}"

	# 停止tracker-sim进程, 避免AT指令串口竞争
	[ ! -z "${ifname}" ] && sim_procd_stop $ifname

	# 声明本地变量用于存储调制解调器相关信息
	local manufacturer devname devpath ifpath
	local ip mask gw prefix

	local device apn auth username password pincode delay mode pdptype profile $PROTO_DEFAULT_OPTIONS
	json_get_vars device apn auth username password pincode delay mode pdptype sourcefilter delegate profile $PROTO_DEFAULT_OPTIONS

	local context_type

	[ "$metric" = "" ] && metric="0"
	# logger -t "NCM" "metric:${metric}"

	[ -n "$profile" ] || profile=1
	# logger -t "NCM" "profile:${profile}"

	# 检查sysfs中是否已有模组对应信息
	config_load sim
    config_get sysfs "$ifname" usb
	[ -z "$sysfs" ] && {
		logger -t "NCM" "$ifname sysfs is not defined! (uci get sim.$ifname.usb)" 
		# proto_set_available "$ifname" 0
		return 1
	}
    [ ! -d "$sysfs" ] && {
		logger -t "NCM" "$ifname sysfs is not exist! sysfs:${sysfs}" 
		return 1
	}

	logger -t "NCM" "$ifname sysfs:${sysfs}"

	# 获取ttyUSB名称
	config_get ttyUSB "$ifname" ttyUSB
	[ -z "$ttyUSB" ] && {
		logger -t "NCM" "$ifname ttyUSB is not defined! (uci get sim.$ifname.ttyUSB)"
		# proto_set_available "$ifname" 0
		return 1
	}
	[ ! -d "$sysfs/$ttyUSB" ] && {
		logger -t "NCM" "$ifname ttyUSB sysfs path is not exist! $sysfs/$ttyUSB"
		# proto_set_available "$ifname" 0
		return 1
	}
	ttyUSB=$(ls "$sysfs/$ttyUSB" | grep ttyUSB)
	[ -z "$ttyUSB" ] && {
		logger -t "NCM" "$ifname can not find ttyUSB in $sysfs/$ttyUSB"
		# proto_set_available "$ifname" 0
		return 1
	}
	ttyUSB="/dev/${ttyUSB}"
	logger -t "NCM" "$ifname $ttyUSB"

	# 接口真实名称,如: eth1 eth2
	interface=$(ls "$sysfs"/*/net/ 2>/dev/null)
	[ -z "$interface" ] && {
		logger -t "NCM" "$ifname can not find interface in ${sysfs}"
		return 1
	}

	logger -t "NCM" "$ifname $ttyUSB $interface"

	# 检查是否成功获取接口名称
	[ -n "$interface" ] || {
		logger -t "NCM" "The interface could not be found."
		# proto_notify_error "$ifname" NO_IFACE
		# proto_set_available "$ifname" 0		
		return 1
	}

	logger -t "NCM" "ifname:${ifname} interface:${interface} device:${device}"

	# 获取模组的VID:PID
	VID=$(cat /sys/bus/usb/devices/$(basename $sysfs)/idVendor)
    [ -z "$VID" ] && { 
		logger -t "NCM" "ifname:${ifname} unknown Vendor! "
		return 1
	}
	PID=$(cat /sys/bus/usb/devices/$(basename $sysfs)/idProduct)
    [ -z "$PID" ] && {
		logger -t "NCM" "ifname:${ifname} unknown Product! "
		return 1
	}

	logger -t "NCM" "ifname:${ifname} VID:PID=$VID:$PID"

	# 根据VID:PID加载对应的AT指令脚本
	[ ! -z ${VID} ] && [ ! -z ${PID} ] && {
		ATCMD_FILE=/usr/share/omr/lib/${VID}${PID}.sh
		[ ! -f ${ATCMD_FILE} ] && {
			logger -t "NCM" "ifname:${ifname} ${ATCMD_FILE} is not exist!"
			return 1
		}

		logger -t "NCM" "ifname:${ifname} ${ATCMD_FILE}"

		# 保存变量, 避免source ATCMD脚本时被顶层的赋值语句清空
		local _saved_ttyUSB="$ttyUSB"
		local _saved_interface="$interface"
		. ${ATCMD_FILE} $ifname
		ttyUSB="$_saved_ttyUSB"
		interface="$_saved_interface"
	}

	# 模组初始化
	atcmd_init ${ttyUSB}

	# 模组未使能,直接退出并不再重新尝试拨号, uci get sim.sim1.enable
	local enable=$(uci -q get sim.$ifname.enable)
	[ -n "$enable" ] && [ "$enable" != "1" ] && [ "$enable" != "true" ] && {
		logger -t "NCM" "ifname:${ifname} sim is disabled by user, exit"
		sim_procd_start "${ifname}"
		proto_block_restart "$ifname"
		return 1
	}

	logger -t "NCM" "ifname:${ifname} before atcmd_dial"

	# 拨号成功则进行DHCP
	# 拨号失败时退出并启动tracker-sim进程, 监控何时可以重新拨号
	if ! atcmd_dial ${ttyUSB}; then
		logger -t "NCM" "ifname:${ifname} atcmd_dial failed!"
		sim_procd_start ${ifname}
		sleep 20
		return 1
	fi

	logger -t "NCM" "ifname:${ifname} after atcmd_dial"

	# 启动tracker-sim, 进行状态监控
	sim_procd_start ${ifname}

	# 执行dhcp, 最多尝试15秒
	ifconfig ${interface} up
	res="$(udhcpc -i "$interface" -t 5 -T 3 -n -q 2>&1)"
	printf '%s\n' "$res" | while IFS= read -r line; do
		[ -n "$line" ] && logger -t "NCM" "ifname:${ifname} interface:${interface} device:${device} $line"
	done

	ip="$(echo "$res" | awk '/lease of/ {print $4; exit}')"
	mask="$(echo "$res" | awk '/ip addr add/ {split($5,a,"/"); print a[2]; exit}')"
	gw="$(echo "$res" | sed -n 's/.*setting default routers:[[:space:]]*//p' | awk '{print $1; exit}')"
	logger -t "NCM" "ifname:${ifname} interface:${interface} ip:${ip} mask:${mask} gw:${gw}"
	[ -n "$ip" ] || {
		logger -t "NCM" "ifname:${ifname} interface:${interface} DHCP did not return IPv4 address"
		proto_notify_error "$ifname" NO_CARRIER
		return 1
	}
	prefix="$(ncm_mask2prefix "$mask" 2>/dev/null)"
	[ -n "$prefix" ] || {
		logger -t "NCM" "ifname:${ifname} interface:${interface} invalid netmask:${mask}"
		proto_notify_error "$ifname" NO_CARRIER
		return 1
	}
	
	# 设置网络接口
	echo "Setting up $ifname"
	logger -t "NCM" "ifname:${ifname} interface:${interface} Setting up $ifname"
	# 初始化接口更新（启用）
	proto_init_update "$interface" 1
	proto_add_ipv4_address "$ip" "$prefix"
	[ -n "$gw" ] && proto_add_ipv4_route "0.0.0.0" 0 "$gw"
	# 开始添加协议数据
	proto_add_data
	# 添加制造商信息
	json_add_string "manufacturer" "$manufacturer"
	# 结束数据添加
	proto_close_data
	# 发送接口更新
	proto_send_update "$ifname"

	logger -t "NCM" "ifname:${ifname} interface:${interface} device:${device} Exit proto_ncm_setup"
}

# NCM协议连接断开函数
proto_ncm_teardown() {

	local ifname="$1"
	logger -t "NCM" "ifname:${ifname} interface:${interface} device:${device} Enter teardown"
	
	sleep 1

	# 更新接口状态为关闭
	# 初始化接口更新（禁用所有）
	proto_init_update "*" 0
	# 发送接口更新
	proto_send_update "$ifname"

	logger -t "NCM" "ifname:${ifname} interface:${interface} device:${device} Exit teardown"
}

# 如果不是仅包含模式则注册NCM协议
[ -n "$INCLUDE_ONLY" ] || {
	logger -t "NCM" "add protocol ncm"
	add_protocol ncm
}
