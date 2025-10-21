#!/usr/bin/env ucode

// 通过 nl80211 内核接口扫描系统中的无线物理设备（wiphy/phy）与其射频前端（radio）。
// 解析各频段能力（2G/5G/6G/60G）、支持的模式与最大带宽，计算默认信道。
// 将探测到的能力结构化写入 board.json 的 wlan 节点，用作后续无线配置生成的依据。
// 仅在内容变化时原子更新 board.json ，保持幂等与一致性



// 开启严格模式，避免不安全或隐式行为
'use strict';
// 从 fs 模块导入文件读写、路径解析、通配符、重命名等函数
import { readfile, writefile, realpath, glob, basename, unlink, open, rename } from "fs";
// 从公共工具中导入对象深比较函数 is_equal
import { is_equal } from "/usr/share/hostap/common.uc";
// 通过 nl80211 模块与内核无线子系统交互
let nl = require("nl80211");

// 板级信息文件路径
let board_file = "/etc/board.json";
// 读取当前 board.json 的内容并解析成对象（作为旧数据）
let prev_board_data = json(readfile(board_file));
// 再次读取 board.json（作为工作副本，将被更新）
let board_data = json(readfile(board_file));

// 根据 phy 名称读取其 index（同一设备多 phy 时用于排序）
function phy_idx(name) {
	// 读取索引文件内容并转为数字
	return +rtrim(readfile(`/sys/class/ieee80211/${name}/index`));
}

