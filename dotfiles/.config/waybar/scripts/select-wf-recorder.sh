#!/usr/bin/env bash
set -Eeuo pipefail

# ========== 可调参数（也可用环境变量覆盖） ==========
CODEC="${CODEC:-h264_vaapi}"        # 例：h264_vaapi / libx264
FRAMERATE="${FRAMERATE:-}"        # 例：60；留空则不限制
AUDIO="${AUDIO:-on}"                # on/off 或指定节点（--audio=XXX）
TITLE="${TITLE:-}"                  # 文件名标记

# ===============================================

command -v wf-recorder >/dev/null || { echo "未找到 wf-recorder"; exit 1; }
command -v slurp >/dev/null       || { echo "未找到 slurp（用于框选区域）"; exit 1; }
command -v xdg-user-dir >/dev/null || true
command -v notify-send >/dev/null  || true

VIDEOS_DIR="$(xdg-user-dir VIDEOS 2>/dev/null || true)"
VIDEOS_DIR="${VIDEOS_DIR:-"$HOME/Videos"}"
SAVE_DIR="${SAVE_DIR:-"$VIDEOS_DIR/wf-recorder"}"
mkdir -p "$SAVE_DIR"

ts="$(date +'%Y-%m-%d-%H%M%S')"
safe_title="${TITLE// /_}"
base="$ts${safe_title:+-$safe_title}"
SAVE_PATH="$SAVE_DIR/$base.mp4"

# 选区：优先用 REC_AREA，否则调用 slurp 获取
if [[ -n "${REC_AREA:-}" ]]; then
  GEOM="$REC_AREA"
else
  GEOM="$(slurp || true)"
fi
# 去掉多余空白
GEOM="$(echo -n "$GEOM" | tr -s '[:space:]' ' ')"
if [[ -z "${GEOM// /}" ]]; then
  echo "已取消选择区域。"
  exit 130
fi

# 构造参数
args=( --file "$SAVE_PATH" -c "$CODEC" -g "$GEOM" )

# 音频：on/off/或具体节点
case "$AUDIO" in
  off|OFF|0|false) ;;  # 不加 --audio
  on|ON|1|true|"") args+=( --audio ) ;;
  *)               args+=( --audio="$AUDIO" ) ;;
esac

# 帧率：仅正整数时追加
if [[ -n "$FRAMERATE" ]]; then
  if [[ "$FRAMERATE" =~ ^[0-9]+$ && "$FRAMERATE" -gt 0 ]]; then
    args+=( --framerate "$FRAMERATE" )
  else
    echo "警告：FRAMERATE=\"$FRAMERATE\" 非法，已忽略。" >&2
  fi
fi

# 编码器专属滤镜
if [[ "$CODEC" == *"_vaapi" ]]; then
  args+=( -F "scale_vaapi=format=nv12:out_range=full:out_color_primaries=bt709" )
else
  args+=( -F "format=yuv420p" )
fi

# 结束时提示并维护 latest.mp4
notify() { command -v notify-send >/dev/null && notify-send "wf-recorder" "$1"; }
finish() {
  code=$?
  if [[ $code -eq 0 ]]; then
    ln -sf "$(basename "$SAVE_PATH")" "$SAVE_DIR/latest.mp4" || true
    msg="已保存：$SAVE_PATH"
  else
    msg="录制中断（退出码 $code）。"
  fi
  echo "$msg"
  notify "$msg"
}
trap finish EXIT

echo "开始录制（区域 $GEOM）→ $SAVE_PATH"
wf-recorder "${args[@]}"
