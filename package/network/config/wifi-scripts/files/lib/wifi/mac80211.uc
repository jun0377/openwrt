#!/usr/bin/env ucode

// 导入读文件模块
import { readfile } from "fs";
// 导入uci模块
import * as uci from 'uci';

// 无线频段,按优先级从高到低
const bands_order = [ "6G", "5G", "2G" ];
// 高通道模式,按优先级从高到低
const htmode_order = [ "EHT", "HE", "VHT", "HT" ];

// 读取并解析 /etc/board.json 文件，获取当前设备的硬件信息
let board = json(readfile("/etc/board.json"));
// 没有 wlan（无线）配置, 退出
if (!board.wlan)
	exit(0);

// 初始化无线电设备的索引，用于创建唯一的设备名称
let idx = 0;
// 用于标记是否需要提交更改的变量
let commit;

// 获取当前无线配置的所有项，并存储在 config 对象中, 若没有则初始化为空对象
let config = uci.cursor().get_all("wireless") ?? {};

// 检查给定的无线电设备是否已存在于配置中
function radio_exists(path, macaddr, phy, radio) {

	// 遍历当前的无线配置项
	for (let name, s in config) {

		// 如果项的类型不是 wifi-device，则跳过
		if (s[".type"] != "wifi-device")
			continue;

		// 如果传入的 radio 存在且与当前项的 radio 不匹配，则跳过
		if (radio != null && int(s.radio) != radio)
			continue;

		// 检查当前项的 macaddr 是否与传入的 macaddr 匹配（不区分大小写），若匹配则返回 true
		if (s.macaddr & lc(s.macaddr) == lc(macaddr))
			return true;

		// 检查当前项的 phy 是否与传入的 phy 匹配，若匹配则返回 true
		if (s.phy == phy)
			return true;

		// 如果当前项或传入的 path 为空，则跳过
		if (!s.path || !path)
			continue;

		// 检查当前项的 path 是否以传入的 path 结束，若是则返回 true
		if (substr(s.path, -length(path)) == path)
			return true;
	}
}

// 遍历 board.wlan 中的所有物理无线设备
for (let phy_name, phy in board.wlan) {

	// 获取当前物理无线设备的信息
	let info = phy.info;
	// 如果信息为空或没有频段，则跳过此设备
	if (!info || !length(info.bands))
		continue;

	// 检查当前无线设备是否有多个无线电，如果没有则创建一个包含其频段的对象
	let radios = length(info.radios) > 0 ? info.radios : [{ bands: info.bands }];
	// 遍历当前无线电设备的信息
	for (let radio in radios) {
		// 确保当前 radio 的名称唯一，通过递增 idx
		while (config[`radio${idx}`])
			idx++;
		// 生成无线电设备的名称
		let name = "radio" + idx;

		// 定义无线设备在 UCI 中的配置路径
		let s = "wireless." + name;
		// 定义默认接口的配置路径
		let si = "wireless.default_" + name;

		// 过滤当前无线电设备支持的频段，获取优先级最高的频段名称
		let band_name = filter(bands_order, (b) => radio.bands[b])[0];
		// 如果没有有效的频段名称，则跳过此无线电设备
		if (!band_name)
			continue;

		// 获取当前频段的详细信息
		let band = info.bands[band_name];
		// 获取当前无线电设备对应频段的具体设置
		let rband = radio.bands[band_name];
		// 设定频道，如果无默认频道则使用 "auto"
		let channel = rband.default_channel ?? "auto";

		// 获取当前频段的最大带宽
		let width = band.max_width;
		// 如果是 2G 频段，带宽设为 20MHz
		if (band_name == "2G")
			width = 20;
		// 如果最大带宽大于 80MHz，则设为 80MHz
		else if (width > 80)
			width = 80;

		// 获取当前频段支持的最高通道模式，按优先级排列
		let htmode = filter(htmode_order, (m) => band[lc(m)])[0];
		// 如果找到了合适的 htmode，则将带宽附加到模式上
		if (htmode)
			htmode += width;
		// 如果没有找到合适的 htmode，则设为 "NOHT"
		else
			htmode = "NOHT";

		// 如果物理设备路径为空，则跳过
		if (!phy.path)
			continue;

		// 读取物理设备的 MAC 地址，并移除空格
		let macaddr = trim(readfile(`/sys/class/ieee80211/${phy_name}/macaddress`));
		// 检查该无线电设备是否已存在，若存在则跳过
		if (radio_exists(phy.path, macaddr, phy_name, radio.index))
			continue;

		// 初始化 id 变量用于后续的配置设置
		let id = `phy='${phy_name}'`;
		// 如果 phy_name 符合模式，则使用设备路径作为 ID
		if (match(phy_name, /^phy[0-9]/))
			id = `path='${phy.path}'`;

		// 将频段名称转换为小写
		band_name = lc(band_name);

		// 初始化变量用于存储国家、默认设置和全局 MAC 地址数量
		let country, defaults, num_global_macaddr;
		// 检查是否有默认设置
		if (board.wlan.defaults) {
			// 从默认设置中获取当前频段的 SSID 信息
			defaults = board.wlan.defaults.ssids?.[band_name]?.ssid ? board.wlan.defaults.ssids?.[band_name] : board.wlan.defaults.ssids?.all;
			// 获取国家代码
			country = board.wlan.defaults.country;
			// 如果没有国家代码且不是 2G 频段，则将默认设置设为 null
			if (!country && band_name != '2g')
				defaults = null;
			// 获取当前频段的全局 MAC 地址数量
			num_global_macaddr = board.wlan.defaults.ssids?.[band_name]?.mac_count;
		}

		// 如果当前无线电设备有多个无线电，则将其对应的 radio 索引设置到配置
		if (length(info.radios) > 0)
			id += `\nset ${s}.radio='${radio.index}'`;

		// 输出无线设备和接口的配置到标准输出，供后续处理
		print(`set ${s}=wifi-device
set ${s}.type='mac80211'
set ${s}.${id}
set ${s}.band='${band_name}'
set ${s}.channel='${channel}'
set ${s}.htmode='${htmode}'
set ${s}.country='${country || ''}'
set ${s}.num_global_macaddr='${num_global_macaddr || ''}'
set ${s}.disabled='${defaults ? 0 : 1}'

set ${si}=wifi-iface
set ${si}.device='${name}'
set ${si}.network='lan'
set ${si}.mode='ap'
set ${si}.ssid='${defaults?.ssid || "OpenWrt"}'
set ${si}.encryption='${defaults?.encryption || "none"}'
set ${si}.key='${defaults?.key || ""}'

`);
		// 在 config 对象中添加当前无线电设备的空配置
		config[name] = {};
		// 标记需要提交更改
		commit = true;
	}
}

// 如果有更改，则打印提交命令以更新无线配置
if (commit)
	print("commit wireless\n");
