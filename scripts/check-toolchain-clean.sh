#!/bin/sh

# 这个脚本的主要功能是检查OpenWrt工具链的版本是否发生变化
## 如果发生变化，它会执行清理操作以确保使用新版本工具链重新编译。这样可以避免因工具链版本不匹配导致的潜在问题

# 从.config文件中获取GCC版本配置信息并执行，将结果存入环境变量
eval "$(grep CONFIG_GCC_VERSION .config)"

# 构建工具链版本标识符，格式为：GCC版本号-构建版本号
CONFIG_TOOLCHAIN_BUILD_VER="$CONFIG_GCC_VERSION-$(cat toolchain/build_version)"

# 创建或更新工具链构建版本文件的时间戳
touch .toolchain_build_ver

# 读取当前保存的工具链构建版本号
CURRENT_TOOLCHAIN_BUILD_VER="$(cat .toolchain_build_ver)"

# 如果当前没有保存的工具链版本号（文件为空），则写入新的版本号并退出
[ -z "$CURRENT_TOOLCHAIN_BUILD_VER" ] && {
	echo "$CONFIG_TOOLCHAIN_BUILD_VER" > .toolchain_build_ver
	exit 0
}

# 如果新旧工具链版本号相同，则直接退出
[ "$CONFIG_TOOLCHAIN_BUILD_VER" = "$CURRENT_TOOLCHAIN_BUILD_VER" ] && exit 0

# 输出提示信息，说明工具链版本发生变化
echo "Toolchain build version changed ($CONFIG_TOOLCHAIN_BUILD_VER != $CURRENT_TOOLCHAIN_BUILD_VER), running make targetclean"

# 执行make targetclean命令清理目标文件
make targetclean

# 将新的工具链版本号写入文件
echo "$CONFIG_TOOLCHAIN_BUILD_VER" > .toolchain_build_ver
exit 0
