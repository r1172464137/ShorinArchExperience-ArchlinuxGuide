#!/bin/bash

# ==================== ROOT WORKER (核心逻辑) ====================
if [ "$1" == "--internal-run-as-root" ]; then
    MODE="$2"
    
    # 定义回档函数：参数1=子卷名(@/@home), 参数2=Snapper配置名(root/home)
    rollback_subvol() {
        local subvol=$1
        local snap_conf=$2
        
        # 1. 找 Snapper ID (列出->过滤quicksave->取最后一行->取ID)
        local snap_id=$(snapper -c "$snap_conf" list --columns number,description | grep "quicksave" | tail -n 1 | awk '{print $1}')
        
        if [ -z "$snap_id" ]; then echo "No quicksave found for $snap_conf"; return 1; fi

        # 2. 找 Btrfs-Assistant Index (匹配子卷和SnapperID -> 取Index)
        local ba_index=$(btrfs-assistant -l | awk -v v="$subvol" -v s="$snap_id" '$2==v && $3==s {print $1}')
        
        if [ -z "$ba_index" ]; then echo "Map failed: $subvol (SnapID: $snap_id)"; return 1; fi

        # 3. 执行回档
        btrfs-assistant -r "$ba_index"
    }

    # 根据模式执行
    if [[ "$MODE" == "both" || "$MODE" == "root" ]]; then rollback_subvol "@" "root"; fi
    if [[ "$MODE" == "both" || "$MODE" == "home" ]]; then rollback_subvol "@home" "home"; fi
    
    # 既然是root shell，不需要notify-send (dbus可能会挂)，直接返回状态码
    exit 0
fi

# ==================== USER INTERFACE (用户界面) ====================
CONFIG="$HOME/.cache/quickload_config"
[ ! -f "$CONFIG" ] && echo "both" > "$CONFIG"
CURRENT_MODE=$(cat "$CONFIG")

# 1. 菜单选择
SELECTION=$(printf "Load Quicksave (Mode: $CURRENT_MODE)\nConfig Mode\nCancel" | fuzzel -d -p "Quickload > ")

case "$SELECTION" in
    "Config Mode")
        NEW_MODE=$(printf "both\nroot\nhome" | fuzzel -d -p "Set Mode > ")
        [ -n "$NEW_MODE" ] && echo "$NEW_MODE" > "$CONFIG" && notify-send "Mode saved: $NEW_MODE"
        exec "$0" ;; # 重启脚本
    "Load Quicksave"*)
        # 2. Polkit 提权 -> 新开 Root Shell 运行本脚本的 Worker 部分
        if pkexec "$0" --internal-run-as-root "$CURRENT_MODE"; then
            notify-send -u critical "Quickload Success" "System restored. Please REBOOT."
        else
            notify-send -u critical "Quickload Failed" "Check logs or snapshot existence."
        fi
        ;;
    *) exit 0 ;;
esac