// 计算某个 phy 对应的设备路径（用于唯一标识设备）
function phy_path(name) {
	// 解析符号链接，拿到真实设备路径
	let devpath = realpath(`/sys/class/ieee80211/${name}/device`);

	// 去掉前缀 /sys/devices/，规范化路径表达
	devpath = replace(devpath, /^\/sys\/devices\//, "");
	// 如果设备路径属于 platform 下的 pci 子层级, 去掉多余的 platform/ 前缀
	if (match(devpath, /^platform\/.*\/pci/))
		devpath = replace(devpath, /^platform\//, "");

	// 找到同一设备下的所有 ieee80211 物理接口（phy），并取其基本名
	let dev_phys = map(glob(`/sys/class/ieee80211/${name}/device/ieee80211/*`), basename);
	// 按各 phy 的 index 进行排序，确保稳定顺序
	sort(dev_phys, (a, b) => phy_idx(a) - phy_idx(b));

	// 查找当前 phy 在列表中的下标位置
	let ofs = index(dev_phys, name);
	// 如果不是第一个，则在路径后加偏移量 +ofs
	if (ofs > 0)
		devpath += `+${ofs}`;

	// 返回规范化后的设备路径（可能含 +偏移）
	return devpath;
}

// 清理 board_data.wlan 中旧的探测信息，避免脏数据
function cleanup() {
	// 取出 wlan 节点
	let wlan = board_data.wlan;

	// 遍历所有 wlan 条目
	for (let name in wlan)
		// 如果键是以 phy 开头（旧格式），整条删除
		if (substr(name, 0, 3) == "phy")
			delete wlan[name];
		// 否则只删除 info 字段（保留其他静态信息，如 path）
		else
			delete wlan[name].info;
}

// 根据 phy 名与设备路径获取/创建 wlan 条目
function wiphy_get_entry(phy, path) {

	// 若 wlan 节点不存在，初始化为空对象
	board_data.wlan ??= {};

	// 引用 wlan 对象
	let wlan = board_data.wlan;
	// 遍历已存在条目,如果路径匹配，说明是同一设备，返回该条目
	for (let name in wlan)
		if (wlan[name].path == path)
			return wlan[name];

	// 如果没找到匹配项，以 phy 名作为键创建新条目
	wlan[phy] = {
		// 记录设备路径，用于后续匹配与持久化
		path: path
	};

	// 返回创建好的条目对象
	return wlan[phy];
}

// 将频率（MHz）转换为信道号（2G/5G/6G/60G）
// 返回 0 表示无法映射为有效信道
function freq_to_channel(freq) {
	if (freq < 1000)
		return 0;
	if (freq == 2484)
		return 14;
	if (freq == 5935)
		return 2;
	if (freq < 2484)
		return (freq - 2407) / 5;
	if (freq >= 4910 && freq <= 4980)
		return (freq - 4000) / 5;
	if (freq < 5950)
		return (freq - 5000) / 5;
	if (freq <= 45000)
		return (freq - 5950) / 5;
	if (freq >= 58320 && freq <= 70200)
		return (freq - 56160) / 2160;
	return 0;
}

// 判断某频率是否落在给定的频段范围集合中
function freq_range_match(ranges, freq) {
	// nl80211 报告的范围单位为 kHz，这里将 MHz 转 kHz
	freq *= 1000;

	for (let range in ranges) {
		if (freq >= range[0] && freq <= range[1])
			return true;
	}
	return false;
}

// 核心：从 nl80211 读取所有 wiphy 能力并整理到 board_data
function wiphy_detect() {

	// 请求内核返回所有无线物理设备（wiphy）信息，启用 dump 以获取列表
	let phys = nl.request(nl.const.NL80211_CMD_GET_WIPHY, nl.const.NLM_F_DUMP, { split_wiphy_dump: true });
	// 若无返回则直接结束探测
	if (!phys)
		return;

	// 遍历每个 wiphy 条目
	for (let phy in phys) {
		if (!phy)
			continue;

		// phy 名称（如 phy0）
		let name = phy.wiphy_name;
		// 计算设备路径（用于唯一标识）
		let path = phy_path(name);
		// 为该 phy 构造能力信息对象
		let info = {
			// 可用接收天线位掩码/数量
			antenna_rx: phy.wiphy_antenna_avail_rx,
			// 可用发送天线位掩码/数量
			antenna_tx: phy.wiphy_antenna_avail_tx,
			// 各频段（2G/5G/6G/60G）的能力信息
			bands: {},
			// 同一设备下的多射频前端（radio）索引与频率范围
			radios: []
		};

		// 遍历该 wiphy 下的所有 radio（物理射频前端）
		for (let radio in phy.radios) {
			// S1G is not supported yet; S1G 尚未支持，过滤掉过低的频率范围
			// 只保留上限大于 2 GHz 的范围
			radio.freq_ranges = filter(radio.freq_ranges,
				(range) => range.end > 2000000
			);

			// 如果过滤后没有范围，跳过该 radio
			if (!length(radio.freq_ranges))
				continue;

			// 记录 radio 的索引、频率范围（kHz，start/end）与其支持的 bands
			push(info.radios, {
				// radio 索引编号
				index: radio.index,
				// 将范围对象映射为二元数组，便于后续处理
				freq_ranges: map(radio.freq_ranges,
					(range) => [ range.start, range.end ]
				),
				// 将在后续根据 band 进行填充
				bands: {}
			});
		}

		// 快捷引用（便于填充每个频段的信息）
		let bands = info.bands;
		// 遍历内核报告的各频段能力
		for (let band in phy.wiphy_bands) {
			// 没有频点数组则跳过
			if (!band || !band.freqs)
				continue;
			// 取第一个频点的频率用于判定频段类型
			let freq = band.freqs[0].freq;
			// 准备存放该频段能力信息的对象
			let band_info = {};
			// 频段名称（2G/5G/6G/60G）
			let band_name;
			// 大于 50,000 MHz（50 GHz）视作 60G
			if (freq > 50000)
				band_name = "60G";
			// 大于 5900 MHz 视作 6G
			else if (freq > 5900)
				band_name = "6G";
			// 大于 4000 MHz 视作 5G
			else if (freq > 4000)
				band_name = "5G";
			// 大于 2000 MHz 视作 2G
			else if (freq > 2000)
				band_name = "2G";
			else
				continue;
			
			// 将 band_info 注册到 info.bands 下
			bands[band_name] = band_info;

			// 存在 HT 能力（802.11n）
			if (band.ht_capa > 0)
				band_info.ht = true;

			// 存在 VHT 能力（802.11ac）
			if (band.vht_capa > 0)
				band_info.vht = true;

			// HE 物理能力位（802.11ax）
			let he_phy_cap = 0;
			// EHT 物理能力位（802.11be）
			let eht_phy_cap = 0;

			// 遍历按接口类型区分的能力数据（AP/STA 等）
			for (let ift in band.iftype_data) {
				// 如果该接口类型没有 HE 能力位，跳过
				if (!ift.he_cap_phy)
					continue;

				// 标记该频段具备 HE 能力
				band_info.he = true;
				// 聚合各接口类型的 HE 物理能力位
				he_phy_cap |= ift.he_cap_phy[0];

				// 如果该接口类型没有 EHT 能力位，跳过
				if (!ift.eht_cap_phy)
					continue;

				// 标记该频段具备 EHT 能力
				band_info.eht = true;
				// 聚合各接口类型的 EHT 物理能力位
				eht_phy_cap |= ift.eht_cap_phy[0];
			}

			// 非 2G 且支持 HE/VHT 的 160MHz 条件
			if (band_name != "2G" &&
			    (he_phy_cap & 0x18) || ((band.vht_capa >> 2) & 0x3))
				band_info.max_width = 160;
			// 非 2G 且支持 HE/VHT 的 80MHz 条件
			else if (band_name != "2G" &&
			         (he_phy_cap & 4) || band.vht_capa > 0)
				band_info.max_width = 80;
			// 支持 HT40 或 HE40
			else if ((band.ht_capa & 0x2) || (he_phy_cap & 0x2))
				band_info.max_width = 40;
			// 默认最小带宽
			else
				band_info.max_width = 20;

			// 初始化该频段支持的模式列表，默认包含 NOHT（禁用高吞吐）
			let modes = band_info.modes = [ "NOHT" ];
			// 若支持 HT（802.11n），加入 HT20
			if (band_info.ht)
				push(modes, "HT20");

			// 若支持 VHT（802.11ac），加入 VHT20
			if (band_info.vht)
				push(modes, "VHT20");

			// 若支持 HE（802.11ax），加入 HE20
			if (band_info.he)
				push(modes, "HE20");
			
			// 若支持 EHT（802.11be），加入 EHT20
			if (band_info.eht)
				push(modes, "EHT20");

			// 若支持 HT40
			if (band.ht_capa & 0x2) {
				push(modes, "HT40");

				// 若同时支持 VHT，加入 VHT40
				if (band_info.vht)
					push(modes, "VHT40")
			}

			// 若 HE 能力包含 40MHz，加入 HE40
			if (he_phy_cap & 2)
				push(modes, "HE40");

			// 若同时具备 EHT 与 HE 的 40MHz 能力，加入 EHT40
			if (eht_phy_cap && he_phy_cap & 2)
				push(modes, "EHT40");

			// 将当前频段与每个 radio 的范围进行匹配
			for (let radio in info.radios) {

				// 判断该 radio 的频率范围是否覆盖当前 band 的某个频点
				let freq_match = filter(band.freqs,
					(freq) => freq_range_match(radio.freq_ranges, freq.freq)
				);

				// 不匹配则跳过当前 radio
				if (!length(freq_match))
					continue;

				// 创建该 radio 在此频段的对象
				let radio_band = {};
				// 关联到 radio.bands 中
				radio.bands[band_name] = radio_band;

				// 过滤掉被标记为不可用的频点
				freq_match = filter(freq_match,
					(freq) => !freq.disabled
				);

				// 取第一个可用频点
				let freq = freq_match[0];
				// 将频率转换为默认信道，记录到 radio_band
				if (freq)
					radio_band.default_channel = freq_to_channel(freq.freq);
			}

			// 在整个频段频点中，寻找第一个可用的默认信道
			for (let freq in band.freqs) {
				// 跳过禁用的频点
				if (freq.disabled)
					continue;
				// 转换为信道号
				let chan = freq_to_channel(freq.freq);
				if (!chan)
					continue;
				// 记录频段级默认信道
				band_info.default_channel = chan;
				break;
			}

			// 2G 频段不再添加更高带宽/模式条目，继续下一个 band
			if (band_name == "2G")
				continue;

			// HE 支持 80MHz 前置能力，加入 HE40（与上文重复逻辑保持一致）
			if (he_phy_cap & 4)
				push(modes, "HE40");

			// 同时具备 EHT 与 HE 的 80MHz 前置能力，加入 EHT40
			if (eht_phy_cap && he_phy_cap & 4)
				push(modes, "EHT40");

			// 若支持 VHT，加入 VHT80
			if (band_info.vht)
				push(modes, "VHT80");

			// 若 HE 能力支持 80MHz，加入 HE80
			if (he_phy_cap & 4)
				push(modes, "HE80");
			
			// 若同时具备 EHT 与 HE 的 80MHz 能力，加入 EHT80
			if (eht_phy_cap && he_phy_cap & 4)
				push(modes, "EHT80");

			// VHT 能力位指示支持 160MHz，加入 VHT160
			if ((band.vht_capa >> 2) & 0x3)
				push(modes, "VHT160");

			// HE 能力位指示支持 160MHz，加入 HE160
			if (he_phy_cap & 0x18)
				push(modes, "HE160");

			// 同时具备 EHT 与 HE 的 160MHz 能力，加入 EHT160
			if (eht_phy_cap && he_phy_cap & 0x18)
				push(modes, "EHT160");

			// EHT 支持 320MHz（仅 6GHz 相关），加入 EHT320
			if (eht_phy_cap & 2)
				push(modes, "EHT320");
		}

		// 获取/创建与该 phy/path 对应的 wlan 条目
		let entry = wiphy_get_entry(name, path);
		// 将探测到的能力信息写入条目
		entry.info = info;
	}
}

// 先清理旧的探测信息，避免与新探测结果冲突
cleanup();
// 探测当前系统 wiphy 能力，并填充到 board_data.wlan
wiphy_detect();
// 若新旧 board_data 不同，则写回 /etc/board.json（保持幂等）
if (!is_equal(prev_board_data, board_data)) {
	// 使用临时文件路径进行安全写入
	let new_file = board_file + ".new";
	// 删除可能存在的旧临时文件
	unlink(new_file);
	// 以 O_EXCL 模式创建新文件，避免覆盖已有文件
	let f = open(new_file, "wx");
	// 打开失败则退出（可能权限或磁盘异常）
	if (!f)
		exit(1);
	// 将 board_data 以 JSON 格式写入临时文件
	f.write(sprintf("%.J\n", board_data));
	// 关闭文件句柄
	f.close();
	// 原子替换为正式文件，确保更新一致性
	rename(new_file, board_file);
}
