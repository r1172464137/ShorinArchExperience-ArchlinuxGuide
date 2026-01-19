#!/bin/bash

# 脚本功能：
# 从随机老婆图片生成api下载图片。
# 支持 --nsfw 参数或 NSFW=1 环境变量开启 R18 模式。

# --- 0. 参数解析与模式设置 ---

NSFW_MODE=false
# 检查环境变量
if [ "$NSFW" = "1" ]; then
    NSFW_MODE=true
fi

# 检查命令行参数，并过滤掉 --nsfw 以便传递剩余参数给 fastfetch
ARGS_FOR_FASTFETCH=()
for arg in "$@"; do
    if [ "$arg" == "--nsfw" ]; then
        NSFW_MODE=true
    else
        ARGS_FOR_FASTFETCH+=("$arg")
    fi
done

# --- 1. 配置区域 ---

# 根据模式区分缓存目录和锁文件，防止混淆
if [ "$NSFW_MODE" = true ]; then
    CACHE_DIR="$HOME/.cache/fastfetch_waifu_nsfw"
    LOCK_FILE="/tmp/fastfetch_waifu_nsfw.lock"
    # echo "当前模式: NSFW (要注意背后有没有人哦)" 
else
    CACHE_DIR="$HOME/.cache/fastfetch_waifu"
    LOCK_FILE="/tmp/fastfetch_waifu.lock"
fi

DOWNLOAD_BATCH_SIZE=10   # 每次补货下载多少张
MAX_CACHE_LIMIT=100      # 最大库存上限
MIN_TRIGGER_LIMIT=60     # 库存少于多少张时开始补货

mkdir -p "$CACHE_DIR"

# --- 2. 核心函数 ---

get_random_url() {
    local TIMEOUT="--connect-timeout 5 --max-time 15"
    RAND=$(( ( RANDOM % 3 ) + 1 ))
    
    if [ "$NSFW_MODE" = true ]; then
        # === NSFW API 列表 ===
        case $RAND in
            # waifu.im 开启 is_nsfw=true
            1) curl -s $TIMEOUT "https://api.waifu.im/search?included_tags=waifu&is_nsfw=true" | jq -r '.images[0].url' ;;
            # waifu.pics NSFW 频道 (waifu)
            2) curl -s $TIMEOUT "https://api.waifu.pics/nsfw/waifu" | jq -r '.url' ;;
            # waifu.pics NSFW 频道 (neko) - 替换掉了没有 NSFW 的 nekos.best
            3) curl -s $TIMEOUT "https://api.waifu.pics/nsfw/neko" | jq -r '.url' ;;
        esac
    else
        # === SFW (正常) API 列表 ===
        case $RAND in
            1) curl -s $TIMEOUT "https://api.waifu.im/search?included_tags=waifu&is_nsfw=false" | jq -r '.images[0].url' ;;
            2) curl -s $TIMEOUT "https://nekos.best/api/v2/waifu" | jq -r '.results[0].url' ;;
            3) curl -s $TIMEOUT "https://api.waifu.pics/sfw/waifu" | jq -r '.url' ;;
        esac
    fi
}

download_one_image() {
    URL=$(get_random_url)
    # 简单的 URL 校验
    if [[ "$URL" =~ ^http ]]; then
        FILENAME="waifu_$(date +%s%N)_$RANDOM.jpg"
        TARGET_PATH="$CACHE_DIR/$FILENAME"
        
        # 下载
        curl -s -L --connect-timeout 5 --max-time 15 -o "$TARGET_PATH" "$URL"
        
        # [安全验证]
        if [ -s "$TARGET_PATH" ]; then
            if command -v file >/dev/null 2>&1; then
                if ! file --mime-type "$TARGET_PATH" | grep -q "image/"; then
                    rm -f "$TARGET_PATH"
                fi
            fi
        else
            rm -f "$TARGET_PATH"
        fi
    fi
}

background_job() {
    (
        flock -n 200 || exit 1
        
        # 1. 补货检查
        CURRENT_COUNT=$(find "$CACHE_DIR" -maxdepth 1 -name "*.jpg" 2>/dev/null | wc -l)

        if [ "$CURRENT_COUNT" -lt "$MIN_TRIGGER_LIMIT" ]; then
            for ((i=1; i<=DOWNLOAD_BATCH_SIZE; i++)); do
                download_one_image
                sleep 0.5
            done
        fi

        # 2. 清理逻辑
        FINAL_COUNT=$(find "$CACHE_DIR" -maxdepth 1 -name "*.jpg" 2>/dev/null | wc -l)
        
        if [ "$FINAL_COUNT" -gt "$MAX_CACHE_LIMIT" ]; then
             DELETE_START_LINE=$((MAX_CACHE_LIMIT + 1))
             ls -tp "$CACHE_DIR"/*.jpg 2>/dev/null | tail -n +$DELETE_START_LINE | xargs -I {} rm -- "{}"
        fi
        
    ) 200>"$LOCK_FILE"
}

# --- 3. 主程序逻辑 ---

shopt -s nullglob
FILES=("$CACHE_DIR"/*.jpg)
NUM_FILES=${#FILES[@]}
shopt -u nullglob

SELECTED_IMG=""

if [ "$NUM_FILES" -gt 0 ]; then
    # 场景 A: 有库存
    RAND_INDEX=$(( RANDOM % NUM_FILES ))
    SELECTED_IMG="${FILES[$RAND_INDEX]}"
    
    # 后台补货
    background_job >/dev/null 2>&1 &
    
else
    # 场景 B: 没库存
    # echo "库存为空，正在获取新图..."
    download_one_image
    
    shopt -s nullglob
    FILES=("$CACHE_DIR"/*.jpg)
    shopt -u nullglob
    
    if [ ${#FILES[@]} -gt 0 ]; then
        SELECTED_IMG="${FILES[0]}"
        background_job >/dev/null 2>&1 &
    fi
fi

# 运行 Fastfetch
# 注意这里使用了处理过的 ARGS_FOR_FASTFETCH 数组
if [ -n "$SELECTED_IMG" ] && [ -f "$SELECTED_IMG" ]; then
    fastfetch --logo "$SELECTED_IMG" --logo-preserve-aspect-ratio true "${ARGS_FOR_FASTFETCH[@]}"
    
    # 阅后即焚
    rm -f "$SELECTED_IMG"
else
    # echo "获取失败，使用默认 Logo"
    fastfetch "${ARGS_FOR_FASTFETCH[@]}"
fi
