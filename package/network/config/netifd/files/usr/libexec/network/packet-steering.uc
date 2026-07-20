#!/usr/bin/env ucode
/*
 * packet-steering.uc — OpenWrt 通用数据包引导 (RPS/RFS) 配置器
 * 根据 CPU 拓扑和网络设备 NAPI 线程, 自动计算最优的 RPS/RFS 分配策略:
 *   1. 探测所有物理网络设备和 NAPI 线程
 *   2. 按负载均衡算法分配 CPU 核心
 *   3. 写 /sys/class/net/<dev>/queues/<rxq>/rps_cpus 和 rps_flow_cnt
 *   4. 用 taskset 绑定 NAPI 软中断线程到指定 CPU
 * 参数: [0|1|2]  [-l <flows>]  [-n dry-run] [-d debug]
 */
'use strict';
import { glob, basename, dirname, readlink, readfile, realpath, writefile, error, open } from "fs";

let napi_weight = 1.0;
let cpu_thread_weight = 0.75;
let rx_weight = 0.75;
let eth_bias = 2.0;
let debug = 0, do_nothing = 0;
let disable;
let cpus;
let all_cpus;
let local_flows = 0;

// 解析命令行参数:
//   -d      调试输出 (可叠加)
//   -n      dry-run 模式 (只打印, 不实际写入)
//   0       关闭 packet steering (disable)
//   2       对所有 CPU 启用 RPS (非仅单核绑定)
//   -l <n>  设置 RFS 流表大小
while (length(ARGV) > 0) {
	let arg = shift(ARGV);
	switch (arg) {
	case "-d":
		debug++;
		break;
	case "-n":
		do_nothing++;
		break;
	case '0':
		disable = true;
		break;
	case '2':
		all_cpus = true;
		break;
	case '-l':
		local_flows = +shift(ARGV);
		break;
	}
}

// 读取 /proc/<pid>/status 的 Name 字段, 返回进程名
// 用于识别 NAPI 线程名 (如 "napi/eth0-0", "mt76-tx phy0")
function task_name(pid)
{
	let stat = open(`/proc/${pid}/status`, "r");
	if (!stat)
		return;
	let line = stat.read("line");
	stat.close();
	return trim(split(line, "\t", 2)[1]);
}

// 用 taskset 将指定进程绑定到指定 CPU 核心
// disable 模式: 绑定到所有 CPU (解除绑核限制)
function set_task_cpu(pid, cpu) {
	if (disable)
		cpu = join(",", map(cpus, (cpu) => cpu.id));
	let name = task_name(pid);
	if (!name)
		return;
	if (debug || do_nothing)
		warn(`taskset -p -c ${cpu} ${name}\n`);
	if (!do_nothing)
		system(`taskset -p -c ${cpu} ${pid}`);
}

// 将 CPU 编号转为十六进制 CPU 掩码 (写 rps_cpus 用)
// cpu < 0 表示所有 CPU
function cpu_mask(cpu)
{
	let mask;
	if (cpu < 0)
		mask = (1 << length(cpus)) - 1;
	else
		mask = (1 << int(cpu));
	return sprintf("%x", mask);
}

// 设置网络设备的 RPS/RFS 参数
// rps_cpus: 哪些 CPU 处理该队列的收包软中断
// rps_flow_cnt: RFS 流表大小 (硬件流导向)
function set_netdev_cpu(dev, cpu, rx_queue) {
	rx_queue ??= "rx-*";
	let queues = glob(`/sys/class/net/${dev}/queues/${rx_queue}/rps_cpus`);
	let val = cpu_mask(cpu);
	if (disable)
		val = 0;
	for (let queue in queues) {
		if (debug || do_nothing)
			warn(`echo ${val} > ${queue}\n`);
		if (!do_nothing)
			writefile(queue, `${val}`);
	}
	queues = glob(`/sys/class/net/${dev}/queues/${rx_queue}/rps_flow_cnt`);
	for (let queue in queues) {
		if (debug || do_nothing)
			warn(`echo ${local_flows} > ${queue}\n`);
		if (!do_nothing)
			writefile(queue, `${local_flows}`);
	}
}

// 判断 NAPI 线程名是否属于指定设备
// 匹配规则: "napi/<dev>-<qid>" 或 "mt76-tx phy<N>"
function task_device_match(name, device)
{
	let napi_match = match(name, /napi\/([^-]*)-\d+/);
	if (!napi_match)
		napi_match = match(name, /mt76-tx (phy\d+)/);
	if (napi_match &&
	    (index(device.phy, napi_match[1]) >= 0 ||
	     index(device.netdev, napi_match[1]) >= 0))
		return true;

	if (device.driver == "mtk_soc_eth" && match(name, /napi\/mtk_eth-/))
		return true;

	return false;
}

cpus = map(glob("/sys/bus/cpu/devices/*"), (path) => {
	return {
		id: int(match(path, /.*cpu(\d+)/)[1]),
		core: int(trim(readfile(`${path}/topology/core_id`))),
		load: 0.0,
	};
});

cpus = slice(cpus, 0, 64);
if (length(cpus) < 2)
	exit(0);

