#!/bin/bash
# ==============================================================================
# 功能：Waybar 更新检测后台守护脚本
# 特性：定期检查 Pacman 和 AUR 更新，生成 JSON 供 Waybar 渲染，
#       同时生成纯净文本缓存供 fzf 脚本极速读取。
# ==============================================================================

set -euo pipefail

# === 配置区域 ===
CACHE_DIR="$HOME/.cache/shorin-check-arch-updates"
CACHE_FILE="$CACHE_DIR/updates.json"
LOCK_FILE="/tmp/waybar-updates.lock"
MAX_LINES=50
CHECK_INTERVAL=3600

# 确保缓存目录存在
mkdir -p "$CACHE_DIR"

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
    
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [[ -z "$updates" ]]; then
        count=0
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
        return
    else
        count=$(echo "$updates" | wc -l)
    fi

    local tooltip_text=""
    if [[ "$count" -gt "$MAX_LINES" ]]; then
        local remainder=$((count - MAX_LINES))
        local top_list=$(echo "$updates" | head -n "$MAX_LINES")
        local escaped_list=$(echo "$top_list" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' )
        tooltip_text="${escaped_list}----------------\\n<b>⚠️ ... and ${remainder} more updates</b>"
    else
        tooltip_text=$(echo "$updates" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | head -c -2 || true)
    fi

    printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip_text"
}

# === 真正的检查逻辑 ===
perform_update_check() {
    # 1. 官方源 (兼容 set -e：如果没有更新 checkupdates 返回 2，捕获状态码避免退出)
    local REPO_UPDATES=""
    local STATUS=0
    REPO_UPDATES=$(checkupdates 2>/dev/null) || STATUS=$?

    # 2. AUR 源
    local AUR_UPDATES=""
    if [[ -n "$AUR_HELPER" ]]; then
        AUR_UPDATES=$("$AUR_HELPER" -Qua 2>/dev/null || true)
    fi

    local ALL_UPDATES=""
    if [[ $STATUS -eq 0 ]] || [[ $STATUS -eq 2 ]]; then
        if [[ -n "$REPO_UPDATES" ]] && [[ -n "$AUR_UPDATES" ]]; then
            ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
        elif [[ -n "$REPO_UPDATES" ]]; then
            ALL_UPDATES="$REPO_UPDATES"
        else
            ALL_UPDATES="$AUR_UPDATES"
        fi
        
        # 写入分离的纯净数据缓存供 fzf 脚本精细化读取和染色
        echo "$REPO_UPDATES" > "${CACHE_FILE%.json}-repo.txt"
        echo "$AUR_UPDATES" > "${CACHE_FILE%.json}-aur.txt"
        
        # 写入 JSON 缓存
        generate_json "$ALL_UPDATES" > "$CACHE_FILE"
    else
        # 检查失败时不覆盖缓存，防止写入错误数据
        return 1
    fi
}

# === 主控制逻辑 ===
run_check() {
    # 1. 检查缓存是否“新鲜”
    if [[ -f "$CACHE_FILE" ]]; then
        local current_time file_time age
        current_time=$(date +%s)
        file_time=$(stat -c %Y "$CACHE_FILE")
        age=$((current_time - file_time))
        
        if [[ $age -lt $((CHECK_INTERVAL - 10)) ]]; then
            cat "$CACHE_FILE"
            return
        fi
    fi

    # 2. 缓存过期，尝试获取锁进行更新
    (
        if flock -x -n 9; then
            perform_update_check
        else
            flock -x -w 120 9
        fi
    ) 9>"$LOCK_FILE"

    # 3. 最终输出缓存内容
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    else
        printf '{"text": "...", "alt": "updated", "tooltip": "Checking..."}\n'
    fi
}

# === 信号处理 ===
trap 'rm -f "$CACHE_FILE" "${CACHE_FILE%.json}-repo.txt" "${CACHE_FILE%.json}-aur.txt"; run_check' SIGUSR1

# === 主循环 ===
while true; do
    run_check
    sleep "$CHECK_INTERVAL" &
    wait $!
done
