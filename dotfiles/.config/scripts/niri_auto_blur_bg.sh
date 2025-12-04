#!/bin/bash

# ==============================================================================
# 1. 配置区
# ==============================================================================
CACHE_DIR="$HOME/.cache/blur-wallpapers/auto-blur-bg"
LAST_CLEAR_FILE="/tmp/niri_last_clear_wallpaper"
# [新增] PID 文件路径，用于防止重复运行
PID_FILE="/tmp/niri_auto_blur.pid"
LINK_NAME="cache-niri-auto-blur-bg"

# --- 行为开关 ---
OVERVIEW_FORCE_CLEAR="false"
# --- 自动预生成缓存：扫描壁纸目录并提前生成模糊图 ---
AUTO_PREGEN="true"        # true/false
WALL_DIR="$HOME/Pictures/Wallpapers/"   # ← 这里改成你的壁纸文件夹

# --- 浮动窗口例外设置 ---
FLOAT_BYPASS_ENABLED="false"   # 开启: 仅有少量浮动窗口时不模糊
FLOAT_BYPASS_THRESHOLD="1"    # 阈值: 浮动窗口数量 <= 此值且无平铺窗口时，保持原图

# --- 视觉参数 ---
BLUR_ARG="0x15"
ENABLE_DARK="false"
DARK_OPACITY="40%"
ANIM_TYPE="fade"
ANIM_DURATION="0.4"
WORK_SWITCH_DELAY="0"

mkdir -p "$CACHE_DIR"

# ==============================================================================
# 2. [新增] 防止重复运行检查
# ==============================================================================
if [[ -f "$PID_FILE" ]]; then
    # 读取旧 PID
    OLD_PID=$(cat "$PID_FILE")
    # 检查进程是否存在
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo -e "\033[31m[ERROR]\033[0m 脚本已经在运行中 (PID: $OLD_PID)。请勿重复启动。"
        echo "如果需要重启，请先执行: kill $OLD_PID 或 killall $(basename "$0")"
        exit 1
    else
        echo -e "\033[33m[WARN]\033[0m 检测到残留的 PID 文件，但进程已不存在。自动清理并启动。"
    fi
fi

# 写入当前 PID
echo $$ > "$PID_FILE"

# ==============================================================================
# 3. 预计算与检查
# ==============================================================================
if [[ "$ENABLE_DARK" == "true" ]]; then
    SAFE_OPACITY="${DARK_OPACITY%\%}"
    FILE_PREFIX="auto-blur-dark-${BLUR_ARG}-${SAFE_OPACITY}-"
else
    FILE_PREFIX="auto-blur-pure-${BLUR_ARG}-"
fi

SWWW_CMD="swww img --transition-type $ANIM_TYPE --transition-duration $ANIM_DURATION"

if [[ "$FLOAT_BYPASS_ENABLED" == "true" ]] && ! command -v jq &> /dev/null; then
    echo "Warning: 'jq' not found. Floating bypass disabled."
    FLOAT_BYPASS_ENABLED="false"
fi

# ==============================================================================
# 4. 工具函数
# ==============================================================================
log() { echo -e "[$(date '+%H:%M:%S')] $1"; }

