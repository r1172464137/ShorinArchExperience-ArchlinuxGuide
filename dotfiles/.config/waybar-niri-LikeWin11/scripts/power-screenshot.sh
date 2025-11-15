#!/usr/bin/env bash
set -euo pipefail

########################
# 配置区域（直接改这里）
########################

NIRI_CONFIG="$HOME/.config/niri/config.kdl"   # niri 配置文件

SHOTEDITOR_DEFAULT="swappy"                   # 默认截图编辑器：swappy 或 satty
COPY_CMD="wl-copy"                            # 复制到剪贴板的命令

# 菜单程序，按你实际使用的启动器改
# wofi 示例: MENU_CMD='wofi -d'
# rofi 示例: MENU_CMD='rofi -dmenu'
MENU_CMD='fuzzel --dmenu'

# 图片目录
PICTURES_DIR=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
SCREEN_DIR="$PICTURES_DIR/Screenshots"

########################
# 本地化（中/英）
########################

LOCALE="${LC_MESSAGES:-${LANG:-en}}"
if [[ "$LOCALE" == zh* ]]; then
    # 通用
    LABEL_CANCEL="取消"
    LABEL_SETTINGS="设置"
    LABEL_EDIT_YES="编辑"
    LABEL_EDIT_NO="不编辑"

    # Niri 模式
    LABEL_NIRI_FULL="全屏"
    LABEL_NIRI_WINDOW="窗口"
    LABEL_NIRI_REGION="选取区域"

    # Grim 模式
    LABEL_GRIM_FULL="全屏"
    LABEL_GRIM_REGION="选取区域"

    # 设置菜单
    LABEL_SETTINGS_EDITOR="截图工具"
    LABEL_SETTINGS_BACKEND="后端模式"
    LABEL_BACKEND_AUTO="自动（检测 Niri）"
    LABEL_BACKEND_GRIM="仅 Grim+slurp"
    LABEL_BACK="返回"

    # 编辑开关显示
    LABEL_EDIT_STATE_ON="编辑：开启"
    LABEL_EDIT_STATE_OFF="编辑：关闭"

    # 提示文字
    PROMPT_MAIN="请选择截图模式"
    PROMPT_SETTINGS="设置 / 更改选项"
    PROMPT_EDITOR="请选择截图编辑工具"
    PROMPT_BACKEND="请选择后端模式"
else
    LABEL_CANCEL="Cancel"
    LABEL_SETTINGS="Settings"
    LABEL_EDIT_YES="Edit"
    LABEL_EDIT_NO="No edit"

    LABEL_NIRI_FULL="Fullscreen"
    LABEL_NIRI_WINDOW="Window"
    LABEL_NIRI_REGION="Region"

    LABEL_GRIM_FULL="Fullscreen"
    LABEL_GRIM_REGION="Select area"

    LABEL_SETTINGS_EDITOR="Screenshot tool"
    LABEL_SETTINGS_BACKEND="Backend mode"
    LABEL_BACKEND_AUTO="Auto (detect Niri)"
    LABEL_BACKEND_GRIM="Grim+slurp only"
    LABEL_BACK="Back"

    LABEL_EDIT_STATE_ON="Edit: ON"
    LABEL_EDIT_STATE_OFF="Edit: OFF"

    PROMPT_MAIN="Choose screenshot mode"
    PROMPT_SETTINGS="Settings / Options"
    PROMPT_EDITOR="Choose screenshot editor"
    PROMPT_BACKEND="Choose backend mode"
fi

########################
# 持久化配置路径
########################

CONFIG_DIR="$HOME/.config/waybar/waybar-shot"
BACKEND_FILE="$CONFIG_DIR/backend"
EDITOR_FILE="$CONFIG_DIR/editor"
EDIT_MODE_FILE="$CONFIG_DIR/edit_mode"   # yes / no

########################
# 通用工具函数
########################

menu() {
    # 不带提示的版本（备用）
    printf '%s\n' "$@" | eval "$MENU_CMD" 2>/dev/null || true
}

