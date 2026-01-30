#!/bin/bash

# ================= 配置区域 =================
bar="▁▂▃▄▅▆▇█"
bar_count=10
config_file="/tmp/waybar_cava_config"
# 退出延迟 (秒)
SHUTDOWN_DELAY=10
# 调试日志 (排错用，确认问题后可设为空 /dev/null)
DEBUG_LOG="/tmp/cava_debug.log"

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

# ================= 3. 辅助函数 =================
log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$DEBUG_LOG"
}

# 彻底清理函数
cleanup() {
    # 查找并杀掉当前脚本下的所有 cava 子进程
    # pgrep -P $$ -x cava : 查找父进程是当前脚本($$)，且名字叫 cava 的进程
    cava_pids=$(pgrep -P $$ -x cava)
    if [ -n "$cava_pids" ]; then
        kill $cava_pids 2>/dev/null
    fi
    exit 0
}
trap cleanup EXIT INT TERM

# 检测函数 (PipeWire Python 解析)
check_audio_playing() {
    if command -v pw-dump >/dev/null; then
        pw-dump Node 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    count = 0
    for obj in data:
        if obj.get('type') != 'PipeWire:Interface:Node': continue
        info = obj.get('info', {})
        props = info.get('props', {})
        
        # 必须是 running 状态
        if info.get('state') != 'running': continue
        
        # 必须是播放流 (Stream/Output/Audio)
        # 排除 Cava 自身的 Stream/Input/Audio
        if props.get('media.class') == 'Stream/Output/Audio':
            count += 1
    print(count)
except:
    print(0)
"
    else
        # 降级方案
        LC_ALL=C pactl list sink-inputs 2>/dev/null | grep -ic "state: running"
    fi
}

# ================= 4. 主循环 =================
log "脚本启动，PID: $$"
silence_timer=0

while true; do
    # 1. 获取活跃音源数量
    active_sources=$(check_audio_playing)
    
    # 2. 检查 cava 进程是否存在
    # pgrep -P $$ -x cava 才是真正的 cava 进程 ID
    real_cava_pid=$(pgrep -P $$ -x cava | head -n 1)

    if [ "$active_sources" -gt 0 ]; then
        # --- [有声音] ---
        silence_timer=0
        
        if [ -z "$real_cava_pid" ]; then
            log "检测到声音 (源数量: $active_sources)，启动 Cava..."
            # 启动管道
            cava -p "$config_file" | sed -u "$dict" &
        fi
        
        # 有声音时检测频率
        sleep 1

    else
        # --- [无声音] ---
        if [ -n "$real_cava_pid" ]; then
            # Cava 活着，但没声音了 -> 倒计时
            silence_timer=$((silence_timer + 1))
            
            # log "静音倒计时: $silence_timer / $SHUTDOWN_DELAY" # (调试时可打开，平时太吵)
            
            if [ "$silence_timer" -ge "$SHUTDOWN_DELAY" ]; then
                log "超时 $SHUTDOWN_DELAY 秒无声音，关闭 Cava (PID: $real_cava_pid)"
                
                # === 核心修改：精准击杀 ===
                kill $real_cava_pid 2>/dev/null
                
                # 双重保险：杀掉所有子进程 (包括 sed)
                pkill -P $$ 
                
                # 杀完输出一条线
                echo "$empty_line"
            else
                # 还没到时间，什么都不做，Cava 继续跑
                :
            fi
        else
            # Cava 已经死了，输出静态占位
            echo "$empty_line"
        fi
        
        # 休眠策略
        if [ -n "$real_cava_pid" ]; then
            sleep 1
        else
            sleep 0.5
        fi
    fi
done