fetch_current_wall() {
    local raw_line
    read -r raw_line < <(swww query 2>/dev/null)
    if [[ "$raw_line" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
        _RET_WALL="${BASH_REMATCH[1]}"
    else
        _RET_WALL=""
    fi
}

is_blur_filename() {
    [[ "$1" == "${FILE_PREFIX}"* || "$1" == auto-blur-* ]]
}

check_floating_bypass() {
    [[ "$FLOAT_BYPASS_ENABLED" != "true" ]] && return 1
    local workspaces_json=$(niri msg -j workspaces 2>/dev/null)
    local windows_json=$(niri msg -j windows 2>/dev/null)
    [[ -z "$workspaces_json" || -z "$windows_json" ]] && return 1

    local counts=$(jq -n -r --argjson ws "$workspaces_json" --argjson wins "$windows_json" '
        ($ws[] | select(.is_focused == true).id) as $focus_id |
        ($wins | map(select(.workspace_id == $focus_id))) as $my_wins |
        {
            total: ($my_wins | length),
            floating: ($my_wins | map(select(.is_floating == true)) | length),
            tiling: ($my_wins | map(select(.is_floating == false)) | length)
        } | "\(.total) \(.floating) \(.tiling)"
    ')
    read -r total floating tiling <<< "$counts"

    [[ "$total" -eq 0 ]] && return 0
    if [[ "$tiling" -eq 0 && "$floating" -le "$FLOAT_BYPASS_THRESHOLD" ]]; then
        log "Bypass: Only floating windows ($floating) -> Keep Clear"
        return 0
    fi
    return 1
}
# ==============================================================================
# X. 自动生成壁纸缓存（优先当前壁纸，其他后台生成）
# ==============================================================================
pregen_wallpaper_cache() {
    [[ "$AUTO_PREGEN" != "true" ]] && return

    log "Auto-PreGen: 开始扫描壁纸目录 $WALL_DIR"
    if [[ ! -d "$WALL_DIR" ]]; then
        log "Auto-PreGen: 目录不存在，跳过。"
        return
    fi

    # 获取当前壁纸（使用脚本已有函数）
    fetch_current_wall
    local current="$_RET_WALL"
    local current_base="${current##*/}"
    local current_target=""
    [[ -n "$current" ]] && current_target="$CACHE_DIR/${FILE_PREFIX}${current_base}"

    # 如果当前壁纸有缓存 -> 立即应用（异步切换以不阻塞启动）
    if [[ -n "$current" && -f "$current_target" ]]; then
        log "Auto-PreGen: 当前壁纸的 blur 已存在 -> 立即应用 ${current_base}"
        $SWWW_CMD "$current_target" &
    else
        # 如果当前壁纸存在但没有缓存，则先为当前壁纸生成并立即应用（前台生成以保证切换即时）
        if [[ -n "$current" && -f "$current" ]]; then
            log "Auto-PreGen: 当前壁纸无缓存，先为其生成 blur -> ${current_base}"
            if [[ "$ENABLE_DARK" == "true" ]]; then
                magick "$current" -blur "$BLUR_ARG" -fill black -colorize "$DARK_OPACITY" "$current_target"
            else
                magick "$current" -blur "$BLUR_ARG" "$current_target"
            fi
            log "Auto-PreGen: 应用已生成的当前 blur -> ${current_base}"
            $SWWW_CMD "$current_target" &
        fi
    fi

    # 后台生成其它图片的 cache（跳过当前壁纸）
    (
        local total=0
        local done=0
        while IFS= read -r -d '' img; do
            # 跳过当前壁纸本体（已处理）
            [[ -n "$current" && "$img" == "$current" ]] && continue

            total=$((total + 1))
            local base="${img##*/}"
            local target="$CACHE_DIR/${FILE_PREFIX}${base}"

            if [[ -f "$target" ]]; then
                log "Auto-PreGen (bg): Skip (exists) -> $base"
                continue
            fi

            log "Auto-PreGen (bg): Generating -> $base"
            if [[ "$ENABLE_DARK" == "true" ]]; then
                magick "$img" -blur "$BLUR_ARG" -fill black -colorize "$DARK_OPACITY" "$target"
            else
                magick "$img" -blur "$BLUR_ARG" "$target"
            fi
            done=$((done + 1))
        done < <(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)

        log "Auto-PreGen (bg): 完成，扫描 $total 个文件，新增生成 $done 个缓存。"
    ) &   # <- 整个生成循环在后台运行
}

# ==============================================================================
# 5. 核心状态管理
# ==============================================================================
CURRENT_STATE=-1 
IS_OVERVIEW=false
DEBOUNCE_PID=""
_RET_WALL=""

# [修改] 退出清理：同时也删除 PID 文件
cleanup() {
    log "Service stopping, restoring wallpaper..."
    
    # 1. 移除 PID 文件
    rm -f "$PID_FILE"
    
    # 2. 停止防抖任务
    [[ -n "$DEBOUNCE_PID" ]] && kill "$DEBOUNCE_PID" 2>/dev/null
    
    # 3. 还原壁纸
    fetch_current_wall
    local cname="${_RET_WALL##*/}"
    if is_blur_filename "$cname" && [[ -f "$LAST_CLEAR_FILE" ]]; then
        local original=$(<"$LAST_CLEAR_FILE")
        [[ -f "$original" ]] && swww img "$original" --transition-type none
    fi
    exit 0
}
# 捕获退出信号
trap cleanup EXIT SIGINT SIGTERM

do_restore_task() {
    [[ ! -f "$LAST_CLEAR_FILE" ]] && return
    local target=$(<"$LAST_CLEAR_FILE")
    [[ ! -f "$target" ]] && return
    fetch_current_wall
    local cname="${_RET_WALL##*/}"
    if is_blur_filename "$cname"; then
        log "Restore -> ${target##*/}"
        $SWWW_CMD "$target"
    fi
}

switch_to_clear() {
    local mode="$1"
    [[ "$CURRENT_STATE" -eq 0 ]] && return
    [[ -n "$DEBOUNCE_PID" ]] && kill "$DEBOUNCE_PID" 2>/dev/null && DEBOUNCE_PID=""

    if [[ "$mode" == "delay" ]]; then
        ( sleep "$WORK_SWITCH_DELAY"; do_restore_task ) &
        DEBOUNCE_PID=$!
    else
        do_restore_task
    fi
    CURRENT_STATE=0
}

switch_to_blur() {
    [[ -n "$DEBOUNCE_PID" ]] && kill "$DEBOUNCE_PID" 2>/dev/null && DEBOUNCE_PID=""
    
    if check_floating_bypass; then
        switch_to_clear "noderect"
        return
    fi

    fetch_current_wall
    local current="$_RET_WALL"
    [[ -z "$current" ]] && return
    local current_name="${current##*/}"

    if [[ "$current_name" == "${FILE_PREFIX}"* ]]; then
        [[ "$CURRENT_STATE" -ne 1 ]] && CURRENT_STATE=1
        return
    fi
    CURRENT_STATE=1

    if ! is_blur_filename "$current_name" && [[ "$current_name" != blur-dark-* ]]; then
        log "New Clear Wall -> $current_name"
        echo "$current" > "$LAST_CLEAR_FILE"
        local link_path="${current%/*}/$LINK_NAME"
        ln -sfn "$CACHE_DIR" "$link_path" 2>/dev/null
    fi

    [[ ! -f "$LAST_CLEAR_FILE" ]] && return
    local source_wall=$(<"$LAST_CLEAR_FILE")
    local target_blur="$CACHE_DIR/${FILE_PREFIX}${source_wall##*/}"

    if [[ ! -f "$target_blur" ]]; then
        log "Generating Blur -> ${source_wall##*/}"
        if [[ "$ENABLE_DARK" == "true" ]]; then
            magick "$source_wall" -blur "$BLUR_ARG" -fill black -colorize "$DARK_OPACITY" "$target_blur"
        else
            magick "$source_wall" -blur "$BLUR_ARG" "$target_blur"
        fi
    fi

    log "Applying Blur"
    $SWWW_CMD "$target_blur" &
}

force_check_state() {
    local niri_out=$(niri msg focused-window 2>&1)
    if [[ "$niri_out" == *"No window"* ]]; then
        [[ "$1" == "true" ]] && switch_to_clear "delay" || switch_to_clear "noderect"
    else
        switch_to_blur
    fi
}

# ==============================================================================
# 6. 主循环
# ==============================================================================
log "Daemon Started (PID: $$)."
pregen_wallpaper_cache
force_check_state "false"

niri msg event-stream | grep --line-buffered -E "^(Window|Workspace|Overview)" | while read -r line; do
    case "$line" in
        *"Window opened"*)              switch_to_blur ;;
        *"Window closed"*)              force_check_state "false" ;;
        *"Window focus changed: None"*) switch_to_clear "noderect" ;;
        *"Window focus changed: Some"*) switch_to_blur ;;
        *"Workspace focused"*)          [[ "$IS_OVERVIEW" == "false" ]] && force_check_state "true" ;;
        *"Overview toggled: true"*)     IS_OVERVIEW=true; [[ "$OVERVIEW_FORCE_CLEAR" == "true" ]] && switch_to_clear "noderect" ;;
        *"Overview toggled: false"*)    IS_OVERVIEW=false; force_check_state "false" ;;
        *"active window changed to Some"*) [[ "$IS_OVERVIEW" == "true" && "$OVERVIEW_FORCE_CLEAR" == "false" ]] && switch_to_blur ;;
        *"active window changed to None"*) [[ "$IS_OVERVIEW" == "true" && "$OVERVIEW_FORCE_CLEAR" == "false" ]] && switch_to_clear "noderect" ;;
    esac
done
