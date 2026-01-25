#!/bin/bash

# 1. 获取脚本绝对路径 (pkexec 需要)
SCRIPT_PATH=$(realpath "$0")

# ==================== 本地化配置 (Localization) ====================
# 使用 env 命令检查环境变量中是否有任何变量包含 zh_CN
if env | grep -q "zh_CN"; then
    # 中文文案
    TXT_PROMPT="快速读档 > "
    TXT_BOTH="全系统恢复 (Root + Home)"
    TXT_ROOT="仅恢复系统 (Root)"
    TXT_HOME="仅恢复数据 (Home)"
    TXT_CANCEL="取消"
    
    MSG_TITLE="系统恢复"
    MSG_SUCCESS="恢复成功，请立即重启电脑。"
    MSG_FAIL="恢复失败，请检查日志。"
    MSG_NO_SNAP="未找到 quicksave 快照："
    MSG_MAP_FAIL="无法映射快照 ID："
else
    # English Strings
    TXT_PROMPT="Quickload > "
    TXT_BOTH="Full Restore (Root + Home)"
    TXT_ROOT="Restore Root Only"
    TXT_HOME="Restore Home Only"
    TXT_CANCEL="Cancel"

    MSG_TITLE="System Restore"
    MSG_SUCCESS="Restore successful. Please REBOOT now."
    MSG_FAIL="Restore failed. Check logs."
    MSG_NO_SNAP="No quicksave found for:"
    MSG_MAP_FAIL="Map failed for:"
fi

# ==================== ROOT WORKER (核心逻辑 - 只有 Root 身份会进这里) ====================
if [ "$1" == "--internal-run-as-root" ]; then
    MODE="$2"
    
    # 核心回档函数
    rollback_subvol() {
        local subvol=$1
        local snap_conf=$2
        
        # 1. 找 Snapper ID
        local snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep "quicksave" | tail -n 1 | awk '{print $1}')
        if [ -z "$snap_id" ]; then echo "$MSG_NO_SNAP $snap_conf"; return 1; fi

        # 2. 找 Btrfs-Assistant Index
        local ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')
        if [ -z "$ba_index" ]; then echo "$MSG_MAP_FAIL $subvol (ID: $snap_id)"; return 1; fi

        # 3. 执行回档
        btrfs-assistant -r "$ba_index"
    }

    # 根据传入的模式执行
    if [[ "$MODE" == "both" || "$MODE" == "root" ]]; then rollback_subvol "@" "root" || exit 1; fi
    if [[ "$MODE" == "both" || "$MODE" == "home" ]]; then rollback_subvol "@home" "home" || exit 1; fi
    
    exit 0
fi

# ==================== 用户交互界面 (UI) ====================

# 1. 弹出 Fuzzel 菜单
SELECTION=$(printf "$TXT_BOTH\n$TXT_ROOT\n$TXT_HOME\n$TXT_CANCEL" | fuzzel -d -p "$TXT_PROMPT")

# 2. 解析选择结果 -> 转换为内部模式
case "$SELECTION" in
    "$TXT_BOTH") TARGET_MODE="both" ;;
    "$TXT_ROOT") TARGET_MODE="root" ;;
    "$TXT_HOME") TARGET_MODE="home" ;;
    *) exit 0 ;; # 取消或无效输入直接退出
esac

# 3. 提权并调用自身
# 使用 $SCRIPT_PATH 确保 pkexec 能找到脚本
if pkexec "$SCRIPT_PATH" --internal-run-as-root "$TARGET_MODE"; then
    notify-send -u critical "$MSG_TITLE" "$MSG_SUCCESS"
else
    notify-send -u critical "$MSG_TITLE" "$MSG_FAIL"
fi