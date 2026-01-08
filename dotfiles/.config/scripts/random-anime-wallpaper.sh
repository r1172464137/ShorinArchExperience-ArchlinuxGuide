#!/bin/bash

# ================= 配置部分 =================
# API 地址
API_URL="https://api.mtyqx.cn/tapi/random.php"

# 保存目录
SAVE_DIR="$HOME/Pictures/Wallpapers/api-random-download"

# 生成唯一文件名 (使用时间戳)，避免覆盖旧图片
# 如果你想每次覆盖同一张图，可以改为固定文件名，如 "current_wall.jpg"
IMAGE_NAME="wall_$(date +%s).jpg"
FULL_PATH="${SAVE_DIR}/${IMAGE_NAME}"

# ================= 逻辑部分 =================

# 1. 确保目录存在
if [ ! -d "$SAVE_DIR" ]; then
    mkdir -p "$SAVE_DIR"
    echo "已创建目录: $SAVE_DIR"
fi

# 2. 下载图片
# curl 参数说明:
# -L : 关键参数！因为这个 API 会返回 302 重定向到真实图片地址，必须跟随重定向。
# -o : 输出到指定文件
# -s : 静默模式，不显示进度条 (如果想看进度可以去掉 -s)
echo "正在从 API 下载随机图片..."

if notify-send "Downloading Wallpaper ..." && curl -L -s -o "$FULL_PATH" "$API_URL"; then
    echo "下载成功: $FULL_PATH"
    # 检查文件大小，避免下载到空文件或错误页面
    FILE_SIZE=$(du -k "$FULL_PATH" | cut -f1)
    if [ "$FILE_SIZE" -lt 10 ]; then
        echo "警告: 下载的文件过小，可能是 API 报错或网络问题，跳过切换。"
        rm "$FULL_PATH"
        exit 1
    fi

    # 3. 使用 swww 切换壁纸
    # 这里直接使用你要求的参数
    echo "正在切换壁纸..."
    swww img "$FULL_PATH" --transition-duration 2 --transition-type center --transition-fps 60
     ~/.config/scripts/matugen-update.sh "$FULL_PATH"
     sleep 1
     ~/.config/scripts/niri_set_overview_blur_dark_bg.sh
    # (可选) 清理旧壁纸，只保留最近 10 张，防止硬盘塞满
     cd "$SAVE_DIR" && ls -t | tail -n +11 | xargs -I {} rm -- {} 2>/dev/null

else
    echo "下载失败，请检查网络连接。"
    exit 1
fi
