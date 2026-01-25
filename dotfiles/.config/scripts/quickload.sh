#!/bin/bash

# 1. 获取脚本绝对路径
SCRIPT_PATH=$(realpath "$0")

# ==================== 本地化配置 (Localization) ====================
if env | grep -q "zh_CN"; then
    # 中文文案
    TXT_PROMPT="快速读档 > "
    # 加上了醒目的警告
    TXT_BOTH="🔄 全系统恢复 (⚠️ 自动重启)"
    TXT_ROOT="💻 仅恢复系统 (⚠️ 自动重启)"
    TXT_HOME="🏠 仅恢复数据 (⚠️ 自动重启)"
    TXT_CANCEL="❌ 取消"
    
    MSG_TITLE="系统恢复"
    MSG_START="正在进行恢复，请勿关闭电脑..."
    MSG_SUCCESS="恢复成功！3秒后自动重启..."
    MSG_FAIL="恢复失败，请检查日志。"
    MSG_NO_SNAP="未找到 quicksave 快照："
    MSG_MAP_FAIL="无法映射快照 ID："
else
    # English Strings
    TXT_PROMPT="Quickload > "
    TXT_BOTH="🔄 Full Restore (⚠️ Auto Reboot)"
    TXT_ROOT="💻 Restore Root Only (⚠️ Auto Reboot)"
    TXT_HOME="🏠 Restore Home Only (⚠️ Auto Reboot)"
    TXT_CANCEL="❌ Cancel"

    MSG_TITLE="System Restore"
    MSG_START="Restoring in progress, do not turn off..."
    MSG_SUCCESS="Success! Rebooting in 3s..."
    MSG_FAIL="Restore failed. Check logs."
    MSG_NO_SNAP="No quicksave found for:"
    MSG_MAP_FAIL="Map failed for:"
fi

# ==================== ROOT WORKER (核心逻辑) ====================
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

# 1. 弹出 Fuzzel 菜单 (带警告)
SELECTION=$(printf "$TXT_BOTH\n$TXT_ROOT\n$TXT_HOME\n$TXT_CANCEL" | fuzzel -d -p "$TXT_PROMPT")

# 2. 解析选择结果
case "$SELECTION" in
    "$TXT_BOTH") TARGET_MODE="both" ;;
    "$TXT_ROOT") TARGET_MODE="root" ;;
    "$TXT_HOME") TARGET_MODE="home" ;;
    *) exit 0 ;; 
esac

# 3. 发送开始通知
notify-send "$MSG_TITLE" "$MSG_START"

# 4. 提权并执行
if pkexec "$SCRIPT_PATH" --internal-run-as-root "$TARGET_MODE"; then
    # 成功逻辑
    notify-send -u critical "$MSG_TITLE" "$MSG_SUCCESS"
    sleep 3
    systemctl reboot
else
    # 失败逻辑
    notify-send -u critical "$MSG_TITLE" "$MSG_FAIL"
fi