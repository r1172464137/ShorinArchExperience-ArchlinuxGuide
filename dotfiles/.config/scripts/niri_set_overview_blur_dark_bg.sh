#!/bin/bash

# ==============================================================================
# 1. 用户配置 (User Configuration)
# ==============================================================================

# --- 核心设置 ---
# 后端命令 (仅支持 swww 或 awww)
# 注意：这里只写命令名，不要带参数
WALLPAPER_BACKEND="swww"

# swww/awww 的额外参数 (指定 namespace)
# 这将确保壁纸只会被设置到 'overview' 这个 daemon 实例上
DAEMON_ARGS="-n overview"

# --- ImageMagick 参数 ---
# 修改这些参数后，脚本会自动生成新的缓存文件
IMG_BLUR_STRENGTH="0x15"
IMG_FILL_COLOR="black"
IMG_COLORIZE_STRENGTH="40%"

# --- 路径配置 ---
# 真实文件存放的缓存总目录
REAL_CACHE_BASE="$HOME/.cache/blur-wallpapers"

# 真实缓存的子目录名
CACHE_SUBDIR_NAME="niri-overview-blur-dark"

# 在壁纸目录下显示的链接名 (加上 cache- 前缀)
LINK_NAME="cache-niri-overview-blur-dark"

# --- 自动预生成配置 ---
AUTO_PREGEN="true"               # true/false：是否在调用时预生成目录内其它壁纸的 blur 缓存
WALL_DIR=""                      # 默认空 -> 会使用 INPUT_FILE 所在目录；若想指定全局目录可设置此变量

# ==============================================================================
# 2. 依赖与输入检查
# ==============================================================================

DEPENDENCIES=("magick" "notify-send" "$WALLPAPER_BACKEND")

for cmd in "${DEPENDENCIES[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        notify-send -u critical "Blur Error" "缺少依赖: $cmd"
        exit 1
    fi
done

INPUT_FILE="$1"

# 自动获取当前壁纸（若未指定）
# 逻辑：从 *主* swww 实例获取当前清晰壁纸，以便生成模糊版本
if [ -z "$INPUT_FILE" ]; then
    if command -v "$WALLPAPER_BACKEND" &> /dev/null; then
        # 注意：这里不加 -n overview，因为我们需要读取的是"主桌面"的原始壁纸
        INPUT_FILE=$("$WALLPAPER_BACKEND" query 2>/dev/null | head -n1 | grep -oP 'image: \K.*')
    fi
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    notify-send "Blur Error" "无法获取输入图片 (swww query 无返回)，请手动指定路径。"
    exit 1
fi

# 如果用户未手动设置 WALL_DIR，则使用 INPUT_FILE 所在目录
if [ -z "$WALL_DIR" ]; then
    WALL_DIR=$(dirname "$INPUT_FILE")
fi

# ==============================================================================
# 3. 路径与链接逻辑
# ==============================================================================

# A. 准备真实缓存目录
REAL_CACHE_DIR="$REAL_CACHE_BASE/$CACHE_SUBDIR_NAME"
mkdir -p "$REAL_CACHE_DIR"

# B. 准备软链接 (文件夹级链接)
WALLPAPER_DIR=$(dirname "$INPUT_FILE")
SYMLINK_PATH="$WALLPAPER_DIR/$LINK_NAME"

# 检查并创建/修复软链接
if [ ! -L "$SYMLINK_PATH" ] || [ "$(readlink -f "$SYMLINK_PATH")" != "$REAL_CACHE_DIR" ]; then
    if [ -d "$SYMLINK_PATH" ] && [ ! -L "$SYMLINK_PATH" ]; then
        # 避免噪音，静默处理或仅调试输出
        : 
    else
        # echo "🔗 创建/修复目录链接: $SYMLINK_PATH -> $REAL_CACHE_DIR"
        ln -sfn "$REAL_CACHE_DIR" "$SYMLINK_PATH"
    fi
fi

# C. 定义文件名
FILENAME=$(basename "$INPUT_FILE")

# 处理参数中的特殊字符
SAFE_OPACITY="${IMG_COLORIZE_STRENGTH%\%}"
SAFE_COLOR="${IMG_FILL_COLOR#\#}"

# 构造唯一前缀
PARAM_PREFIX="blur-${IMG_BLUR_STRENGTH}-${SAFE_COLOR}-${SAFE_OPACITY}-"

BLUR_FILENAME="${PARAM_PREFIX}${FILENAME}"
FINAL_IMG_PATH="$REAL_CACHE_DIR/$BLUR_FILENAME"

# ==============================================================================
# 4. 预生成功能
# ==============================================================================
log() { echo "[$(date '+%H:%M:%S')] $*"; }

target_for() {
    local img="$1"
    local base="${img##*/}"
    echo "$REAL_CACHE_DIR/${PARAM_PREFIX}${base}"
}

pregen_other_in_background() {
    local current_img="$1"
    # log "PreGen (bg): 在目录 $WALL_DIR 中异步生成其余图片的缓存"

    (
        local total=0
        local done=0
        while IFS= read -r -d '' img; do
            [[ -n "$current_img" && "$img" == "$current_img" ]] && continue
            
            total=$((total + 1))
            local tgt
            tgt=$(target_for "$img")

            if [[ -f "$tgt" ]]; then
                continue
            fi

            if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
                magick "$img" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$tgt"
            else
                magick "$img" -blur "$IMG_BLUR_STRENGTH" "$tgt"
            fi
        done < <(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)
    ) & 
}

# ==============================================================================
# 5. 生成与应用函数
# ==============================================================================

apply_wallpaper() {
    local img_path="$1"
    
    # 使用配置的 Backend 和 Args (swww/awww img -n overview ...)
    "$WALLPAPER_BACKEND" img $DAEMON_ARGS "$img_path" \
        --transition-type fade \
        --transition-duration 0.5 \
        &  # 放入后台执行以提高响应速度
}

# ==============================================================================
# 6. 主逻辑
# ==============================================================================

# 若缓存命中
if [ -f "$FINAL_IMG_PATH" ]; then
    echo "✅ 缓存命中: $FINAL_IMG_PATH"
    apply_wallpaper "$FINAL_IMG_PATH"

    if [[ "$AUTO_PREGEN" == "true" ]]; then
        pregen_other_in_background "$INPUT_FILE"
    fi
    exit 0
fi

# 若无缓存，生成当前壁纸
echo "⚡ 生成模糊壁纸..."
if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$FINAL_IMG_PATH"
else
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" "$FINAL_IMG_PATH"
fi

if [ $? -ne 0 ]; then
    notify-send "Blur Error" "ImageMagick 生成失败"
    exit 1
fi

# 应用壁纸
echo "应用背景 ($WALLPAPER_BACKEND $DAEMON_ARGS)..."
apply_wallpaper "$FINAL_IMG_PATH"

# 后台预生成其它
if [[ "$AUTO_PREGEN" == "true" ]]; then
    pregen_other_in_background "$INPUT_FILE"
fi

echo "完成。"
exit 0