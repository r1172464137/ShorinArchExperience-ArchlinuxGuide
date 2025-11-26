#!/bin/bash

# ==============================================================================
# 1. 本地化与文案配置 (Localization)
# ==============================================================================

# 默认英文 (English Default)
STR_PROMPT="Longshot> "
STR_START="⛶  Start Selection (Width as baseline)"
STR_CANCEL="❌ Cancel"
STR_NEXT="📸 Capture Next (Height only)"
STR_SAVE="💾 Save & Finish"
STR_EDIT="🎨 Edit & Finish"
STR_ABORT="❌ Abort"
STR_NOTIFY_TITLE="Longshot"
STR_NOTIFY_SAVED="Saved to"
STR_NOTIFY_COPIED="Copied to clipboard"
STR_ERR_DEP="Missing dependency"
STR_ERR_MENU="Menu tool not found"
STR_ERR_TITLE="Error"

# 本地化检测逻辑：检查 env 输出中是否包含 zh_CN
if env | grep -q "zh_CN"; then
    STR_PROMPT="长截图> "
    STR_START="⛶  开始框选（该图宽视为基准）"
    STR_CANCEL="❌ 取消"
    STR_NEXT="📸 截取下一张（只需确定高度）"
    STR_SAVE="💾 完成并保存"
    STR_EDIT="🎨 完成并编辑"
    STR_ABORT="❌ 放弃并退出"
    STR_NOTIFY_TITLE="长截图完成"
    STR_NOTIFY_SAVED="已保存至"
    STR_NOTIFY_COPIED="并已复制到剪贴板"
    STR_ERR_DEP="缺少核心依赖"
    STR_ERR_MENU="未找到菜单工具 (fuzzel/rofi/wofi)"
    STR_ERR_TITLE="错误"
fi

# ==============================================================================
# 2. 用户配置区
# ==============================================================================
# [修改点] 保存路径增加 longshots 子文件夹
SAVE_DIR="$HOME/Pictures/Screenshots/longshots"
TMP_DIR="/tmp/niri_longshot_$(date +%s)"
FILENAME="longshot_$(date +%Y%m%d_%H%M%S).png"
RESULT_PATH="$SAVE_DIR/$FILENAME"
TMP_STITCHED="$TMP_DIR/stitched_temp.png"

# 菜单工具参数配置
CMD_FUZZEL="fuzzel -d --anchor=top --y-margin=10 --lines=5 --width=45 --prompt=$STR_PROMPT"
CMD_ROFI="rofi -dmenu -i -p $STR_PROMPT -l 5"
CMD_WOFI="wofi --dmenu --lines 5 --prompt $STR_PROMPT"

# ==============================================================================
# 3. 依赖检查
# ==============================================================================
REQUIRED_CMDS=("grim" "slurp" "magick" "notify-send")

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        PKG_NAME="$cmd"
        [[ "$cmd" == "magick" ]] && PKG_NAME="imagemagick"
        notify-send -u critical "$STR_ERR_TITLE" "$STR_ERR_DEP: $cmd\nInstall: sudo pacman -S $PKG_NAME"
        exit 1
    fi
done

# ==============================================================================
# 4. 工具探测 (编辑器 & 菜单)
# ==============================================================================

# --- 编辑器探测 (Satty > Swappy) ---
EDITOR_CMD=""
if command -v satty &> /dev/null; then
    EDITOR_CMD="satty --filename"
elif command -v swappy &> /dev/null; then
    EDITOR_CMD="swappy -f"
fi

# --- 菜单工具探测 ---
MENU_CMD=""
if command -v fuzzel &> /dev/null; then MENU_CMD="$CMD_FUZZEL"
elif command -v rofi &> /dev/null; then MENU_CMD="$CMD_ROFI"
elif command -v wofi &> /dev/null; then MENU_CMD="$CMD_WOFI"
else
    notify-send -u critical "$STR_ERR_TITLE" "$STR_ERR_MENU"
    exit 1
fi

# ==============================================================================
# 5. 辅助函数与初始化
# ==============================================================================
mkdir -p "$SAVE_DIR"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

function show_menu() { echo -e "$1" | $MENU_CMD; }

# ==============================================================================
# 步骤 1: 第一张截图 (基准)
# ==============================================================================

SELECTION=$(show_menu "$STR_START\n$STR_CANCEL")
if [[ "$SELECTION" != "$STR_START" ]]; then exit 0; fi

sleep 0.2 
GEO_1=$(slurp)
if [ -z "$GEO_1" ]; then exit 0; fi

IFS=', x' read -r FIX_X FIX_Y FIX_W FIX_H <<< "$GEO_1"
grim -g "$GEO_1" "$TMP_DIR/001.png"

# ==============================================================================
# 步骤 2: 循环截图
# ==============================================================================
INDEX=2
SAVE_MODE=""

while true; do
    # 构建菜单选项
    MENU_OPTIONS="$STR_NEXT\n$STR_SAVE"
    
    if [[ -n "$EDITOR_CMD" ]]; then
        MENU_OPTIONS="$MENU_OPTIONS\n$STR_EDIT"
    fi
    
    MENU_OPTIONS="$MENU_OPTIONS\n$STR_ABORT"
    
    # 显示菜单
    ACTION=$(show_menu "$MENU_OPTIONS")
    
    case "$ACTION" in
        *"📸"*)
            sleep 0.2
            GEO_NEXT=$(slurp)
            if [ -z "$GEO_NEXT" ]; then break; fi 
            
            IFS=', x' read -r _TEMP_X NEW_Y _TEMP_W NEW_H <<< "$GEO_NEXT"
            FINAL_GEO="${FIX_X},${NEW_Y} ${FIX_W}x${NEW_H}"
            
            IMG_NAME="$(printf "%03d" $INDEX).png"
            grim -g "$FINAL_GEO" "$TMP_DIR/$IMG_NAME"
            ((INDEX++))
            ;;
            
        *"💾"*) # 保存
            SAVE_MODE="save"
            break
            ;;
            
        *"🎨"*) # 编辑
            SAVE_MODE="edit"
            break
            ;;
            
        *"❌"*) # 放弃/取消
            exit 0
            ;;
            
        *) # Esc 关闭菜单
            break
            ;;
    esac
done

# ==============================================================================
# 步骤 3: 拼接与后续处理
# ==============================================================================
COUNT=$(ls "$TMP_DIR"/*.png 2>/dev/null | wc -l)

if [ "$COUNT" -gt 0 ]; then
    # 拼接
    magick "$TMP_DIR"/*.png -append "$TMP_STITCHED"
    
    # 编辑模式
    if [[ "$SAVE_MODE" == "edit" ]]; then
        $EDITOR_CMD "$TMP_STITCHED"
    fi
    
    # 保存与通知
    if [[ -n "$SAVE_MODE" ]]; then
        mv "$TMP_STITCHED" "$RESULT_PATH"
        
        COPY_MSG=""
        if command -v wl-copy &> /dev/null; then
            wl-copy < "$RESULT_PATH"
            COPY_MSG="$STR_NOTIFY_COPIED"
        fi
        
        notify-send -i "$RESULT_PATH" "$STR_NOTIFY_TITLE" "$STR_NOTIFY_SAVED $FILENAME\n$COPY_MSG"
    fi
fi