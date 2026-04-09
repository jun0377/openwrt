#!/bin/sh

# NCM协议处理脚本，用于OpenWrt系统中管理NCM调制解调器连接


# 通过usb总线号和端口号，获取/dev/ttyUSBx
function get_usb_by_ttyUSB()
{
    # /dev/ttyUSB2 => ttyUSB2
    local ttyUSB=$(basename $1)
    echo $(find /sys/devices/platform -name ${ttyUSB} | head -n 1 | awk -F'/' '{print $(NF-1)}')
}

# 通过usb总线号和端口号，获取链路名称
# TODO: 这个配置应该放到UCI配置文件中, ncm.sh应该是一个通用的脚本
function get_simindex_by_usb()
{
    local USB=$1
    [ "${USB}" == "2-2:2.3" ] && echo "SIM_5G_1"
    [ "${USB}" == "2-3:2.3" ] && echo "SIM_5G_2"
    [ "${USB}" == "2-1:2.3" ] && echo "SIM_5G_3"
}

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

	logger -t "NCM" "$FUNCNAME Exit proto_ncm_init_config"
}


# NCM协议连接建立函数
proto_ncm_setup() {

	logger -t "NCM" "Enter proto_ncm_setup, interface:$1"

	# 获取接口名称参数
	local interface="$1"
	logger -t "NCM" "interface:${interface}"

	# 声明本地变量用于存储调制解调器相关信息
	local manufacturer initialize setmode connect finalize devname devpath ifpath

	local device ifname  apn auth username password pincode delay mode pdptype profile $PROTO_DEFAULT_OPTIONS
	json_get_vars device ifname apn auth username password pincode delay mode pdptype sourcefilter delegate profile $PROTO_DEFAULT_OPTIONS

	local context_type

	[ "$metric" = "" ] && metric="0"
	# logger -t "NCM" "metric:${metric}"

	[ -n "$profile" ] || profile=1
	# logger -t "NCM" "profile:${profile}"

	# 必须指定 /dev/ttyUSB
	[ -n "$device" ] || {
		# 输出错误信息
		echo "No control device specified"
		logger -t "NCM" "No control device specified"
		# 通知协议错误
		proto_notify_error "$interface" NO_DEVICE
		# 设置接口不可用
		proto_set_available "$interface" 0
		return 1
	}

	# 获取设备的真实路径
	device="$(readlink -f $device)"
	# 检查设备是否存在
	[ -e "$device" ] || {
		echo "Control device not valid"
		logger -t "NCM" "Control device not valid"
		proto_set_available "$interface" 0
		return 1
	}

	logger -t "NCM" "interface:${interface} device:${device}"

	# 接口真实名称,如: eth1 eth2
	[ -z "$ifname" ] && {
		devname="$(basename "$device")"

		# 根据设备名称类型确定网络接口路径
		case "$devname" in
		# ACM类型设备
		'ttyACM'*)
			devpath="$(readlink -f /sys/class/tty/$devname/device)"
			ifpath="$devpath/../*/net"
			;;
		# TTY类型设备
		'tty'*)
			devpath="$(readlink -f /sys/class/tty/$devname/device)"
			ifpath="$devpath/../../*/net"
			;;
		# 其他USB设备
		*)
			devpath="$(readlink -f /sys/class/usbmisc/$devname/device/)"
			ifpath="$devpath/net"
			;;
		esac
		# 获取网络接口名称
		ifname="$(ls $(ls -1 -d $ifpath | head -n 1))"
	}

	# 检查是否成功获取接口名称
	[ -n "$ifname" ] || {
		logger -t "NCM" "The interface could not be found."
		proto_notify_error "$interface" NO_IFACE
		proto_set_available "$interface" 0
		
		sleep 5
		return 1
	}

	logger -t "NCM" "interface:${interface} ifname:${ifname} device:${device}"

    local sysfs_usb=$(find /sys/devices/platform -name $(basename $device) | head -n 1 | awk -F'/' '{print $(NF-1)}')
	logger -t "NCM" "interface:${interface} ifname:${ifname} device:${device} usb:${sysfs_usb}"

	# 开始获取调制解调器制造商信息的循环
	# 记录开始时间
	start=$(date '+%F %T')
	logger -t "NCM" "start dial at ${start}"

	# 获取USB总线和端口号
	local USB=$(get_usb_by_ttyUSB ${device})
	logger -t "NCM" "interface:${interface} ifname:${ifname} device:${device} USB:${USB}"
	# 获取uci配置section
	local uci_section=$(get_simindex_by_usb ${USB})
	logger -t "NCM" "$FUNCNAME uci section:${uci_section}"

	# 拨号配置参数
	. /usr/share/libubox/jshn.sh
	json_init

	# 设置入网方式
	local net=$(uci -q get sim.${uci_section}.net)
	net=$(echo ${net} | tr 'A-Z' 'a-z')
	logger -t "NCM" "uci sim net:${net}"
	local json_rat
	case "${net}" in
		"auto")
			json_add_string rat "sa+nsa"
			;;
		"sa")
			json_add_string rat "sa"
			;;
		"nsa")
			json_add_string rat "nsa"
			;;
		"lte")
			json_add_string rat "lte"
			;;
		*)
			logger -t "NCM" "unknown net:${net}! set auto..."
			json_add_string rat "sa+nsa"

			net=auto
			uci set sim.${uci_section}.net=auto && uci commit sim
			logger -t "NCM" "uci set sim.${uci_section}.net=auto && uci commit sim"
			;;
	esac

	# 设置APN
	local uci_apn=$(uci -q get sim.${uci_section}.apn)
	json_add_string apn "${uci_apn}"

	logger -t "NCM" "uci sim apn:${uci_apn}"
	
	# 设置鉴权
	uci_auth=$(uci -q get sim.${uci_section}.auth)
	uci_username=$(uci -q get sim.${uci_section}.user)
	uci_password=$(uci -q get sim.${uci_section}.passwd)

	uci_auth=$(echo ${uci_auth} | tr 'A-Z' 'a-z')
	logger -t "NCM" "uci sim auth:${uci_auth}"
	logger -t "NCM" "uci sim username:${uci_username}"
	logger -t "NCM" "uci sim password:${uci_password}"

	# local AUTH
	case "${uci_auth}" in
		"none")
			json_add_string auth "none"
			;;
		"pap")
			json_add_string auth "pap"
			;;
		"chap")
			json_add_string auth "chap"
			;;
		"auto")
			json_add_string auth "auto"
			;;
		*)
			json_add_string auth "none"
			;;
	esac

	json_add_string passwd "$uci_password"
	json_add_string username "$uci_username"


	# NR锁PCI小区配置
	uci_nrPciLockEnable="$(uci -q get "sim.${uci_section}.nrPciLock")"
	uci_nrPciLockPcid="$(uci -q get "sim.${uci_section}.nrPciPcid")"
	uci_nrPciLockBand="$(uci -q get "sim.${uci_section}.nrPciBand")"
	uci_nrPciLockFreq="$(uci -q get "sim.${uci_section}.nrPciFreq")"
	uci_nrPciLockScs="$(uci -q get "sim.${uci_section}.nrPciScs")"

	json_add_object nrfreqlock
	if [ "$uci_nrPciLockEnable" = "true" ] && [ -n "$uci_nrPciLockPcid" ] && [ -n "$uci_nrPciLockBand" ] && [ -n "$uci_nrPciLockFreq" ] && [ -n "$uci_nrPciLockScs" ]; then
		# band_num="$(echo "$uci_nrPciLockBand" | sed 's/^[nN]//')"
		json_add_int operatetype 2
		json_add_array band
		json_add_int "" "$uci_nrPciLockBand"
		json_close_array
		json_add_array arfcn
		json_add_int "" "$uci_nrPciLockFreq"
		json_close_array
		json_add_array scstype
		json_add_int "" "$uci_nrPciLockScs"
		json_close_array
		json_add_array pci
		json_add_int "" "$uci_nrPciLockPcid"
		json_close_array
	else
		json_add_int operatetype 0
	fi
	json_close_object

	# LTE锁PCI小区配置
	uci_ltePciLockEnable="$(uci -q get "sim.${uci_section}.ltePciLock")"
	uci_ltePciLockPcid="$(uci -q get "sim.${uci_section}.ltePciPcid")"
	uci_ltePciLockBand="$(uci -q get "sim.${uci_section}.ltePciBand")"
	uci_ltePciLockFreq="$(uci -q get "sim.${uci_section}.ltePciFreq")"

	json_add_object ltefreqlock
	if [ "$uci_ltePciLockEnable" = "true" ] && [ -n "$uci_ltePciLockPcid" ] && [ -n "$uci_ltePciLockBand" ] && [ -n "$uci_ltePciLockFreq" ]; then
		# band_num="$(echo "$uci_ltePciLockBand" | sed 's/^[nN]//')"
		json_add_int operatetype 2
		json_add_array band
		json_add_int "" "$uci_ltePciLockBand"
		json_close_array
		json_add_array arfcn
		json_add_int "" "$uci_ltePciLockFreq"
		json_close_array
		json_add_array pci
		json_add_int "" "$uci_ltePciLockPcid"
		json_close_array
	else
		json_add_int operatetype 0
	fi
	json_close_object

	DIAL_PARAMS="$(json_dump)"
	logger -t "NCM" "dial params: ${DIAL_PARAMS}"

	# 拨号
	dial=$(/usr/share/modemdata/dial.sh ${device} "${DIAL_PARAMS}")
	echo ${dial}

	# 执行dhcp, 最多尝试15秒
	ifconfig $ifname up

	res="$(udhcpc -i "$ifname" -t 5 -T 3 -n -q 2>&1)"
	printf '%s\n' "$res" | while IFS= read -r line; do
	[ -n "$line" ] && logger -t "NCM" "$line"
	done

	ip="$(echo "$res" | awk '/lease of/ {print $4; exit}')"
	mask="$(echo "$res" | awk '/ip addr add/ {split($5,a,"/"); print a[2]; exit}')"
	gw="$(echo "$res" | sed -n 's/.*setting default routers:[[:space:]]*//p' | awk '{print $1; exit}')"
	logger -t "NCM" "${ifname} ip:${ip} mask:${mask} gw:${gw}"
	
	# 设置网络接口
	echo "Setting up $ifname"
	logger -t "NCM" "Setting up $ifname"
	# 初始化接口更新（启用）
	proto_init_update "$ifname" 1
	# 开始添加协议数据
	proto_add_data
	# 添加制造商信息
	json_add_string "manufacturer" "$manufacturer"
	# 结束数据添加
	proto_close_data
	# 发送接口更新
	proto_send_update "$interface"

	# 获取防火墙区域信息
	local zone="$(fw3 -q network "$interface" 2>/dev/null)"

	# 如果PDP类型支持IPv4则创建IPv4接口
	logger -t "NCM" "pdptype=${pdptype}!"
	[ "$pdptype" = "IP" -o "$pdptype" = "IPV4V6" ] && {

		# 初始化JSON
		json_init
		# 添加IPv4接口名称
		json_add_string name "${interface}_4"
		# 添加接口引用
		json_add_string ifname "@$interface"
		# 设置协议为DHCP
		json_add_string proto "dhcp"
		# 添加动态默认配置
		proto_add_dynamic_defaults
		# 如果有防火墙区域，则添加防火墙区域配置
		[ -n "$zone" ] && {
			json_add_string zone "$zone"
		}
		# 关闭JSON对象
		json_close_object
		# 通过ubus添加动态网络接口
		ubus call network add_dynamic "$(json_dump)"
	}

	# 如果PDP类型支持IPv6则创建IPv6接口
	[ "$pdptype" = "IPV6" -o "$pdptype" = "IPV4V6" ] && {
		# 初始化JSON
		json_init
		# 添加IPv6接口名称
		json_add_string name "${interface}_6"
		# 添加接口引用
		json_add_string ifname "@$interface"
		# 设置协议为DHCPv6
		json_add_string proto "dhcpv6"
		# 启用前缀扩展
		json_add_string extendprefix 1
		# 如果禁用委托则设置
		[ "$delegate" = "0" ] && json_add_boolean delegate "0"
		# 如果禁用源过滤则设置
		[ "$sourcefilter" = "0" ] && json_add_boolean sourcefilter "0"
		# 添加动态默认配置
		proto_add_dynamic_defaults
		# 如果有防火墙区域
		[ -n "$zone" ] && {
			json_add_string zone "$zone"
		}
		# 关闭JSON对象
		json_close_object
		# 通过ubus添加动态网络接口
		ubus call network add_dynamic "$(json_dump)"
	}

	logger -t "NCM" "$FUNCNAME Exit proto_ncm_setup, interface:$1"
	sleep 5
}

# NCM协议连接断开函数
proto_ncm_teardown() {


	local interface="$1"
	logger -t "NCM" "$FUNCNAME Enter teardown, interface:$1"
	
	sleep 1

	# 更新接口状态为关闭
	# 初始化接口更新（禁用所有）
	proto_init_update "*" 0
	# 发送接口更新
	proto_send_update "$interface"

	logger -t "NCM" "$FUNCNAME Exit teardown, interface:$1"
}

# 如果不是仅包含模式则注册NCM协议
[ -n "$INCLUDE_ONLY" ] || {
	logger -t "NCM" "add protocol ncm"
	add_protocol ncm
}
