#!/bin/bash

# --- 1. 参数解析 ---
WALLPAPER=""
NO_INDEX=false

show_help() {
    echo "Usage: matugen-update.sh [OPTIONS] [WALLPAPER]"
    echo ""
    echo "Options:"
    echo "  -h, --help       显示此帮助信息"
    echo "  -n, --no-index   不指定 index，在终端运行时唤起 matugen 原生的交互式颜色选择"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -n|--no-index)
            NO_INDEX=true
            shift
            ;;
        *)
            # 假设其他参数都是壁纸路径
            WALLPAPER="$1"
            shift
            ;;
    esac
done

# --- 2. 路径与状态定义 ---
CACHE_DIR="$HOME/.cache/matugen-strategy"
TYPE_FILE="$CACHE_DIR/type"
MODE_FILE="$CACHE_DIR/mode"
INDEX_MODE_FILE="$CACHE_DIR/index_mode"
LAST_WALL_FILE="$CACHE_DIR/last_wallpaper"  # 新增：记录上一次处理的壁纸路径
CURRENT_INDEX_FILE="$CACHE_DIR/current_index" # 新增：记录当前使用的颜色索引
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"

# --- 3. 获取壁纸路径 ---
if [ -z "$WALLPAPER" ]; then
    if command -v swww &>/dev/null && pgrep -x "swww-daemon" >/dev/null; then
         DETECTED_WALL=$(swww query | head -n 1 | awk -F ': ' '{print $2}' | awk '{print $1}')
         if [ -n "$DETECTED_WALL" ] && [ -f "$DETECTED_WALL" ]; then
            WALLPAPER="$DETECTED_WALL"
         fi
    fi
    if [ -z "$WALLPAPER" ] && [ -f "$WAYPAPER_CONFIG" ]; then
        WP_PATH=$(sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' "$WAYPAPER_CONFIG")
        WP_PATH="${WP_PATH/#\~/$HOME}"
        if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
            WALLPAPER="$WP_PATH"
        fi
    fi
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    notify-send "Matugen Error" "无法找到壁纸路径。"
    exit 1
fi
ln -sf "$WALLPAPER" "$HOME/.cache/.current_wallpaper"

# --- 4. 读取策略与模式 ---
if [ -f "$TYPE_FILE" ]; then STRATEGY=$(cat "$TYPE_FILE"); else STRATEGY="scheme-tonal-spot"; fi
if [ -f "$MODE_FILE" ]; then MODE=$(cat "$MODE_FILE"); else MODE="dark"; fi

# --- 5. 执行 Matugen ---
if [ "$NO_INDEX" = true ]; then
    # 终端交互模式：不带 index 参数
    matugen image "$WALLPAPER" -t "$STRATEGY" -m "$MODE"
else
    # 后台自动化模式：判断是固定 0 还是 随机/轮换
    FORCE_ZERO=false
    if [ -f "$INDEX_MODE_FILE" ]; then
        if [ "$(cat "$INDEX_MODE_FILE")" == "0" ]; then
            FORCE_ZERO=true
        fi
    fi

    if [ "$FORCE_ZERO" = true ]; then
        SELECTED_INDEX=0
    else
        # 探测有效 Index (0~5)
        VALID_INDICES=()
        for i in {0..5}; do
            if matugen image "$WALLPAPER" --source-color-index "$i" --dry-run &>/dev/null; then
                VALID_INDICES+=("$i")
            else
                break
            fi
        done

        if [ ${#VALID_INDICES[@]} -eq 0 ]; then
            SELECTED_INDEX=0 # 兜底
        else
            # 轮换/随机 核心逻辑
            LAST_WALL=""
            [ -f "$LAST_WALL_FILE" ] && LAST_WALL=$(cat "$LAST_WALL_FILE")
            
            if [ "$LAST_WALL" == "$WALLPAPER" ] && [ -f "$CURRENT_INDEX_FILE" ]; then
                # 相同壁纸：执行顺序轮换
                LAST_INDEX=$(cat "$CURRENT_INDEX_FILE")
                NEXT_POS=0
                
                # 查找上次的 index 在有效数组中的位置
                for j in "${!VALID_INDICES[@]}"; do
                    if [ "${VALID_INDICES[$j]}" == "$LAST_INDEX" ]; then
                        # 找到后，取下一个位置（取余数实现循环）
                        NEXT_POS=$(( (j + 1) % ${#VALID_INDICES[@]} ))
                        break
                    fi
                done
                SELECTED_INDEX=${VALID_INDICES[$NEXT_POS]}
            else
                # 新壁纸：第一次遇到，执行随机抽取
                RANDOM_INDEX=$((RANDOM % ${#VALID_INDICES[@]}))
                SELECTED_INDEX=${VALID_INDICES[$RANDOM_INDEX]}
            fi
            
            # 持久化当前状态
            echo "$WALLPAPER" > "$LAST_WALL_FILE"
            echo "$SELECTED_INDEX" > "$CURRENT_INDEX_FILE"
        fi
    fi
    
    # 带 index 参数执行
    matugen image "$WALLPAPER" -t "$STRATEGY" -m "$MODE" --source-color-index "$SELECTED_INDEX"
fi

if [ "$MODE" == "light" ]; then
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk"
else
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk"
    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
fi
