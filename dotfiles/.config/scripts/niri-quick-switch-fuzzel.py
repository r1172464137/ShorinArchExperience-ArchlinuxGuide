#!/usr/bin/env python3

import subprocess
import json
import sys
import shutil
import os

# ================= Configuration =================
# 排除列表：把 fuzzel 自己也加进去，防止套娃
EXCLUDE_APPS = ["fuzzel", "quick-switch", "niri-quick-switch"]

# Fuzzel 参数配置
# --dmenu: 必须，表示读取标准输入
# --index: 关键！让 fuzzel 返回选中的行号，而不是文本
FUZZEL_ARGS = [
    "--dmenu",
    "--index",              
    "--width", "60",        # 宽度字符数
    "--lines", "15",        # 显示行数
    "--prompt", "Switch: ", 
    "--placeholder", "Search windows..."
]
# =================================================

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0: return None
        if "-j" in cmd:
            return json.loads(result.stdout)
        return result.stdout
    except Exception: return None

def get_active_workspace_id():
    workspaces = run_cmd("niri msg -j workspaces")
    if not workspaces: return None
    for ws in workspaces:
        if ws.get("is_focused"): return ws.get("id")
    return None

def get_window_sort_key(w):
    """
    核心视觉排序逻辑 (与 FZF 版一致)
    """
    # 浮动窗口沉底
    if w.get("is_floating"):
        return (99999, 0, w.get("id"))

    try:
        layout = w.get("layout", {})
        if not layout: return (9999, 0, w.get("id"))
        
        # 读取 pos_in_scrolling_layout [列, 行]
        pos = layout.get("pos_in_scrolling_layout")
        if pos and isinstance(pos, list) and len(pos) >= 2:
            return (pos[0], pos[1], w.get("id"))
            
    except Exception:
        pass

    return (9999, 0, w.get("id"))

def main():
    if not shutil.which("fuzzel"):
        # 如果没装 fuzzel，弹个窗提示一下
        subprocess.run(["notify-send", "Error", "Fuzzel not found"])
        sys.exit(1)

    ws_id = get_active_workspace_id()
    if ws_id is None: sys.exit(1)

    windows = run_cmd("niri msg -j windows")
    if not windows: sys.exit(0)

    # 1. 筛选
    current_windows = []
    for w in windows:
        if w.get("workspace_id") != ws_id:
            continue
        
        app_id = w.get("app_id") or ""
        if app_id in EXCLUDE_APPS:
            continue
            
        current_windows.append(w)

    if not current_windows: sys.exit(0)

    # 2. 排序 (Visual Sort)
    current_windows.sort(key=get_window_sort_key)

    # 3. 构建列表
    input_str = ""
    # 我们不需要 mapping 字典了，因为 fuzzel --index 返回的索引
    # 直接对应 current_windows 列表的下标
    
    for w in current_windows:
        app_id = w.get("app_id") or "Wayland"
        title = w.get("title", "No Title").replace("\n", " ")
        
        # 格式: [AppID] Title
        display_str = f"[{app_id}] {title}"
        
        # Fuzzel 图标魔法: \0icon\x1f + 图标名
        # 这样 fuzzel 就会自动去系统里找 app_id 对应的图标显示在左侧
        line = f"{display_str}\0icon\x1f{app_id}"
        
        input_str += f"{line}\n"

    # 4. 运行 Fuzzel
    try:
        proc = subprocess.Popen(
            ["fuzzel"] + FUZZEL_ARGS,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True
        )
        stdout, _ = proc.communicate(input=input_str)

        if stdout.strip():
            # 获取索引 (例如 "2")
            selected_idx = int(stdout.strip())
            
            # 安全检查
            if 0 <= selected_idx < len(current_windows):
                target_window = current_windows[selected_idx]
                target_id = target_window.get("id")
                
                # 切换窗口
                subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(target_id)])

    except Exception:
        pass

if __name__ == "__main__":
    main()