// 为指定 CPU 增加负载权重
// 同时给同物理核的 sibling (超线程) 加上 cpu_thread_weight 倍权重
function cpu_add_weight(cpu_id, weight)
{
	let cpu = cpus[cpu_id];
	cpu.load += weight;
	for (let sibling in cpus) {
		if (sibling == cpu || sibling.core != cpu.core)
			continue;
		sibling.load += weight * cpu_thread_weight;
	}
}

// 负载均衡核心算法: 选择当前负载最低的 CPU
// prev_cpu: 上一步选中的 CPU (多队列时避免重复分配到同一个核)
function get_next_cpu(weight, prev_cpu)
{
	if (disable)
		return 0;

	let sort_cpus = sort(slice(cpus), (a, b) => a.load - b.load);
	let idx = 0;

	if (prev_cpu != null && sort_cpus[idx].id == prev_cpu)
		idx++;

	let cpu = sort_cpus[idx].id;
	cpu_add_weight(cpu, weight);
	return cpu;
}

let phys_devs = {};
let netdev_phys = {};
let netdevs = map(glob("/sys/class/net/*"), (dev) => basename(dev));

for (let dev in netdevs) {
	let pdev_path = realpath(`/sys/class/net/${dev}/device`);
	if (!pdev_path)
		continue;

	if (length(glob(`/sys/class/net/${dev}/lower_*`)) > 0)
		continue;

	let pdev = phys_devs[pdev_path];
	if (!pdev) {
		pdev = phys_devs[pdev_path] = {
			path: pdev_path,
			driver: basename(readlink(`${pdev_path}/driver`)),
			netdev: [],
			phy: [],
			tasks: [],
			rx_tasks: [],
			rx_queues: map(glob(`/sys/class/net/${dev}/queues/rx-*/rps_cpus`),
			               (v) => basename(dirname(v))),
		};
	}

	let phyidx = trim(readfile(`/sys/class/net/${dev}/phy80211/index`));
	if (phyidx != null) {
		let phy = `phy${phyidx}`;
		if (index(pdev.phy, phy) < 0)
			push(pdev.phy, phy);
	}

	push(pdev.netdev, dev);
	netdev_phys[dev] = pdev;
}

// 按 CPU 拓扑映射, 跳过虚拟接口 (有 lower_* 的)

// 扫描 /proc/*/exe, 通过 NAPI 线程名匹配将线程归属到对应设备
for (let path in glob("/proc/*/exe")) {
	readlink(path);
	if (error() != "No such file or directory")
		continue;

	let pid = basename(dirname(path));
	let name = task_name(pid);
	for (let devname in phys_devs) {
		let dev = phys_devs[devname];
		if (!task_device_match(name, dev))
			continue;

		push(dev.tasks, pid);

		let napi_match = match(name, /napi\/([^-]*)-(\d+)/);
		if (napi_match && napi_match[2] > 0)
			push(dev.rx_tasks, pid);
		break;
	}
}

function assign_dev_queues_cpu(dev) {
	let num = length(dev.rx_queues);
	if (num < length(dev.rx_tasks))
		num = length(dev.rx_tasks);

	for (let i = 0; i < num; i++) {
		let cpu;

		let task = dev.rx_tasks[i];
		if (num >= length(cpus))
			cpu = i % length(cpus);
		else if (task)
			cpu = get_next_cpu(napi_weight);
		else
			cpu = -1;
		set_task_cpu(task, cpu);

		let rxq = dev.rx_queues[i];
		if (!rxq)
			continue;

		if (num >= length(cpus))
			cpu = (i + 1) % length(cpus);
		else if (all_cpus)
			cpu = -1;
		else
			cpu = get_next_cpu(napi_weight, cpu);
		for (let netdev in dev.netdev)
			set_netdev_cpu(netdev, cpu, rxq);
	}
}

function assign_dev_cpu(dev) {
	if (length(dev.rx_queues) > 1 &&
		length(dev.rx_tasks) > 1)
		return assign_dev_queues_cpu(dev);

	if (length(dev.tasks) > 0) {
		let cpu = dev.napi_cpu = get_next_cpu(napi_weight);
		for (let task in dev.tasks)
			set_task_cpu(task, cpu);
	}

	if (length(dev.netdev) > 0) {
		let cpu;
		if (all_cpus)
			cpu = -1;
		else
			cpu = get_next_cpu(rx_weight, dev.napi_cpu);
		for (let netdev in dev.netdev)
			set_netdev_cpu(netdev, cpu);
	}
}

// Assign ethernet devices first
for (let devname in phys_devs) {
	let dev = phys_devs[devname];
	if (!length(dev.phy))
		assign_dev_cpu(dev);
}

// Add bias to avoid assigning other tasks to CPUs with ethernet NAPI
for (let devname in phys_devs) {
	let dev = phys_devs[devname];
	if (!length(dev.tasks) || dev.napi_cpu == null)
		continue;
	cpu_add_weight(dev.napi_cpu, eth_bias);
}

// Assign WLAN devices
for (let devname in phys_devs) {
	let dev = phys_devs[devname];
	if (length(dev.phy) > 0)
		assign_dev_cpu(dev);
}

if (debug > 1)
	warn(sprintf("devices: %.J\ncpus: %.J\n", phys_devs, cpus));
