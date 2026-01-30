#!/bin/bash

# ================= 配置区域 =================
bar="▁▂▃▄▅▆▇█"
bar_count=10
config_file="/tmp/waybar_cava_config"

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

# 生成静止时的"直线"
empty_char="${bar:0:1}"
empty_line=""
for ((j=0; j<bar_count; j++)); do empty_line="${empty_line}${empty_char}"; done

# ================= 3. 控制逻辑 =================
cava_pid=""

cleanup() {
    # 退出脚本时确保杀掉 cava
    [ -n "$cava_pid" ] && kill $cava_pid 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

# ================= 4. 主循环 =================
while true; do
    # === 终极检测逻辑 (保持不变) ===
    # 1. 检查 PulseAudio/PipeWire SINK 状态 (强制英文)
    is_running=$(LC_ALL=C pactl list sinks 2>/dev/null | grep -c "State: RUNNING")
    
    # 2. 如果 pactl 没检测到，检查 ALSA 内核状态 (双保险)
    if [ "$is_running" -eq 0 ]; then
        if grep -q "RUNNING" /proc/asound/card*/pcm*/sub*/status 2>/dev/null; then
            is_running=1
        fi
    fi

    if [ "$is_running" -gt 0 ]; then
        # --- [有声音] ---
        
        # 如果 cava 没在运行，赶紧启动它
        if [ -z "$cava_pid" ]; then
            cava -p "$config_file" | sed -u "$dict" &
            cava_pid=$!
        fi
        
        # 守护逻辑：如果进程意外死了(比如切歌时崩溃)，清除 PID 以便下次循环重启
        if ! kill -0 $cava_pid 2>/dev/null; then
            cava_pid=""
        fi
        
        # 运行中，每秒检查一次状态即可
        sleep 1

    else
        # --- [无声音] ---
        
        # 如果 cava 还在跑，杀无赦！(释放内存)
        if [ -n "$cava_pid" ]; then
            kill $cava_pid 2>/dev/null
            cava_pid=""
        fi
        
        # 此时 cava 死了，脚本接管输出，打印静止线条保持 Waybar 模块显示
        echo "$empty_line"
        
        # 没声音时脚本进入深睡眠，不仅 0 内存占用(cava)，脚本自身也几乎 0 CPU
        sleep 2
    fi
done
