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

empty_char="${bar:0:1}"
empty_line=""
for ((j=0; j<bar_count; j++)); do empty_line="${empty_line}${empty_char}"; done

# ================= 3. 控制逻辑 =================
cava_pid=""
current_state="running"

cleanup() {
    [ -n "$cava_pid" ] && kill -KILL $cava_pid 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

# 启动 cava
cava -p "$config_file" | sed -u "$dict" &
cava_pid=$!
sleep 0.5

# ================= 4. 主循环 =================
while true; do
    # === 终极检测逻辑 ===
    # 1. 优先检查 Pulse/PipeWire 的 SINK (硬件设备) 状态
    #    只要有声音，Sink 必须是 RUNNING。
    is_running=$(LC_ALL=C pactl list sinks 2>/dev/null | grep -c "State: RUNNING")
    
    # 2. 如果 pactl 说没声音，再查一次内核层面的声卡状态 (ALSA)
    #    这是最后的防线，除了蓝牙设备外，所有物理声卡都会在这里显示状态
    if [ "$is_running" -eq 0 ]; then
        if grep -q "RUNNING" /proc/asound/card*/pcm*/sub*/status 2>/dev/null; then
            is_running=1
        fi
    fi

    if [ "$is_running" -gt 0 ]; then
        # --- [有声音] ---
        if [ "$current_state" == "stopped" ]; then
            # 解冻进程 (SIGCONT)
            kill -CONT $cava_pid 2>/dev/null
            current_state="running"
        fi
        
        # 活体检测
        if ! kill -0 $cava_pid 2>/dev/null; then
            cava -p "$config_file" | sed -u "$dict" &
            cava_pid=$!
        fi
        
        # 稍微等待，减少检测频率
        sleep 1

    else
        # --- [无声音] ---
        if [ "$current_state" == "running" ]; then
            # 冻结进程 (SIGSTOP) -> CPU 0%
            kill -STOP $cava_pid 2>/dev/null
            current_state="stopped"
            
            # 只有在刚停下的时候输出一次直线
            echo "$empty_line"
        fi
        
        sleep 2
    fi
done