menu_prompt() {
    # 第一个参数是提示文字，其余是选项
    local prompt="$1"
    shift
    # 简单转义双引号，避免破坏 eval
    local esc_prompt="${prompt//\"/\\\"}"
    printf '%s\n' "$@" | eval "$MENU_CMD --prompt \"$esc_prompt\"" 2>/dev/null || true
}

load_backend_mode() {
    local mode
    if [[ -n "${SHOT_BACKEND:-}" ]]; then
        mode="$SHOT_BACKEND"
    elif [[ -f "$BACKEND_FILE" ]]; then
        mode="$(<"$BACKEND_FILE")"
    else
        mode="auto"
    fi
    case "$mode" in
        auto|grim|niri) ;;
        *) mode="auto" ;;
    esac
    printf '%s\n' "$mode"
}

save_backend_mode() {
    local mode="$1"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$mode" >"$BACKEND_FILE"
}

load_editor() {
    local ed
    if [[ -n "${SHOTEDITOR:-}" ]]; then
        ed="$SHOTEDITOR"
    elif [[ -f "$EDITOR_FILE" ]]; then
        ed="$(<"$EDITOR_FILE")"
    else
        ed="$SHOTEDITOR_DEFAULT"
    fi

    ed="${ed,,}"
    case "$ed" in
        swappy|satty) ;;
        *) ed="$SHOTEDITOR_DEFAULT" ;;
    esac
    printf '%s\n' "$ed"
}

save_editor() {
    local ed="$1"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$ed" >"$EDITOR_FILE"
}

load_edit_mode() {
    local v="yes"
    if [[ -f "$EDIT_MODE_FILE" ]]; then
        v="$(<"$EDIT_MODE_FILE")"
    fi
    case "$v" in
        yes|no) ;;
        *) v="yes" ;;    # 默认：编辑开启
    esac
    printf '%s\n' "$v"
}

save_edit_mode() {
    local v="$1"
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$v" >"$EDIT_MODE_FILE"
}

detect_backend() {
    case "$BACKEND_MODE" in
        niri) echo "niri" ;;
        grim) echo "grim" ;;
        auto|*)
            if command -v niri >/dev/null 2>&1 && pgrep -x niri >/dev/null 2>&1; then
                echo "niri"
            else
                echo "grim"
            fi
            ;;
    esac
}

choose_editor() {
    local choice
    choice="$(menu_prompt "$PROMPT_EDITOR" "swappy" "satty" "$LABEL_BACK")"
    case "$choice" in
        swappy|Swappy)
            SHOTEDITOR="swappy"
            save_editor "$SHOTEDITOR"
            ;;
        satty|Satty)
            SHOTEDITOR="satty"
            save_editor "$SHOTEDITOR"
            ;;
        *) : ;;
    esac
}

choose_backend_mode() {
    local choice
    choice="$(menu_prompt "$PROMPT_BACKEND" "$LABEL_BACKEND_AUTO" "$LABEL_BACKEND_GRIM" "$LABEL_BACK")"
    case "$choice" in
        "$LABEL_BACKEND_AUTO")
            BACKEND_MODE="auto"
            save_backend_mode "$BACKEND_MODE"
            ;;
        "$LABEL_BACKEND_GRIM")
            BACKEND_MODE="grim"
            save_backend_mode "$BACKEND_MODE"
            ;;
        *) : ;;
    esac
}

settings_menu() {
    while :; do
        local backend_desc editor_line backend_line choice

        if [[ -n "${SHOT_BACKEND:-}" ]]; then
            backend_desc="${BACKEND_MODE} (env)"
        else
            if [[ "$BACKEND_MODE" == "grim" ]]; then
                backend_desc="$LABEL_BACKEND_GRIM"
            elif [[ "$BACKEND_MODE" == "niri" ]]; then
                backend_desc="niri"
            else
                backend_desc="$LABEL_BACKEND_AUTO"
            fi
        fi

        editor_line="$LABEL_SETTINGS_EDITOR: $SHOTEDITOR"
        backend_line="$LABEL_SETTINGS_BACKEND: $backend_desc"

        choice="$(menu_prompt "$PROMPT_SETTINGS" "$editor_line" "$backend_line" "$LABEL_BACK")"
        case "$choice" in
            "$editor_line")  choose_editor ;;
            "$backend_line")
                if [[ -n "${SHOT_BACKEND:-}" ]]; then
                    : # 环境变量强制时不改持久化
                else
                    choose_backend_mode
                fi
                ;;
            *)               return ;;  # 返回上一层
        esac
    done
}

