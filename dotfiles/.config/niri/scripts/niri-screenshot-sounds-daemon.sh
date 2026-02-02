#!/bin/bash
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
