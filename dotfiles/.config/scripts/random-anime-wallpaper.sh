#!/bin/bash

# 配置
API_URL="https://t.alcy.cc/pc/"
SAVE_DIR="$HOME/Pictures/Wallpapers/api-random-download"
RAW_FILENAME="wall_$(date +%s).jpg"
RAW_PATH="${SAVE_DIR}/${RAW_FILENAME}"
UPSCALE_THRESHOLD=2500 

mkdir -p "$SAVE_DIR"

# 1. 启动循环通知 (后台进程)
# 逻辑：先睡8秒，如果下载还没完，就发通知，然后循环
(
    sleep 8
    while true; do
        notify-send "Wallpaper" "Downloading is still in progress..." --expire-time=5000 --icon=drive-harddisk
        sleep 8
    done
) &
NOTIFY_PID=$!

# 2. 执行下载 (主进程)
notify-send "Wallpaper" "Downloading from Alcy..." --expire-time=5000
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# 执行 curl
curl -L -s -A "$USER_AGENT" --connect-timeout 10 -m 120 -o "$RAW_PATH" "$API_URL"
DOWNLOAD_EXIT_CODE=$?

# 3. 下载结束，立即杀死循环通知进程
kill "$NOTIFY_PID" 2>/dev/null
wait "$NOTIFY_PID" 2>/dev/null

# 4. 检查下载结果
if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
    notify-send "Wallpaper Error" "Download failed (Network/API Error)" --urgency=critical
    exit 1
fi

# 5. 校验文件
if [ ! -f "$RAW_PATH" ] || [ "$(wc -c < "$RAW_PATH")" -lt 20480 ]; then
    notify-send "Wallpaper Error" "Download failed (File too small/Invalid)" --urgency=critical
    rm -f "$RAW_PATH"
    exit 1
fi

FILE_TYPE=$(file --mime-type -b "$RAW_PATH")
if [[ "$FILE_TYPE" != image/* ]]; then
    notify-send "Wallpaper Error" "Not an image file ($FILE_TYPE)" --urgency=critical
    rm -f "$RAW_PATH"
    exit 1
fi

# 6. 智能超分处理
IMG_WIDTH=0
if command -v identify &> /dev/null; then
    IMG_WIDTH=$(identify -format "%w" "$RAW_PATH")
fi

if [ "$IMG_WIDTH" -gt 0 ] && [ "$IMG_WIDTH" -lt "$UPSCALE_THRESHOLD" ] && command -v waifu2x-ncnn-vulkan &> /dev/null; then
    notify-send "Wallpaper" "Upscaling image..." --expire-time=2000
    UPSCALED_PATH="${RAW_PATH%.*}.png"
    
    if waifu2x-ncnn-vulkan -i "$RAW_PATH" -o "$UPSCALED_PATH" -n 1 -s 2; then
        FINAL_PATH="$UPSCALED_PATH"
        MSG="Upscaled 2x (Was ${IMG_WIDTH}px)"
        rm "$RAW_PATH"
    else
        FINAL_PATH="$RAW_PATH"
        MSG="Upscale failed, used original"
    fi
else
    FINAL_PATH="$RAW_PATH"
    MSG="Original Image (${IMG_WIDTH}px)"
fi

# 7. 应用
swww img "$FINAL_PATH" --transition-duration 2 --transition-type center --transition-fps 60

# 后台执行 hooks
(
    [ -x "$HOME/.config/scripts/matugen-update.sh" ] && "$HOME/.config/scripts/matugen-update.sh" "$FINAL_PATH"
    sleep 0.5
    [ -x "$HOME/.config/scripts/niri_set_overview_blur_dark_bg.sh" ] && "$HOME/.config/scripts/niri_set_overview_blur_dark_bg.sh"
    # 清理旧文件
    cd "$SAVE_DIR" && ls -t | tail -n +11 | xargs -I {} rm -- {} 2>/dev/null
) &

notify-send "Wallpaper Updated" "$MSG"
