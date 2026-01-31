#!/bin/bash

# ================= 配置区域 =================
# 默认显示字符 (8个字符，对应 0-7 强度)
DEFAULT_BAR_CHARS="▁▂▃▄▅▆▇█"
# 条形数量
BAR_COUNT=10
# 配置文件位置
CONFIG_FILE="/tmp/waybar_cava_config"
# 音乐停止后多少秒关闭 Cava
SHUTDOWN_DELAY=5

# ================= 参数解析 =================
usage() {
    echo "Usage: $(basename $0) [OPTIONS]"
    exit 0
}
bar_chars="$DEFAULT_BAR_CHARS"
while getopts "b:c:d:h" opt; do
    case $opt in
        b) bar_chars="$OPTARG" ;;
        c) BAR_COUNT="$OPTARG" ;;
        d) SHUTDOWN_DELAY="$OPTARG" ;;
        h) usage ;;
        ?) usage ;;
    esac
done

# ================= 1. 生成配置 =================
max_range=$((${#bar_chars} - 1))
sed_dict="s/;//g;"
for ((i=0; i<=${max_range}; i++)); do
    char="${bar_chars:$i:1}"
    sed_dict="${sed_dict}s/$i/${char}/g;"
done

# 预生成空行字符串
empty_char="${bar_chars:0:1}"
empty_line=""
for ((j=0; j<BAR_COUNT; j++)); do empty_line="${empty_line}${empty_char}"; done

# 生成 Cava 配置
cat > "$CONFIG_FILE" <<EOF
[general]
framerate = 30
bars = $BAR_COUNT
[input]
method = pulse
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = $max_range
EOF

# ================= 2. 核心函数 =================

# 检查音频播放状态 (基于 PipeWire)
# 返回: 正在播放的音频流数量 (int)
check_audio_playing() {
    # 只要有任何 Stream/Output/Audio 处于 running 状态，就算有声音
    # 忽略 Cava 自身的 Stream/Input 录音流
    pw-dump Node 2>/dev/null | jq -r '
        [ .[] | select(
            .type == "PipeWire:Interface:Node" and
            .info.state == "running" and
            .info.props["media.class"] == "Stream/Output/Audio"
        ) ] | length
    '
}

# 阻塞等待音频事件 (CPU 0% 占用)
wait_for_audio_event() {
    # 监听 sink-input 事件，只要有变化就立即退出阻塞
    # 加 timeout 防止极端情况下死锁
    timeout 60s pactl subscribe 2>/dev/null | grep --line-buffered "sink-input" | head -n 1 >/dev/null
}

cleanup() {
    pkill -P $$ -x cava 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

# ================= 3. 主循环 =================
# 输出一行空行防止 Waybar 模块消失
echo "$empty_line"

trigger_check=true
silence_timer=0

while true; do
    if [ "$trigger_check" = true ]; then
        active_sources=$(check_audio_playing)
        # 容错：如果 jq 失败，active_sources 为空则视为 0
        [[ -z "$active_sources" ]] && active_sources=0
        
        cava_pid=$(pgrep -P $$ -x cava | head -n 1)

        if [ "$active_sources" -gt 0 ]; then
            # --- [有声音] ---
            silence_timer=0
            if [ -z "$cava_pid" ]; then
                # 启动 Cava
                # 2>/dev/null 屏蔽 cava 的启动日志，只保留 stdout 给 Waybar
                cava -p "$CONFIG_FILE" 2>/dev/null | sed -u "$sed_dict" &
                # 给一点点缓冲时间
                sleep 0.2
            fi
            
            # 播放期间每 2 秒检查一次状态
            sleep 2
            # 保持 trigger_check 为 true 以便循环继续
            trigger_check=true 
            
        else
            # --- [无声音] ---
            if [ -n "$cava_pid" ]; then
                # 还有 Cava 进程 -> 倒计时
                silence_timer=$((silence_timer + 1))
                
                if [ "$silence_timer" -ge "$SHUTDOWN_DELAY" ]; then
                    # 超时：关闭 Cava
                    kill "$cava_pid" 2>/dev/null
                    wait "$cava_pid" 2>/dev/null
                    # 输出空行清屏
                    echo "$empty_line"
                else
                    # 还没超时，继续轮询
                    sleep 1
                    trigger_check=true
                    continue 
                fi
            fi

            # --- [深度休眠] ---
            # 确保 Cava 已死且无声音，进入事件监听模式
            if [ -z "$(pgrep -P $$ -x cava)" ]; then
                # 这里会阻塞，直到你有动作（比如打开网易云）
                wait_for_audio_event
                # 被唤醒后，强制检查一次
                trigger_check=true
                silence_timer=0
            fi
        fi
    fi
done
