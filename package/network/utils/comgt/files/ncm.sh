#!/bin/sh

# NCM协议处理脚本，用于OpenWrt系统中管理NCM调制解调器连接



# 通过usb总线号和端口号，获取/dev/ttyUSBx
function get_usb_by_ttyUSB()
{
    # /dev/ttyUSB2 => ttyUSB2
    local ttyUSB=$(basename $1)
    local USB=$(find /sys/devices/platform -name ${ttyUSB} | head -n 1 | awk -F'/' '{print $(NF-1)}')
    echo ${USB}
}
# 通过usb总线号和端口号，获取链路名称
function get_simindex_by_usb()
{
    local USB=$1
    [ "${USB}" == "2-1:1.4" ] && echo "SIM_5G_1" && return
    [ "${USB}" == "2-2:1.4" ] && echo "SIM_5G_2" && return
    [ "${USB}" == "2-3:1.4" ] && echo "SIM_5G_3" && return
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
	
	logger -t "NCM" "$FUNCNAME"

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
}


# NCM协议连接建立函数
proto_ncm_setup() {

	# 获取接口名称参数
	local interface="$1"
	logger -t "NCM" "$FUNCNAME interface:${interface}"

	# 声明本地变量用于存储调制解调器相关信息
	local manufacturer initialize setmode connect finalize devname devpath ifpath

	local device ifname  apn auth username password pincode delay mode pdptype profile $PROTO_DEFAULT_OPTIONS
	json_get_vars device ifname apn auth username password pincode delay mode pdptype sourcefilter delegate profile $PROTO_DEFAULT_OPTIONS

	# 删除串行设备锁文件
	LOCK_FILE=/var/lock/LCK..$(basename ${device})
	logger -t "NCM" "$FUNCNAME Lock_file:${LOCK_FILE}"
	[ -f ${LOCK_FILE} ] && {
		rm -rf ${LOCK_FILE}
		logger -t "NCM" "$FUNCNAME rm ${LOCK_FILE}"
	}

	local context_type

	[ "$metric" = "" ] && metric="0"
	logger -t "NCM" "$FUNCNAME metric:${metric}"

	[ -n "$profile" ] || profile=1
	logger -t "NCM" "$FUNCNAME profile:${profile}"

	# 将PDP类型转换为大写
	pdptype=$(echo "$pdptype" | awk '{print toupper($0)}')
	# 验证PDP类型，如果不是有效值则默认为IP
	[ "$pdptype" = "IP" -o "$pdptype" = "IPV6" -o "$pdptype" = "IPV4V6" ] || pdptype="IP"

	# 根据PDP类型设置上下文类型
	# 双栈模式
	[ "$pdptype" = "IPV4V6" ] && context_type=3
	# IPv6模式
	[ -z "$context_type" -a "$pdptype" = "IPV6" ] && context_type=2
	# IPv4模式（默认）
	[ -n "$context_type" ] || context_type=1

	# 如果设置了控制设备则使用它
	[ -n "$ctl_device" ] && device=$ctl_device

	logger -t "NCM" "$FUNCNAME pdptype:${pdptype} context_type:${context_type} ctl_device:${ctl_device} device:${device}"

	# 检查设备是否已指定
	[ -n "$device" ] || {
		# 输出错误信息
		echo "No control device specified"
		logger -t "NCM" "$FUNCNAME No control device specified"
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
		logger -t "NCM" "$FUNCNAME Control device not valid"
		proto_set_available "$interface" 0
		return 1
	}

	logger -t "NCM" "$FUNCNAME device:${device}"

	# 如果接口名称未指定，则自动检测
	[ -z "$ifname" ] && {
		# 获取设备基本名称
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
		echo "The interface could not be found."
		logger -t "NCM" "$FUNCNAME The interface could not be found."
		proto_notify_error "$interface" NO_IFACE
		proto_set_available "$interface" 0
		return 1
	}

	logger -t "NCM" "$FUNCNAME ifname:${ifname}"

	# 开始获取调制解调器制造商信息的循环
	# 记录开始时间
	start=$(date +%s)
	logger -t "NCM" "$FUNCNAME start:${start} device:${device}"
	while true; do
		manufacturer=$(rm -rf ${LOCK_FILE};echo -e 'AT+CGMI\r' | microcom "$device" -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		if echo ${manufacturer} | grep -q 'OK'; then
			manufacturer=$(echo ${manufacturer} | cut -d ' ' -f 1 | tr 'A-Z' 'a-z' | tr -d '\r\n')
		else
			manufacturer=error
		fi

		# 如果返回错误则清空制造商信息
		[ "$manufacturer" = "error" ] && {
			manufacturer=""
		}

		# 如果成功获取制造商信息则退出循环
		[ -n "$manufacturer" ] && {
			break
		}

		# 如果未设置延迟则立即退出循环
		[ -z "$delay" ] && {
			break
		}
		sleep 1
		elapsed=$(($(date +%s) - start))
		# 如果超过延迟时间则退出循环
		[ "$elapsed" -gt "$delay" ] && {
			break
		}
	done

	logger -t "NCM" "manufacturer:[${manufacturer}]"

	# 如果未能获取制造商信息则报错退出
	[ -z "$manufacturer" ] && {
		echo "Failed to get modem information"
		logger -t "NCM" "$FUNCNAME Failed to get modem information"
		proto_notify_error "$interface" GETINFO_FAILED
		return 1
	}

	# 加载NCM配置JSON文件
	json_load "$(cat /etc/gcom/ncm.json)"
	# 选择对应制造商的配置
	# json_select "$manufacturer"
	# # 如果找不到对应制造商配置则报错
	# [ $? -ne 0 ] && {
	# 	echo "Unsupported modem"
	# 	logger -t "NCM" "$FUNCNAME Unsupported modem"
	# 	proto_notify_error "$interface" UNSUPPORTED_MODEM
	# 	proto_set_available "$interface" 0
	# 	return 1
	# }

	# 获取USB总线和端口号
	local USB=$(get_usb_by_ttyUSB ${device})
	logger -t "NCM" "$FUNCNAME ${USB}"
	# 获取uci配置section
	local uci_section=$(get_simindex_by_usb ${USB})
	logger -t "NCM" "$FUNCNAME uci section:${uci_section}"

	# UCI配置文件待确认
	uci set sim.${uci_section}.confirmed=0 && uci commit sim
	logger -t "NCM" "uci set sim.${uci_section}.confirmed=1 && uci commit sim"

	# 清除UCI配置文件中的sim IMSI
	uci set sim.${uci_section}.imsi=none && uci commit sim
	logger -t "NCM" "uci set sim.${uci_section}.imsi=${imsi} && uci commit sim"

	# 保存USB总线和端口号到UCI配置文件
	OLD_USB=$(uci get sim.${uci_section}.usb)
	if [ "${OLD_USB}" != "${USB}" ]; then
		uci set sim.${uci_section}.usb=${USB} && uci commit sim
		logger -t "NCM" "$FUNCNAME uci set sim.${uci_section}.usb=${USB} && uci commit sim"
	fi

	# 获取模组名称
	local module old_module
	uci set sim.${uci_section}.module='' && uci commit sim
	for i in 1 2 3; do
		module=$(rm -rf ${LOCK_FILE};echo -e 'AT+CGMM\r' | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		# logger -t "NCM" "module:[${module}]"
		if echo ${module} | grep -q "OK"; then
			module=$(echo ${module} | cut -d ' ' -f 1 | tr -d '\r\n')
		else
			module=
		fi

		logger -t "NCM" "module:[${module}]"
		if [ ! -z "${module}" ]; then
			old_module=$(uci get sim.${uci_section}.module)
			[ "${old_module}" != "${module}" ] && { 
				uci set sim.${uci_section}.module=${module} && uci commit sim
				logger -t "NCM" "old_module:[${old_module}] | module:[${module}]"
				logger -t "NCM" "uci set sim.${uci_section}.module=${module} && uci commit sim"
			}

			break
		fi
	done

	logger -t "NCM" "module:[${module}]"

	# 设置工作模式为NCM
	for i in $(seq 1 3); do
		mode=$(rm -rf ${LOCK_FILE};echo -e 'AT+QCFG="usbnet"\r' | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		mode=$(echo ${mode} | grep -o '+QCFG:.*' | sed 's/.*,\([0-9]\).*/\1/' | tr -d '\n')
		[ "$mode" != "5" ] && {
			mode=5
			ret=$(rm -rf ${LOCK_FILE};echo -e "AT+QCFG=\"usbnet\",${mode}\r" | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
			if echo "${ret}" | grep -q "OK"; then
				logger -t "NCM" "set mode ${mode} ncm succeed!"
				break
			else
				logger -t "NCM" "set mode ${mode} ncm failed!"
			fi
		}
	done

	logger -t "NCM" "mode:[${mode}]"

	# 获取模组版本号
	local version old_version
	uci set sim.${uci_section}.moduleVersion='' && uci commit sim
	for i in 1 2 3; do
		version=$(rm -rf ${LOCK_FILE};echo -e 'ATI\r' | microcom "$device" -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		version=$(echo ${version} | grep -o "Revision:."* | cut -d ' ' -f 2 | tr -d '\r\n')
		[ ! -z ${version} ] && {
			
			# 保存到uci配置文件
			old_version=$(uci get sim.${uci_section}.moduleVersion)
			[ "${old_version}" != "${version}" ] && {
				uci set sim.${uci_section}.moduleVersion=${version} && uci commit sim
				logger -t "NCM" "old_version:[${old_version}] | version:[${version}]"
				logger -t "NCM" "uci set sim.${uci_section}.moduleVersion=${version} && uci commit sim"
			}

			break
		}

	done

	logger -t "NCM" "version:[${version}]"

	# 获取模组IMEI码
	local imei old_imei
	uci set sim.${uci_section}.imei='' && uci commit sim
	for i in 1 2 3; do
		imei=$(rm -rf ${LOCK_FILE};echo -e 'AT+CGSN\r' | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		imei=$(echo ${imei} | tr -cd '0-9')
		[ ! -z ${imei} ] && {
			# 保存到uci配置文件
			old_imei=$(uci get sim.${uci_section}.imei)
			[ "${old_imei}" != "${imei}" ] && {
				uci set sim.${uci_section}.imei=${imei} && uci commit sim
				logger -t "NCM" "old_imei:[${old_imei}] | imei:[${imei}]"
				logger -t "NCM" "uci set sim.${uci_section}.imei=${imei} && uci commit sim"
			}

			break
		}
	done

	logger -t "NCM" "imei:[${imei}]"

	# 查询是否插卡
	local simin
	for i in $(seq 1 3); do
		# echo -e 'AT+CPIN?\r' | microcom /dev/ttyUSB2 -t 100
		simin=$(rm -rf ${LOCK_FILE};echo -e 'AT+CPIN?\r' | microcom "$device" -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		logger -t "NCM" "${simin}"
		if echo "${simin}" | grep -q "READY"; then
			break
		fi		
	done

	if echo "${simin}" | grep -q "READY"; then
		logger -t "NCM" "sim ready"
	else
		logger -t "NCM" "sim not ready! return now..." && return 1
	fi	

	# 查询IMSI
	local imsi old_imsi
	uci set sim.${uci_section}.imsi='' && uci commit sim
	for i in $(seq 1 3); do
		imsi=$(rm -rf ${LOCK_FILE};echo -e 'AT+CIMI\r' | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		imsi=$(echo ${imsi} | tr -cd '0-9')
		[ ! -z ${imsi} ] && {
			uci set sim.${uci_section}.imsi=${imsi} && uci commit sim
			logger -t "NCM" "uci set sim.${uci_section}.imsi=${imsi} && uci commit sim"
			break
		}
	done

	logger -t "NCM" "imsi:[${imsi}]"

	# 查询运营商
	local operator old_operator
	uci set sim.${uci_section}.operator='' && uci commit sim
	for i in $(seq 1 3); do
		operator=$(rm -rf ${LOCK_FILE};echo -e 'AT+QNWINFO\r' | microcom $device -t 100 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		operator=$(echo ${operator} | sed -n 's/.*+QNWINFO: "[^"]*",\([0-9]*\).*/\1/p')
		logger -t "NCM" "operator:${operator}"
		[ ! -z ${operator} ] && {
			# 保存到uci配置文件
			old_operator=$(uci get sim.${uci_section}.operator)
			[ "${old_operator}" != ${operator} ] && {
				uci set sim.${uci_section}.operator=${operator} && uci commit sim
				logger -t "NCM" "old_operator:[${old_operator}] | operator:[${operator}]"
				logger -t "NCM" "uci set sim.${uci_section}.operator=${operator} && uci commit sim"
			}

			break
		}

	done

	logger -t "NCM" "operator:[${operator}]"

	# 设置入网方式
	local net=$(uci get sim.${uci_section}.net)
	net=$(echo ${net} | tr 'A-Z' 'a-z')
	logger -t "NCM" "uci sim net:${net}"
	local NET=AUTO
	case "${net}" in
		"auto")
			NET=AUTO
			;;
		"sa")
			NET=NR5G-SA
			;;
		"nsa")
			NET=NR5G-NSA
			;;
		"lte")
			NET=LTE
			;;
		*)
			logger -t "NCM" "unknown net:${net}! set auto..."
			net=auto
			uci set sim.${uci_section}.net=auto && uci commit sim
			logger -t "NCM" "uci set sim.${uci_section}.net=auto && uci commit sim"
			NET=AUTO
			;;
	esac

	for i in $(seq 1 3); do
		# NET=AUTO comgt -d /dev/ttyUSB2 -s /etc/gcom/setnet.gcom
		# NET=NR5G-SA comgt -d /dev/ttyUSB2 -s /etc/gcom/setnet.gcom
		# NET=NR5G-NSA comgt -d /dev/ttyUSB2 -s /etc/gcom/setnet.gcom
		# NET=LTE comgt -d /dev/ttyUSB2 -s /etc/gcom/setnet.gcom
		ret=$(rm -rf ${LOCK_FILE};echo -e "AT+QNWPREFCFG=\"mode_pref\",${NET}\r" | microcom $device -t 3000 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		if echo "${ret}" | grep -q "OK"; then
			logger -t "NCM" "set net ${net} succeed!"
			break
		else
			logger -t "NCM" "set net ${net} failed!"
		fi
	done

	# 设置APN
	apn=$(uci get sim.${uci_section}.apn)
	logger -t "NCM" "uci sim apn:${apn}"
	for i in $(seq 1 3); do
		# APN=3gnet comgt -d /dev/ttyUSB2 -s /etc/gcom/setapn.gcom
		ret=$(rm -rf ${LOCK_FILE};echo -e "AT+CGDCONT=1,\"IP\",\"${apn}\"\r" | microcom $device -t 300 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		if echo "${ret}" | grep -q "OK"; then
			logger -t "NCM" "set apn ${apn} succeed!"
			break
		else
			logger -t "NCM" "set apn ${apn} failed!"
		fi
	done

	# 设置鉴权
	auth=$(uci get sim.${uci_section}.auth)
	username=$(uci get sim.${uci_section}.user)
	password=$(uci get sim.${uci_section}.passwd)
	auth=$(echo ${auth} | tr 'A-Z' 'a-z')
	logger -t "NCM" "uci sim auth:${auth}"
	logger -t "NCM" "uci sim username:${username}"
	logger -t "NCM" "uci sim password:${password}"

	local AUTH
	case "${auth}" in
		"none")
			AUTH=0
			;;
		"pap")
			AUTH=1
			;;
		"chap")
			AUTH=2
			;;
		"auto")
			AUTH=3
			;;
		*)
			AUTH=0
			;;
	esac

	for i in $(seq 1 3); do
		# APN=3gnet USER=user PASSWD=passwd AUTH=0 comgt -d /dev/ttyUSB2 -s /etc/gcom/setauth.gcom
		ret=$(rm -rf ${LOCK_FILE};echo -e "AT+QICSGP=1,1,\"${apn}\",\"${username}\",\"${password}\",${AUTH}\r" | microcom $device -t 2000 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		if echo "${ret}" | grep -q "OK"; then
			logger -t "NCM" "set auth apn:${apn} auth:${auth} user:${username} passwd:${password} succeed!"
			break
		else
			logger -t "NCM" "set auth apn:${apn} auth:${auth} user:${username} passwd:${password} failed!"
		fi
	done

	# 拨号
	for i in $(seq 1 3); do
		# comgt -d /dev/ttyUSB2 -s /etc/gcom/dial.gcom
		ret=$(rm -rf ${LOCK_FILE};echo -e "AT+QNETDEVCTL=1,1,0\r" | microcom $device -t 1000 | tr '\r' ' ' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/ $//' | sed 's/^ //')
		if echo "${ret}" | grep -q "OK"; then
			logger -t "NCM" "dial succeed!"
			break
		else
			logger -t "NCM" "dial failed!"
		fi
	done

	# 拨号指令执行失败
	if echo "${ret}" | grep -q "OK"; then
		logger -t "NCM" "dial succeed!"
	else
		proto_notify_error "$interface" CONNECT_FAILED
		return 1
	fi

	# uci配置文件确认成功
	uci set sim.${uci_section}.confirmed=1 && uci commit sim
	logger -t "NCM" "uci set sim.${uci_section}.confirmed=1 && uci commit sim"

	# 设置网络接口
	echo "Setting up $ifname"
	logger -t "NCM" "$FUNCNAME Setting up $ifname"
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

	# 如果有最终化命令则执行
	# [ -n "$finalize" ] && {
	# 	eval COMMAND="$finalize" gcom -d "$device" -s /etc/gcom/runcommand.gcom || {
	# 		echo "Failed to configure modem"
	# 		logger -t "NCM" "$FUNCNAME Failed to configure modem"
	# 		proto_notify_error "$interface" FINALIZE_FAILED
	# 		return 1
	# 	}
	# }
}

# NCM协议连接断开函数
proto_ncm_teardown() {
	local interface="$1"

	# 声明制造商和断开命令变量
	local manufacturer disconnect

	# 声明设备和配置文件变量
	local device profile
	# 获取设备和配置文件变量
	json_get_vars device profile

	# 如果设置了控制设备则使用它
	[ -n "$ctl_device" ] && device=$ctl_device

	# 检查设备是否已指定
	[ -n "$device" ] || {
		echo "No control device specified"
		logger -t "NCM" "$FUNCNAME No control device specified"
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
		logger -t "NCM" "$FUNCNAME Control device not valid"
		proto_set_available "$interface" 0
		return 1
	}

	# 如果profile未设置则默认为1
	[ -n "$profile" ] || profile=1

	echo "Stopping network $interface"

	# 尝试从接口状态中获取制造商信息
	json_load "$(ubus call network.interface.$interface status)"
	# 选择数据节点
	json_select data
	# 获取制造商信息
	json_get_vars manufacturer
	# 获取失败或为空
	[ $? -ne 0 -o -z "$manufacturer" ] && {
		# Fallback to direct detect, for proper handle device replug.
		# 回退到直接检测，用于正确处理设备重新插拔
		manufacturer=$(gcom -d "$device" -s /etc/gcom/getcardinfo.gcom | awk 'NF && $0 !~ /AT\+CGMI/ { sub(/\+CGMI: /,""); print tolower($1); exit; }')
		[ $? -ne 0 -o -z "$manufacturer" ] && {
			echo "Failed to get modem information"
			logger -t "NCM" "$FUNCNAME Failed to get modem information"
			proto_notify_error "$interface" GETINFO_FAILED
			return 1
		}
		# 添加制造商信息到JSON
		json_add_string "manufacturer" "$manufacturer"
	}

	# 加载NCM配置JSON文件并选择制造商配置
	json_load "$(cat /etc/gcom/ncm.json)"
	json_select "$manufacturer" || {
		echo "Unsupported modem"
		logger -t "NCM" "$FUNCNAME Unsupported modem"
		proto_notify_error "$interface" UNSUPPORTED_MODEM
		return 1
	}

	# 获取断开连接命令并执行
	json_get_vars disconnect
	[ -n "$disconnect" ] && {
		# 执行断开命令
		eval COMMAND="$disconnect" gcom -d "$device" -s /etc/gcom/runcommand.gcom || {
			echo "Failed to disconnect"
			logger -t "NCM" "$FUNCNAME Failed to disconnect"
			proto_notify_error "$interface" DISCONNECT_FAILED
			return 1
		}
	}

	# 更新接口状态为关闭
	# 初始化接口更新（禁用所有）
	proto_init_update "*" 0
	# 发送接口更新
	proto_send_update "$interface"
}

# 如果不是仅包含模式则注册NCM协议
[ -n "$INCLUDE_ONLY" ] || {
	logger -t "NCM" "add protocol ncm"
	add_protocol ncm
}