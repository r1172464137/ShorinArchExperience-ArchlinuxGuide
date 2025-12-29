#!/bin/bash

# --- 参数定义 ---
WALLPAPER="$1"
CACHE_DIR="$HOME/.cache/matugen-strategy"
TYPE_FILE="$CACHE_DIR/type"
MODE_FILE="$CACHE_DIR/mode"
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"

# --- 1. 获取壁纸路径 (智能判定逻辑) ---
if [ -z "$WALLPAPER" ]; then
    # 优先读取 Waypaper 配置
    if [ -f "$WAYPAPER_CONFIG" ]; then
        WP_PATH=$(grep "^wallpaper =" "$WAYPAPER_CONFIG" | cut -d "=" -f 2 | xargs)
        if [ -n "$WP_PATH" ] && [ -f "$WP_PATH" ]; then
            WALLPAPER="$WP_PATH"
        fi
    fi

    # 备选 swww
    if [ -z "$WALLPAPER" ] && command -v swww &>/dev/null; then
         DETECTED_WALL=$(swww query | head -n 1 | cut -d ":" -f2- | xargs)
         if [ -f "$DETECTED_WALL" ]; then
            WALLPAPER="$DETECTED_WALL"
         fi
    fi
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    notify-send "Matugen Error" "无法找到壁纸路径。"
    exit 1
fi

# --- 2. 读取策略 (Type) ---
# 如果文件存在读取，否则默认 tonal-spot
if [ -f "$TYPE_FILE" ]; then
    STRATEGY=$(cat "$TYPE_FILE")
else
    STRATEGY="scheme-tonal-spot"
fi

# --- 3. 读取模式 (Mode) ---
# 如果文件存在读取，否则默认 dark
if [ -f "$MODE_FILE" ]; then
    MODE=$(cat "$MODE_FILE")
else
    MODE="dark"
fi

# --- 4. 执行 Matugen ---
# 同时传入 -t (策略) 和 -m (亮暗模式)
matugen image "$WALLPAPER" -t "$STRATEGY" -m "$MODE"