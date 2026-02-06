#!/bin/bash

# === 配置部分 ===
CACHE_FILE="$HOME/.cache/waybar-updates.json"
CHECK_INTERVAL=3600  # 检查间隔：1小时 (秒)

# === 函数定义 ===
generate_json() {
    local updates=$1
    local count
    
    if [ -z "$updates" ]; then
        count=0
    else
        count=$(echo "$updates" | wc -l)
    fi

    if [ "$count" -gt 0 ]; then
        # 处理 tooltip：转义引号，移除末尾换行
        local tooltip=$(echo "$updates" | awk '{printf "%s\\n", $0}' | sed 's/"/\\"/g' | head -c -2)
        printf '{"text": "%s", "alt": "has-updates", "tooltip": "%s"}\n' "$count" "$tooltip"
    else
        printf '{"text": "", "alt": "updated", "tooltip": "System is up to date"}\n'
    fi
}

# === 核心逻辑函数 ===
run_check() {
    # 尝试获取更新
    # 捕获输出
    local NEW_UPDATES
    NEW_UPDATES=$(checkupdates 2>/dev/null)
    local STATUS=$?

    # checkupdates 退出代码说明：
    # 0 = 有更新
    # 2 = 无更新 (这是正常情况，不是错误！)
    # 1 = 发生错误 (如网络断开、锁被占用)

    local OUTPUT=""

    if [ $STATUS -eq 0 ]; then
        # --- 情况A：发现更新 ---
        OUTPUT=$(generate_json "$NEW_UPDATES")
        echo "$OUTPUT" > "$CACHE_FILE"
        echo "$OUTPUT"

    elif [ $STATUS -eq 2 ]; then
        # --- 情况B：正常运行，但没有更新 ---
        # 必须清空缓存或者写入 0 状态
        OUTPUT=$(generate_json "")
        echo "$OUTPUT" > "$CACHE_FILE"
        echo "$OUTPUT"

    else
        # --- 情况C：真的出错了 (Exit 1) ---
        # 比如没网，或者 pacman 锁死
        # 只有这种时候才读取旧缓存来保底
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
