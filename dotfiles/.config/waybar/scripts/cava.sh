#!/bin/bash

# ================= 配置区域 =================
bar="▁▂▃▄▅▆▇█"
bar_count=10
config_file="/tmp/waybar_cava_config"
cava_pid=""

# ================= 1. 生成配置 =================
echo "
[general]
framerate = 24
bars = $bar_count
[input]
method = pulse
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
" > "$config_file"

# ================= 2. 准备字符串 =================
dict="s/;//g;"
i=0
while [ $i -lt ${#bar} ]; do
    dict="${dict}s/$i/${bar:$i:1}/g;"
    i=$((i=i+1))
done

empty_char="${bar:0:1}"
empty_line=""
for ((j=0; j<bar_count; j++)); do empty_line="${empty_line}${empty_char}"; done

# ================= 3. 清理函数 =================
cleanup() {
    [ -n "$cava_pid" ] && kill $cava_pid 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

# ================= 4. 主循环 =================
while true; do
    # === 核心修改 ===
    # 不再检测 sink-inputs (输入流)，改为检测 sinks (输出设备)
    # 只要有任何一个输出设备处于 RUNNING 状态，就认为有声音
    # 这几乎能捕获所有类型的音频活动 (ALSA, PipeWire, Pulse)
    
    # 1. 尝试用 pactl 检测 Sink 状态 (强制英文环境)
    playing=$(LC_ALL=C pactl list sinks 2>/dev/null | grep -c "State: RUNNING")
    
    # 2. 如果 pactl 完全失效 (极少数情况)，尝试检查 /proc/asound (ALSA底层状态)
    # 如果 playing 还是 0，我们多做这一步保险
    if [ "$playing" -eq 0 ]; then
        if grep -q "RUNNING" /proc/asound/card*/pcm*/sub*/status 2>/dev/null; then
            playing=1
        fi
    fi

    if [ "$playing" -gt 0 ]; then
        # --- [有声音] ---
        if [ -z "$cava_pid" ]; then
            cava -p "$config_file" | sed -u "$dict" &
            cava_pid=$!
        fi
        sleep 1 
        if ! kill -0 $cava_pid 2>/dev/null; then
            cava_pid=""
        fi
    else
        # --- [无声音] ---
        if [ -n "$cava_pid" ]; then
            kill $cava_pid 2>/dev/null
            cava_pid=""
        fi
        echo "$empty_line"
        sleep 2
    fi
done
