#!/bin/bash

# 1. 获取脚本的绝对路径 (修复 "No such file" 错误的核心)
SCRIPT_PATH=$(realpath "$0")

# ==================== ROOT WORKER (核心逻辑) ====================
if [ "$1" == "--internal-run-as-root" ]; then
    MODE="$2"
    
    # 定义回档函数
    rollback_subvol() {
        local subvol=$1
        local snap_conf=$2
        
        # 找 Snapper ID
        local snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep "quicksave" | tail -n 1 | awk '{print $1}')
        if [ -z "$snap_id" ]; then echo "No quicksave found for $snap_conf"; return 1; fi

        # 找 Btrfs-Assistant Index
        local ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')
        if [ -z "$ba_index" ]; then echo "Map failed: $subvol (SnapID: $snap_id)"; return 1; fi

        # 执行回档
        btrfs-assistant -r "$ba_index"
    }

    # 根据模式执行
    if [[ "$MODE" == "both" || "$MODE" == "root" ]]; then rollback_subvol "@" "root"; fi
    if [[ "$MODE" == "both" || "$MODE" == "home" ]]; then rollback_subvol "@home" "home"; fi
    
    exit 0
fi

# ==================== USER INTERFACE (用户界面) ====================
CONFIG="$HOME/.cache/quickload_config"
[ ! -f "$CONFIG" ] && echo "both" > "$CONFIG"
CURRENT_MODE=$(cat "$CONFIG")

# 菜单选择
SELECTION=$(printf "Load Quicksave (Mode: $CURRENT_MODE)\nConfig Mode\nCancel" | fuzzel -d -p "Quickload > ")

case "$SELECTION" in
    "Config Mode")
        NEW_MODE=$(printf "both\nroot\nhome" | fuzzel -d -p "Set Mode > ")
        [ -n "$NEW_MODE" ] && echo "$NEW_MODE" > "$CONFIG" && notify-send "Mode saved: $NEW_MODE"
        exec "$SCRIPT_PATH" ;; # 使用绝对路径重新运行
    "Load Quicksave"*)
        # 2. 这里改成了使用 $SCRIPT_PATH (绝对路径)
        if pkexec "$SCRIPT_PATH" --internal-run-as-root "$CURRENT_MODE"; then
            notify-send -u critical "Quickload Success" "System restored. Please REBOOT."
        else
            notify-send -u critical "Quickload Failed" "Check logs or snapshot existence."
        fi
        ;;
    *) exit 0 ;;
esac