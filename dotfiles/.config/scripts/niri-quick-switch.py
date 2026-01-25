#!/usr/bin/env python3

import subprocess
import json
import sys
import shutil

# ================= Configuration =================
FUZZEL_WIDTH = 80       
FUZZEL_LINES = 15       
PROMPT = "Switch: "
# =================================================

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0: return None
        return json.loads(result.stdout)
    except Exception: return None

def get_active_workspace_id():
    workspaces = run_cmd("niri msg -j workspaces")
    if not workspaces: return None
    for ws in workspaces:
        if ws.get("is_focused"): return ws.get("id")
    return None

def main():
    if not shutil.which("fuzzel"): sys.exit(1)

    ws_id = get_active_workspace_id()
    if ws_id is None:
        subprocess.run(["notify-send", "Niri Overview", "Error: No active workspace"])
        sys.exit(1)

    windows = run_cmd("niri msg -j windows")
    if not windows: sys.exit(0)

    # 1. 筛选当前工作区窗口
    current_windows = [w for w in windows if w.get("workspace_id") == ws_id]
    if not current_windows: sys.exit(0)

    # 2. 排序 (这步很重要，保证列表顺序和内存中的列表一致，以便通过索引查找)
    current_windows.sort(key=lambda x: x.get("id", 0))

    # 3. 生成列表
    fuzzel_input = ""
    for w in current_windows:
        app_id = w.get("app_id") or "Wayland"
        
        # 去掉换行符，保持单行整洁
        title = w.get("title", "No Title").replace("\n", " ")
        
        # ==========================================================
        # V8 风格：[AppID] Title
        # 极简，无 ID，无多余符号
        # ==========================================================
        display_str = f"[{app_id}] {title}"
        
        fuzzel_input += f"{display_str}\0icon\x1f{app_id}\n"

    try:
        proc = subprocess.Popen(
            [
                "fuzzel", 
                "-d", 
                "--index",              # <--- 关键修改：让 fuzzel 返回选中的行号(0, 1, 2...)
                "--width", str(FUZZEL_WIDTH), 
                "--lines", str(FUZZEL_LINES),
                "--prompt", PROMPT,
                "--placeholder", "Search windows..."
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True
        )
        stdout, _ = proc.communicate(input=fuzzel_input)

        if stdout.strip():
            # 4. 通过行号反查 ID
            # Fuzzel 返回的是索引 (例如 "2")，我们去 current_windows[2] 里找对应的 ID
            selected_index = int(stdout.strip())
            
            if 0 <= selected_index < len(current_windows):
                target_window = current_windows[selected_index]
                target_id = target_window.get("id")
                
                # 发送聚焦命令
                subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(target_id)])

    except Exception:
        pass

if __name__ == "__main__":
    main()
