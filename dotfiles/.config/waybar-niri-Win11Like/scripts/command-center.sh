#!/bin/bash

# ==============================================================================
# Command Center - 常用维护指令集
# ==============================================================================
# 脚本功能：
# 1. 严格模式执行，保障代码健壮性。
# 2. 启动时检测必要的前置依赖 (kitty)，若缺失则通过终端和桌面弹窗双重报错。
# 3. 动态检测环境并按需生成 Fuzzel 菜单选项：
#    - 检测 BTRFS 文件系统及快照工具，决定是否显示快速存读档和深度清理。
#    - 检测 .local/share/shorin-niri 目录，决定是否显示 Shorin 更新。
#    - 检测 NetworkManager 及其后端，动态显示并调用联网工具 (impala/nmtui)。
#    - 检测是否存在蓝牙设备，动态探测并显示可用的蓝牙界面工具 (bluetuith/blueman/blueberry等)。
# ==============================================================================

# 启用严格模式：
# -e: 命令执行失败(非0)时立即退出
# -u: 使用未定义变量时报错并退出
# -o pipefail: 管道中任何一个命令失败都会导致整个管道返回失败
set -euo pipefail

# 错误处理与通知函数
report_error() {
    local error_msg="$1"
    echo "错误：$error_msg" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical -a "Command Center" "Shorin 指令异常" "$error_msg" || true
    fi
}

# 0. 基础依赖检测 (kitty)
if ! command -v kitty >/dev/null 2>&1; then
    report_error "未找到 kitty 终端，请先安装。"
    exit 1
fi

# 定义静态菜单选项
OPT_SAVE="快速存档 (quicksave)"
OPT_LOAD="快速读档 (quickload)"
OPT_MIRROR="更新镜像源 (mirror-update)"
OPT_SYSUP="更新系统 (sysup)"
OPT_SHORIN="更新Shorin's Niri (shorin-update)"
OPT_CLEAN="系统清理 (clean)"
OPT_DEEP_CLEAN="深度系统清理 (clean all)"

# 定义动态菜单选项及其对应的命令环境变量，满足 set -u 要求
OPT_NETWORK=""
NET_TOOL=""
OPT_BLUETOOTH=""
BT_TOOL=""

# 使用数组存储动态生成的选项
OPTIONS_ARR=()

# 1. BTRFS 相关判断
BTRFS_MODE=false
if [[ "$(stat -f -c %T /)" == "btrfs" ]] && \
   command -v shorin >/dev/null 2>&1 && \
   command -v snapper >/dev/null 2>&1 && \
   command -v btrfs-assistant >/dev/null 2>&1; then
    BTRFS_MODE=true
    OPTIONS_ARR+=("$OPT_SAVE")
    OPTIONS_ARR+=("$OPT_LOAD")
fi

# 基础选项
OPTIONS_ARR+=("$OPT_MIRROR")
OPTIONS_ARR+=("$OPT_SYSUP")

# 5. 检测特定目录存在与否决定 Shorin 更新选项
if [[ -d "$HOME/.local/share/shorin-niri" ]]; then
    OPTIONS_ARR+=("$OPT_SHORIN")
fi

OPTIONS_ARR+=("$OPT_CLEAN")

# 2. 如果满足 BTRFS 判定条件，追加深度清理
if [[ "$BTRFS_MODE" == true ]]; then
    OPTIONS_ARR+=("$OPT_DEEP_CLEAN")
fi

# 3. 判断当前是否使用 NetworkManager，并确定后端工具
if systemctl is-active --quiet NetworkManager; then
    if NetworkManager --print-config 2>/dev/null | grep -iq 'wifi\.backend.*iwd' || systemctl is-active --quiet iwd; then
        NET_TOOL="impala"
    else
        NET_TOOL="nmtui"
    fi
    OPT_NETWORK="联网工具 ($NET_TOOL)"
    OPTIONS_ARR+=("$OPT_NETWORK")
fi

# 4. 判断蓝牙设备是否存在，并探测可用的图形/终端界面工具
if [[ -d /sys/class/bluetooth ]] && [[ -n "$(ls -A /sys/class/bluetooth 2>/dev/null || true)" ]]; then
    # 按照个人偏好或常见程度排列优先级
    if command -v bluetui >/dev/null 2>&1; then
        BT_TOOL="bluetui"
    elif command -v blueman-manager >/dev/null 2>&1; then
        BT_TOOL="blueman-manager"
    elif command -v blueberry >/dev/null 2>&1; then
        BT_TOOL="blueberry"
    else
        BT_TOOL="bluetoothctl" # 兜底选项
    fi
    
    OPT_BLUETOOTH="蓝牙工具 ($BT_TOOL)"
    OPTIONS_ARR+=("$OPT_BLUETOOTH")
fi

# 调用 Fuzzel 显示菜单
SELECTED=$(printf "%s\n" "${OPTIONS_ARR[@]}" | fuzzel --dmenu \
    -p "Shorin指令 > " \
    --placeholder "命令可手动运行" \
    --placeholder-color 80808099 || true)

# 如果用户未选择任何项直接退出
if [[ -z "$SELECTED" ]]; then
    exit 0
fi

# 根据选择执行命令
case "$SELECTED" in
    "$OPT_SAVE")
        quicksave &
        ;;
    "$OPT_LOAD")
        quickload &
        ;;
    "$OPT_MIRROR")
        kitty --single-instance --class command-center --title "更新镜像源" bash -c "~/.local/bin/mirror-update; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SYSUP")
        kitty --single-instance --class command-center --title "系统更新" bash -c "~/.local/bin/sysup; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_SHORIN")
        kitty --single-instance --class command-center --title "Shorin更新" bash -c "~/.local/bin/shorin-update; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_CLEAN")
        kitty --single-instance --class command-center --title "系统清理" bash -c "~/.local/bin/clean; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_DEEP_CLEAN")
        kitty --single-instance --class command-center --title "深度系统清理" bash -c "~/.local/bin/clean all; echo; echo '按任意键退出...'; read -n 1 -s -r"
        ;;
    "$OPT_NETWORK")
        if [[ -n "$NET_TOOL" ]]; then
            kitty --single-instance --class command-center --title "联网工具" bash -c "$NET_TOOL"
        fi
        ;;
    "$OPT_BLUETOOTH")
        if [[ -n "$BT_TOOL" ]]; then
            # 统一使用 kitty 启动。如果是 TUI (如 bluetuith) 则完美适配。
            # 即使探测到的是 GUI (如 blueman-manager)，通过 bash -c 启动同样有效，遵守了原设定的调用风格。
            kitty --single-instance --class command-center --title "蓝牙工具" bash -c "$BT_TOOL"
        fi
        ;;
    *)
        report_error "未知的选项: $SELECTED"
        exit 1
        ;;
esac
