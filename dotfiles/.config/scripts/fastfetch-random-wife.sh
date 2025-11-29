#!/bin/bash

# --- 1. 配置区域 ---
CACHE_DIR="$HOME/.cache/fastfetch_waifu"
# 确保缓存目录存在
mkdir -p "$CACHE_DIR"

# --- 2. 核心函数定义 ---

# 函数：获取一个随机的图片 URL
get_random_url() {
    RAND=$(( ( RANDOM % 3 ) + 1 ))
    case $RAND in
        1) curl -s "https://api.waifu.im/search?included_tags=waifu&is_nsfw=false" | jq -r '.images[0].url' ;;
        2) curl -s "https://nekos.best/api/v2/waifu" | jq -r '.results[0].url' ;;
        3) curl -s "https://api.waifu.pics/sfw/waifu" | jq -r '.url' ;;
    esac
}

# 函数：下载一张图片到缓存目录
# 参数 $1: 是否是“急用”模式（如果是急用，文件名会有特殊标记，虽然这里统一处理即可）
download_one_image() {
    URL=$(get_random_url)
    if [ -n "$URL" ] && [ "$URL" != "null" ]; then
        # 使用纳秒级时间戳作为文件名，确保绝对唯一
        FILENAME="waifu_$(date +%s%N)_$RANDOM.jpg"
        curl -s -L --max-time 10 -o "$CACHE_DIR/$FILENAME" "$URL"
    fi
}

# 函数：后台批量任务 (下载10张 + 清理旧文件)
background_job() {
    # 1. 批量下载 10 张
    for i in {1..10}; do
        download_one_image
        # 稍微间隔一下，避免瞬间把 API 刷爆被封 IP
        sleep 0.2
    done

    # 2. 清理旧文件 (如果超过 100 张)
    # ls -t 按时间排序(新到旧), tail -n +101 选出第101行之后的文件(即最旧的), xargs rm 删除
    FILE_COUNT=$(ls -1 "$CACHE_DIR" | wc -l)
    if [ "$FILE_COUNT" -gt 100 ]; then
        ls -tp "$CACHE_DIR" | grep -v '/$' | tail -n +101 | xargs -I {} rm -- "$CACHE_DIR/{}"
    fi
}

# --- 3. 主程序逻辑 ---

# 步骤 A: 检查缓存库存
# 查找目录下所有的 jpg/png/webp 文件
FILES=("$CACHE_DIR"/*)
NUM_FILES=${#FILES[@]}

SELECTED_IMG=""

# 步骤 B: 决定显示哪张图
if [ "$NUM_FILES" -gt 0 ] && [ -f "${FILES[0]}" ]; then
    # === 场景 1: 有库存 (秒开) ===
    
    # 随机选择一个索引
    RAND_INDEX=$(( RANDOM % NUM_FILES ))
    SELECTED_IMG="${FILES[$RAND_INDEX]}"
    
    # 触发后台下载任务 (静默运行，不阻塞当前终端)
    ( background_job ) >/dev/null 2>&1 &
    
else
    # === 场景 2: 没库存 (第一次运行) ===
    echo "库存为空，正在紧急获取第一张图片..."
    
    # 同步下载一张急用
    download_one_image
    
    # 重新获取刚才下载的文件
    FILES=("$CACHE_DIR"/*)
    if [ ${#FILES[@]} -gt 0 ]; then
        SELECTED_IMG="${FILES[0]}"
    fi
    
    # 既然已经下载了1张，后台只需再补9张即可(为了逻辑简单，还是下10张也没事)
    ( background_job ) >/dev/null 2>&1 &
fi

# 步骤 C: 运行 Fastfetch
if [ -n "$SELECTED_IMG" ] && [ -f "$SELECTED_IMG" ]; then
    # 运行 fastfetch
    fastfetch --logo "$SELECTED_IMG" --logo-preserve-aspect-ratio true "$@"
    
    # 步骤 D: 阅后即焚 (避免重复)
    rm -f "$SELECTED_IMG"
else
    echo "图片获取失败，使用默认 Logo"
    fastfetch "$@"
fi