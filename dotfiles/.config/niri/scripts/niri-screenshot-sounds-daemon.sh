#!/bin/bash
until wl-paste --list-types >/dev/null 2>&1; do
    sleep 0.5
done

# 2. (可选) 等待音频服务 (PipeWire) 就绪
# 检查 pw-play 命令是否存在且能运行
if command -v pw-play >/dev/null; then
    until pw-play --help >/dev/null 2>&1; do
        sleep 0.5
    done
fi
SOUND="/usr/share/sounds/freedesktop/stereo/camera-shutter.oga"
TOKEN="/dev/shm/niri_screenshot_active"

# 监听剪贴板变化
wl-paste --watch bash -c "
    # 核心优化：利用 find 的 -mmin 参数
    # 如果令牌文件存在，且修改时间在 0.15 分钟（约9秒）以内
    if [ -n \"\$(find \"$TOKEN\" -mmin -0.15 2>/dev/null)\" ]; then
        
        # 检查是否是图片
        if wl-paste --list-types | grep -q 'image/'; then
            pw-play \"$SOUND\" &
            rm -f \"$TOKEN\"
        fi
    fi
"