latest_in_dir() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -n | tail -1 | cut -d' ' -f2-
}

########################
# Niri 相关
########################

get_niri_shot_dir() {
    [[ -f "$NIRI_CONFIG" ]] || { echo "Config not found: $NIRI_CONFIG" >&2; return 1; }

    local line tpl dir
    line="$(
        grep -E '^[[:space:]]*screenshot-path[[:space:]]' "$NIRI_CONFIG" \
          | grep -v '^[[:space:]]*//' \
          | tail -n 1 || true
    )"
    [[ -n "$line" ]] || { echo "No screenshot-path in config" >&2; return 1; }

    tpl="$(sed -E 's/.*screenshot-path[[:space:]]+"([^"]+)".*/\1/' <<<"$line")"
    [[ -n "$tpl" ]] || { echo "Failed to parse screenshot-path: $line" >&2; return 1; }

    tpl="${tpl/#\~/$HOME}"
    dir="${tpl%/*}"

    printf '%s\n' "$dir"
}

edit_image() {
    local src="$1"
    local backend="$2"  # "niri" 或 "grim"

    local dir edited_link ts dst

    if [[ "$backend" == "niri" ]]; then
        dir="$NIRI_EDIT_DIR"
        edited_link="$NIRI_EDIT_DIR/latest"
    else
        dir="$SCREEN_DIR"
        edited_link="$SCREEN_DIR/latest"
    fi

    mkdir -p "$dir"

    ts="$(date +'%Y-%m-%d_%H-%M-%S')"
    dst="$dir/$SHOTEDITOR-$ts.png"

    case "$SHOTEDITOR" in
        satty)
            satty --filename "$src" --output-filename "$dst"
            ;;
        swappy)
            swappy -f "$src" -o "$dst"
            ;;
        *)
            echo "Unknown SHOTEDITOR: $SHOTEDITOR (use satty or swappy)" >&2
            return 1
            ;;
    esac

    if [[ -f "$dst" ]]; then
        ln -sfn "$dst" "$edited_link"
        if [[ "$backend" == "grim" && "$src" == /tmp/* ]]; then
            rm -f "$src"
        fi
        "$COPY_CMD" < "$dst"
    fi
}

niri_capture_and_maybe_edit() {
    local mode="$1"       # fullscreen / window / region
    local need_edit="$2"  # yes / no

    local action
    case "$mode" in
        fullscreen) action="screenshot-screen" ;;
        window)     action="screenshot-window" ;;
        region)     action="screenshot"       ;;
        *)          return 1 ;;
    esac

    local before shot
    before="$(latest_in_dir "$NIRI_SHOT_DIR" || true)"

    niri msg action "$action"

    while :; do
        shot="$(latest_in_dir "$NIRI_SHOT_DIR" || true)"
        if [[ -z "$before" && -n "$shot" ]] || \
           [[ -n "$before" && -n "$shot" && "$shot" != "$before" ]]; then
            break
        fi
        sleep 0.05
    done

    ln -sfn "$shot" "$NIRI_SHOT_DIR/latest"

    if [[ "$need_edit" == "yes" ]]; then
        edit_image "$shot" "niri"
    fi
}

run_niri_flow() {
    NIRI_SHOT_DIR="$(get_niri_shot_dir)" || exit 1
    NIRI_EDIT_DIR="$NIRI_SHOT_DIR/Edited"
    mkdir -p "$NIRI_SHOT_DIR" "$NIRI_EDIT_DIR"

    while :; do
        local choice mode edit_mode edit_label

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            edit_label="$LABEL_EDIT_STATE_ON"
        else
            edit_label="$LABEL_EDIT_STATE_OFF"
        fi

        choice="$(menu_prompt "$PROMPT_MAIN" \
            "$LABEL_NIRI_FULL" \
            "$LABEL_NIRI_WINDOW" \
            "$LABEL_NIRI_REGION" \
            "$edit_label" \
            "$LABEL_SETTINGS" \
            "$LABEL_CANCEL"
        )"

        [[ -z "$choice" || "$choice" == "$LABEL_CANCEL" ]] && exit 0

        case "$choice" in
            "$LABEL_NIRI_FULL")   mode="fullscreen" ;;
            "$LABEL_NIRI_WINDOW") mode="window"     ;;
            "$LABEL_NIRI_REGION") mode="region"     ;;
            "$edit_label")
                if [[ "$edit_mode" == "yes" ]]; then
                    save_edit_mode "no"
                else
                    save_edit_mode "yes"
                fi
                continue  # 回到主菜单，更新显示
                ;;
            "$LABEL_SETTINGS")
                settings_menu
                continue
                ;;
            *)
                exit 0 ;;
        esac

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            niri_capture_and_maybe_edit "$mode" "yes"
        else
            niri_capture_and_maybe_edit "$mode" "no"
        fi
        exit 0
    done
}

########################
# Grim + slurp 相关
########################

grim_capture_and_maybe_edit() {
    local mode="$1"       # fullscreen / region
    local need_edit="$2"  # yes / no

    mkdir -p "$SCREEN_DIR"

    local ts shot geo
    ts="$(date +'%Y-%m-%d_%H-%M-%S')"

    if [[ "$need_edit" == "yes" ]]; then
        # 编辑模式：原图在 /tmp，用完删，只保留编辑后的图
        shot="/tmp/waybar-shot-$ts.png"

        case "$mode" in
            fullscreen)
                grim "$shot"
                ;;
            region)
                geo="$(slurp 2>/dev/null)" || exit 0
                grim -g "$geo" "$shot"
                ;;
            *)
                return 1 ;;
        esac

        edit_image "$shot" "grim"
    else
        # 不编辑：原图保存到 Screenshots，并更新 latest
        shot="$SCREEN_DIR/Screenshot_$ts.png"

        case "$mode" in
            fullscreen)
                grim "$shot"
                ;;
            region)
                geo="$(slurp 2>/dev/null)" || exit 0
                grim -g "$geo" "$shot"
                ;;
            *)
                return 1 ;;
        esac

        ln -sfn "$shot" "$SCREEN_DIR/latest"
    fi
}

run_grim_flow() {
    mkdir -p "$SCREEN_DIR"

    while :; do
        local choice mode edit_mode edit_label

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            edit_label="$LABEL_EDIT_STATE_ON"
        else
            edit_label="$LABEL_EDIT_STATE_OFF"
        fi

        choice="$(menu_prompt "$PROMPT_MAIN" \
            "$LABEL_GRIM_FULL" \
            "$LABEL_GRIM_REGION" \
            "$edit_label" \
            "$LABEL_SETTINGS" \
            "$LABEL_CANCEL"
        )"

        [[ -z "$choice" || "$choice" == "$LABEL_CANCEL" ]] && exit 0

        case "$choice" in
            "$LABEL_GRIM_FULL")   mode="fullscreen" ;;
            "$LABEL_GRIM_REGION") mode="region"     ;;
            "$edit_label")
                if [[ "$edit_mode" == "yes" ]]; then
                    save_edit_mode "no"
                else
                    save_edit_mode "yes"
                fi
                continue
                ;;
            "$LABEL_SETTINGS")
                settings_menu
                continue
                ;;
            *)
                exit 0 ;;
        esac

        edit_mode="$(load_edit_mode)"
        if [[ "$edit_mode" == "yes" ]]; then
            grim_capture_and_maybe_edit "$mode" "yes"
        else
            grim_capture_and_maybe_edit "$mode" "no"
        fi
        exit 0
    done
}

########################
# 入口
########################

BACKEND_MODE="$(load_backend_mode)"
SHOTEDITOR="$(load_editor)"

BACKEND="$(detect_backend)"

case "$BACKEND" in
    niri) run_niri_flow ;;
    grim) run_grim_flow ;;
    *)    run_grim_flow ;;
esac
