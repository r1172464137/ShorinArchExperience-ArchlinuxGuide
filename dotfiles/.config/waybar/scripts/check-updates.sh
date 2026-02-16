#!/bin/bash

# === 配置区域 ===
CACHE_FILE="$HOME/.cache/waybar-updates.json"
MAX_LINES=50 # 限制显示行数，防止底部 Waybar 渲染失败
CHECK_INTERVAL=3600

# === 自动检测 AUR Helper ===
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
else
    AUR_HELPER=""
fi

# === 生成 JSON 函数 ===
generate_json() {
    local updates=$1
    local count
    
    # 去除空行
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [ -z "$updates" ]; then
        count=0
        # 无更新时的 JSON
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
        return
    else
        count=$(echo "$updates" | wc -l)
    fi

    # === 核心：防炸截断逻辑 ===
    local tooltip_text=""
    
    if [ "$count" -gt "$MAX_LINES" ]; then
        local remainder=$((count - MAX_LINES))
        # 取前 MAX_LINES 行
        local top_list=$(echo "$updates" | head -n "$MAX_LINES")
        
        # 1. 转义双引号
        # 2. 将换行符转换为 \n 文本
        local escaped_list=$(echo "$top_list" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        
        # 拼接提示信息
        tooltip_text="${escaped_list}----------------\\n<b>⚠️ ... and ${remainder} more updates</b>"
    else
        # 数量少于限制，显示全部 (移除末尾多余的换行)
        tooltip_text=$(echo "$updates" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | head -c -2)
    fi

    # 输出最终 JSON
    printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip_text"
}

# === 检查逻辑 ===
run_check() {
    # 1. 官方源
    local REPO_UPDATES=$(checkupdates 2>/dev/null)
    local STATUS=$?

    # 2. AUR 源
    local AUR_UPDATES=""
    if [ -n "$AUR_HELPER" ]; then
        AUR_UPDATES=$($AUR_HELPER -Qua 2>/dev/null)
    fi

    local ALL_UPDATES=""
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 2 ]; then
        # 合并列表
        if [ -n "$REPO_UPDATES" ] && [ -n "$AUR_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
        elif [ -n "$REPO_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"
        else
            ALL_UPDATES="$AUR_UPDATES"
        fi
        
        # 生成并缓存
        local JSON=$(generate_json "$ALL_UPDATES")
        echo "$JSON" > "$CACHE_FILE"
        echo "$JSON"
    else
        # 错误回退：读取旧缓存
        if [ -f "$CACHE_FILE" ]; then
            cat "$CACHE_FILE"
        else
            printf '{"text": "?", "alt": "updated", "tooltip": "Check failed"}\n'
        fi
    fi
}

# === 信号处理 ===
trap 'run_check' SIGUSR1

# === 主循环 ===
while true; do
    run_check
    sleep "$CHECK_INTERVAL" &
    wait $!
done
