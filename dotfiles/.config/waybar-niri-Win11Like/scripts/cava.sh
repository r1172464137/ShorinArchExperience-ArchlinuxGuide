#!/bin/bash

#==== 配置 ====
# Bar的样式
DEFAULT_BAR_CHARS="▁▂▃▄▅▆▇█"
# Bar的宽度
BAR_COUNT=10
CONFIG_FILE="/tmp/waybar_cava_config"
# 闲置多少秒退出cava
SHUTDOWN_DELAY=3

usage() {
    echo "Usage: $(basename $0) [-b chars] [-c count] [-d delay]"
    exit 0
}

bar_chars="$DEFAULT_BAR_CHARS"
while getopts "b:c:d:h" opt; do
    case $opt in
        b) bar_chars="$OPTARG" ;;
        c) BAR_COUNT="$OPTARG" ;;
        d) SHUTDOWN_DELAY="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# 初始化
max_range=$((${#bar_chars} - 1))
sed_dict="s/;//g;"
for ((i=0; i<=${max_range}; i++)); do
    sed_dict="${sed_dict}s/$i/${bar_chars:$i:1}/g;"
done

idle_char="${bar_chars:0:1}"
idle_output=$(printf "%0.s$idle_char" $(seq 1 $BAR_COUNT))

cat > "$CONFIG_FILE" <<EOF
[general]
framerate = 30
bars = $BAR_COUNT
[input]
method = pulse
source = auto
[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = $max_range
EOF

cleanup() {
    trap - EXIT INT TERM
    pkill -P $$ 2>/dev/null
    echo "$idle_output"
    exit 0
}
trap cleanup EXIT INT TERM

check_audio_playing() {
    count=$(pw-dump Node 2>/dev/null | jq -r '
        [ .[] | select(
            .type == "PipeWire:Interface:Node" and
            .info.state == "running" and
            .info.props["media.class"] == "Stream/Output/Audio"
        ) ] | length
    ')
    echo "${count:-0}"
}

start_cava() {
    if ! pgrep -P $$ -x cava >/dev/null; then
        cava -p "$CONFIG_FILE" 2>/dev/null | sed -u "$sed_dict" &
        sleep 0.1
    fi
}

stop_cava() {
    if pgrep -P $$ -x cava >/dev/null; then
        pkill -P $$ -x cava 2>/dev/null
        wait 2>/dev/null
        echo "$idle_output"
    fi
}

wait_for_audio_event() {
    timeout 4s pactl subscribe 2>/dev/null | grep --line-buffered "sink" | head -n 1 >/dev/null
}

wait_for_running_state() {
    for i in {1..10}; do
        [ "$(check_audio_playing)" -gt 0 ] && return 0
        sleep 0.1
    done
    return 1
}

# 主循环
pkill -P $$ 2>/dev/null
echo "$idle_output"
silence_timer=0

while true; do
    active_sources=$(check_audio_playing)

    if [ "$active_sources" -gt 0 ]; then
        silence_timer=0
        start_cava
        sleep 2
    else
        if pgrep -P $$ -x cava >/dev/null; then
            if [ "$silence_timer" -ge "$SHUTDOWN_DELAY" ]; then
                stop_cava
            else
                sleep 1
                ((silence_timer++))
            fi
        else
            wait_for_audio_event
            wait_for_running_state
            silence_timer=0
        fi
    fi
done
