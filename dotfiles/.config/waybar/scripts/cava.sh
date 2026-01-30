#!/bin/bash

# ================= 配置区域 =================
bar="▁▂▃▄▅▆▇█"
bar_count=10
config_file="/tmp/waybar_cava_config"
# 退出延迟 (秒)
SHUTDOWN_DELAY=10

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

# ================= 3. 检测函数 (核心修改) =================
# 使用 PipeWire 原生工具 + Python 精确解析
# 相比 grep，这能完美区分"播放流"和"录音流"
check_audio_playing() {
    if command -v pw-dump >/dev/null; then
        # 获取所有 Node 信息，交给 Python 筛选
        pw-dump Node 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = 0
    for obj in data:
        # 必须是 Node 类型
        if obj.get('type') != 'PipeWire:Interface:Node': continue
        
        info = obj.get('info', {})
        props = info.get('props', {})
        
        # 核心判断 1: 状态必须是 running
        if info.get('state') != 'running': continue
        
        # 核心判断 2: 必须是'播放流' (Stream/Output/Audio)
        # Cava 属于'录音流' (Stream/Input/Audio)，会被这里排除 -> 解决死循环！
        if props.get('media.class') == 'Stream/Output/Audio':
            count += 1
            
    print(count)
except:
    print(0)
"
    else
        # 降级方案 (如果系统真的没装 pw-dump，虽然不太可能)
        LC_ALL=C pactl list sink-inputs 2>/dev/null | grep -ic "state: running"
    fi
}

# ================= 4. 控制循环 =================
cava_pipe_pid=""
silence_timer=0

cleanup() {
    [ -n "$cava_pipe_pid" ] && kill $cava_pipe_pid 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    # 执行检测
    active_sources=$(check_audio_playing)

    if [ "$active_sources" -gt 0 ]; then
        # --- [有声音] ---
        silence_timer=0
        
        if [ -z "$cava_pipe_pid" ]; then
            cava -p "$config_file" | sed -u "$dict" &
            cava_pipe_pid=$!
        fi
        
        if ! kill -0 $cava_pipe_pid 2>/dev/null; then
            cava_pipe_pid=""
        fi
        
        # 有声音时，1秒查一次足够了
        sleep 1

    else
        # --- [无声音] ---
        if [ -n "$cava_pipe_pid" ]; then
            # 进入倒计时
            silence_timer=$((silence_timer + 1))
            
            if [ "$silence_timer" -ge "$SHUTDOWN_DELAY" ]; then
                # 时间到，杀进程
                kill $cava_pipe_pid 2>/dev/null
                cava_pipe_pid=""
                echo "$empty_line"
            else
                # 冷却中，保持运行
                :
            fi
        else
            echo "$empty_line"
        fi
        
        # 动态休眠
        if [ -n "$cava_pipe_pid" ]; then
            sleep 1
        else
            # 纯待机时加快检测，降低启动延迟
            sleep 0.5
        fi
    fi
done
