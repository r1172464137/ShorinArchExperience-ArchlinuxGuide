#!/bin/bash

# ==============================================================================
# 1. 用户配置 (User Configuration)
# ==============================================================================

# --- 核心设置 ---
# 选择你的壁纸后端: "awww", "swww", "swaybg", "hyprpaper"
WALLPAPER_BACKEND="swww -n overview"

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

# --- 自动预生成配置（新增） ---
AUTO_PREGEN="true"               # true/false：是否在调用时预生成目录内其它壁纸的 blur 缓存
WALL_DIR=""                       # 默认空 -> 会使用 INPUT_FILE 所在目录；若想指定全局目录可设置此变量

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
if [ -z "$INPUT_FILE" ]; then
    case "$WALLPAPER_BACKEND" in
        swww|awww)
            if command -v swww &> /dev/null; then
                INPUT_FILE=$(swww query 2>/dev/null | head -n1 | grep -oP 'image: \K.*')
            fi
            ;;
        hyprpaper)
            INPUT_FILE=$(hyprctl hyprpaper listactive 2>/dev/null | head -n1 | awk '{print $3}')
            ;;
        *)
            ;;
    esac
fi

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    notify-send "Blur Error" "无法获取输入图片，请手动指定路径。"
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
        echo "警告: $SYMLINK_PATH 是一个真实目录，跳过创建链接。"
    else
        echo "🔗 创建/修复目录链接: $SYMLINK_PATH -> $REAL_CACHE_DIR"
        ln -sfn "$REAL_CACHE_DIR" "$SYMLINK_PATH"
    fi
fi

# C. 定义文件名 (核心修复: 将参数写入文件名)
FILENAME=$(basename "$INPUT_FILE")

# 处理参数中的特殊字符，防止文件名非法
# 去掉 % 号
SAFE_OPACITY="${IMG_COLORIZE_STRENGTH%\%}"
# 去掉 # 号 (如果颜色写的是 #000000)
SAFE_COLOR="${IMG_FILL_COLOR#\#}"

# 构造唯一前缀: blur-[强度]-[颜色]-[浓度]-
PARAM_PREFIX="blur-${IMG_BLUR_STRENGTH}-${SAFE_COLOR}-${SAFE_OPACITY}-"

BLUR_FILENAME="${PARAM_PREFIX}${FILENAME}"
FINAL_IMG_PATH="$REAL_CACHE_DIR/$BLUR_FILENAME"

# ==============================================================================
# 4. 预生成功能（新增函数：优先当前，其余后台生成）
# ==============================================================================
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# 根据原有参数构造某张图片的目标缓存路径（复用）
target_for() {
    local img="$1"
    local base="${img##*/}"
    echo "$REAL_CACHE_DIR/${PARAM_PREFIX}${base}"
}

# 后台生成函数（跳过 current）
pregen_other_in_background() {
    local current_img="$1"
    log "PreGen (bg): 在目录 $WALL_DIR 中异步生成其余图片的缓存（跳过当前）"

    (
        local total=0
        local done=0
        while IFS= read -r -d '' img; do
            # 仅处理文件
            # 跳过当前图片本体
            [[ -n "$current_img" && "$img" == "$current_img" ]] && continue

            total=$((total + 1))
            local tgt
            tgt=$(target_for "$img")

            if [[ -f "$tgt" ]]; then
                log "PreGen (bg): Skip (exists) -> ${img##*/}"
                continue
            fi

            log "PreGen (bg): Generating -> ${img##*/}"
            if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
                magick "$img" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$tgt"
            else
                magick "$img" -blur "$IMG_BLUR_STRENGTH" "$tgt"
            fi

            if [[ $? -eq 0 ]]; then
                done=$((done + 1))
            else
                log "PreGen (bg): 生成失败 -> ${img##*/}"
            fi
        done < <(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

        log "PreGen (bg): 完成，扫描 $total 个文件，新增 $done 个缓存。"
    ) &  # 整个循环在后台运行
}

# ==============================================================================
# 5. 生成或命中当前图片的 blur，并应用；其余异步生成
# ==============================================================================

# 若已经存在对应缓存 -> 立即应用并在后台继续预生成其它
if [ -f "$FINAL_IMG_PATH" ]; then
    echo "✅ 缓存命中: $FINAL_IMG_PATH"
    log "当前壁纸已有缓存 -> 立即应用并在后台预生成其它"
    # 立即应用（异步以不阻塞）
    case "$WALLPAPER_BACKEND" in
        awww)
            awww img "$FINAL_IMG_PATH" --transition-type fade --transition-duration 0.5 &
            ;;
        swww)
            swww img "$FINAL_IMG_PATH" --transition-type fade --transition-duration 0.5 &
            ;;
        swaybg)
            pkill swaybg 2>/dev/null
            swaybg -m fill -i "$FINAL_IMG_PATH" &
            ;;
        hyprpaper)
            hyprctl hyprpaper preload "$FINAL_IMG_PATH"
            hyprctl hyprpaper wallpaper ",$FINAL_IMG_PATH"
            ;;
        *)
            notify-send "Blur Error" "未知的后端: $WALLPAPER_BACKEND"
            exit 1
            ;;
    esac

    # 根据配置在后台生成其它缓存
    if [[ "$AUTO_PREGEN" == "true" ]]; then
        pregen_other_in_background "$INPUT_FILE"
    fi

    echo "完成。"
    exit 0
fi

# 若没有缓存 -> 先为当前生成并应用（同步生成以保证切换即时），再后台生成其它
echo "⚡ 当前无缓存，正在生成当前壁纸的 blur (参数: $IMG_BLUR_STRENGTH / $IMG_FILL_COLOR / $IMG_COLORIZE_STRENGTH)..."
if [[ -n "$IMG_FILL_COLOR" && -n "$IMG_COLORIZE_STRENGTH" ]]; then
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" -fill "$IMG_FILL_COLOR" -colorize "$IMG_COLORIZE_STRENGTH" "$FINAL_IMG_PATH"
else
    magick "$INPUT_FILE" -blur "$IMG_BLUR_STRENGTH" "$FINAL_IMG_PATH"
fi

if [ $? -ne 0 ]; then
    notify-send "Blur Error" "ImageMagick 生成失败"
    exit 1
fi

# 同步生成成功 -> 立即应用（不放后台，以保证用户界面切换稳定）
echo "应用背景 ($WALLPAPER_BACKEND)..."
case "$WALLPAPER_BACKEND" in
    awww)
        awww img "$FINAL_IMG_PATH" --transition-type fade --transition-duration 0.5
        ;;
    swww)
        swww img "$FINAL_IMG_PATH" --transition-type fade --transition-duration 0.5
        ;;
    swaybg)
        pkill swaybg 2>/dev/null
        swaybg -m fill -i "$FINAL_IMG_PATH" &
        ;;
    hyprpaper)
        hyprctl hyprpaper preload "$FINAL_IMG_PATH"
        hyprctl hyprpaper wallpaper ",$FINAL_IMG_PATH"
        ;;
    *)
        notify-send "Blur Error" "未知的后端: $WALLPAPER_BACKEND"
        exit 1
        ;;
esac

# 若配置允许 -> 在后台生成其它
if [[ "$AUTO_PREGEN" == "true" ]]; then
    pregen_other_in_background "$INPUT_FILE"
fi

echo "完成。"
exit 0
