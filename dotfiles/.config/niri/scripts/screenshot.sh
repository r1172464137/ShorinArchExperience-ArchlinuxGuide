#!/usr/bin/env bash
set -euo pipefail

########################
# 配置区域（直接改这里）
########################

CONFIG="$HOME/.config/niri/config.kdl"   # niri 配置文件
SHOTEDITOR="swappy"                       # satty 或 swappy
COPY_CMD="wl-copy"                       # 复制到剪贴板的命令
NIRI_ACTION="screenshot"                # screenshot / screenshot-window / screenshot-screen

# 图片目录
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
SAVE_DIR="$PICTURES_DIR/Screenshots/Edited"  # 保存到 Pictures/Screenshots/Edited

# 统一用小写，方便拼文件名
SHOTEDITOR="${SHOTEDITOR,,}"

########################
# 从 niri 配置里获取截图目录 SHOT_DIR
########################

get_shot_dir() {
    [[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; return 1; }

    local LINE TPL DIR
    LINE="$(
        grep -E '^[[:space:]]*screenshot-path[[:space:]]' "$CONFIG" \
          | grep -v '^[[:space:]]*//' \
          | tail -n 1 || true
    )"
    [[ -n "$LINE" ]] || { echo "No screenshot-path in config" >&2; return 1; }

    TPL="$(sed -E 's/.*screenshot-path[[:space:]]+"([^"]+)".*/\1/' <<<"$LINE")"
    [[ -n "$TPL" ]] || { echo "Failed to parse screenshot-path: $LINE" >&2; return 1; }

    # 展开 ~
    TPL="${TPL/#\~/$HOME}"
    DIR="${TPL%/*}"

    printf '%s\n' "$DIR"
}

SHOT_DIR="$(get_shot_dir)"
mkdir -p "$SHOT_DIR" "$SAVE_DIR"

ORIG_LINK_PATH="$SHOT_DIR/latest"      # 原始截图 latest
EDITED_LINK_PATH="$SAVE_DIR/latest"    # 编辑后 latest

########################
# 获取目录中“最新文件”
########################

latest_file() {
    find "$SHOT_DIR" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -n \
        | tail -1 \
        | cut -d' ' -f2-
}

BEFORE="$(latest_file || true)"

########################
# 1. 用 niri 截图
########################

niri msg action "$NIRI_ACTION"

########################
# 2. 等待新文件出现
########################

LATEST=""
while :; do
    CANDIDATE="$(latest_file || true)"

    if [[ -z "$BEFORE" && -n "$CANDIDATE" ]] || \
       [[ -n "$BEFORE" && -n "$CANDIDATE" && "$CANDIDATE" != "$BEFORE" ]]; then
        LATEST="$CANDIDATE"
        break
    fi

    sleep 0.05
done

########################
# 3. 更新原始截图 latest 链接
########################

ln -sfn "$LATEST" "$ORIG_LINK_PATH"

########################
# 4. 生成编辑后文件名（包含编辑器名）
########################

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
# 形如：satty-2025-11-15_13-20-01.png / swappy-...
EDITED_FILE="$SAVE_DIR/$SHOTEDITOR-$TIMESTAMP.png"

########################
# 5. 用 swappy / satty 编辑
########################

case "$SHOTEDITOR" in
    satty)
        satty \
            --filename "$LATEST" \
            --output-filename "$EDITED_FILE"
        ;;
    swappy)
        swappy \
            -f "$LATEST" \
            -o "$EDITED_FILE"
        ;;
    *)
        echo "Unknown SHOTEDITOR: $SHOTEDITOR (use satty or swappy)" >&2
        exit 1
        ;;
esac

########################
# 6. 编辑完后：更新编辑版 latest + 放入剪贴板
########################

if [[ -f "$EDITED_FILE" ]]; then
    # 编辑后的 latest 链接
    ln -sfn "$EDITED_FILE" "$EDITED_LINK_PATH"
    # 放入剪贴板
    "$COPY_CMD" < "$EDITED_FILE"
else
    echo "Edited file not found: $EDITED_FILE" >&2
    exit 1
fi
