#!/bin/bash

# === 配置部分 ===
CACHE_FILE="$HOME/.cache/waybar-updates.json"
CHECK_INTERVAL=3600  # 检查间隔：1小时 (秒)

# === 自动检测 AUR Helper ===
if command -v paru &> /dev/null; then
    AUR_HELPER="paru"
elif command -v yay &> /dev/null; then
    AUR_HELPER="yay"
else
    AUR_HELPER=""
fi

# === 函数定义 ===
generate_json() {
    local updates=$1
    local count
    
    # 去除可能的空行，避免计数错误
    updates=$(echo "$updates" | grep -v '^\s*$' || true)
    
    if [ -z "$updates" ]; then
        count=0
    else
        count=$(echo "$updates" | wc -l)
    fi

    if [ "$count" -gt 0 ]; then
        # 处理 tooltip：转义引号，移除末尾换行
        # 使用 awk 确保每一行都被正确处理，head -c -2 移除最后多余的 \n
        local tooltip=$(echo "$updates" | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g' | head -c -2)
        printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip"
    else
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
    fi
}

# === 核心逻辑函数 ===
run_check() {
    # 1. 获取官方仓库更新
    local REPO_UPDATES
    REPO_UPDATES=$(checkupdates 2>/dev/null)
    local STATUS=$?

    # checkupdates 退出代码说明：
    # 0 = 有更新
    # 2 = 无更新 (正常情况)
    # 1 = 发生错误

    local OUTPUT=""
    local ALL_UPDATES=""
    local AUR_UPDATES=""

    # 只要状态不是错误 (1)，我们就继续检查 AUR
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 2 ]; then
        
        # 2. 获取 AUR 更新 (如果安装了 helper)
        if [ -n "$AUR_HELPER" ]; then
            AUR_UPDATES=$($AUR_HELPER -Qua 2>/dev/null)
        fi

        # 3. 合并列表
        if [ -n "$REPO_UPDATES" ] && [ -n "$AUR_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"$'\n'"$AUR_UPDATES"
        elif [ -n "$REPO_UPDATES" ]; then
            ALL_UPDATES="$REPO_UPDATES"
        else
            ALL_UPDATES="$AUR_UPDATES"
        fi

        # 4. 生成 JSON 并输出
        OUTPUT=$(generate_json "$ALL_UPDATES")
        echo "$OUTPUT" > "$CACHE_FILE"
        echo "$OUTPUT"

    else
        # --- 情况C：官方源检查出错了 (Exit 1) ---
        # 比如没网，或者 pacman 锁死
        # 这种情况下通常不建议继续查 AUR，直接读取旧缓存来保底
        if [ -f "$CACHE_FILE" ]; then
            cat "$CACHE_FILE"
        else
            printf '{"text": "?", "alt": "updated", "tooltip": "Check failed"}\n'
        fi
    fi
}

# === 信号处理 ===
# 收到 SIGUSR1 信号时，调用 run_check
trap 'run_check' SIGUSR1

# === 主循环 (守护进程模式) ===
while true; do
    run_check
    
    # 这里的技巧是：将 sleep 放入后台，然后 wait 它
    # 当收到信号时，wait 会被强制中断，脚本会立即进入下一次循环（运行 run_check）
    # 从而实现“点击即刷新”的效果，而不需要等待 sleep 结束
    sleep "$CHECK_INTERVAL" &
    wait $!
done
