#!/bin/bash

# --- 本地化配置 ---
if env | grep -q "zh_CN"; then
    MSG_CLEAN_OK="旧存档已清理"
    MSG_CLEAN_FAIL="错误：清理失败"
    MSG_SAVE_OK="已快速存档"
    MSG_SAVE_FAIL="错误：存档失败"
else
    MSG_CLEAN_OK="Old save files cleaned."
    MSG_CLEAN_FAIL="ERROR: Clean process failed."
    MSG_SAVE_OK="Quicksaved."
    MSG_SAVE_FAIL="ERROR: Quicksave failed."
fi

# --- 执行清理 ---
if snapper -c root cleanup number && snapper -c home cleanup number; then
    notify-send "$MSG_CLEAN_OK"
else
    notify-send -u critical "$MSG_CLEAN_FAIL"
fi

# --- 执行存档 ---
if snapper -c root create --description "quicksave" --cleanup-algorithm number && \
   snapper -c home create --description "quicksave" --cleanup-algorithm number; then
    notify-send "$MSG_SAVE_OK"
else
    notify-send -u critical "$MSG_SAVE_FAIL"
fi
