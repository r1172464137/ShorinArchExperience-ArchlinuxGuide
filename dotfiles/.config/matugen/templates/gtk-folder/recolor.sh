#!/usr/bin/env bash

# 作用：更改gtk文件夹颜色
# 逻辑：png图片由magick更改为灰色然后适应matugen颜色。svg图标已事先获取svg内的目标色，根据光影逻辑用sed适配matugen色。修改后的图标文件保存到~/.local/share/icons目录下，取名为Adwaita-Matugen，fallback是Adwaita。保存为A和B两份，在AB之间切换做到瞬间切换的效果。
# ==============================================================================
# 1. 颜色配置 (由 Matugen 填充)
# ==============================================================================

# [组 A] 文件夹与 Mimetype 使用的主色系 
COLOR_FOLDER_MAIN="{{colors.secondary_fixed_dim.default.hex}}"
COLOR_FOLDER_HIGHLIGHT="{{colors.secondary.default.hex}}"
COLOR_FOLDER_SHADOW="{{colors.secondary_container.default.hex}}"

# [组 B] 功能图标 (网络/垃圾桶) 使用的强调色系 
COLOR_ACCENT_MAIN="{{colors.tertiary.default.hex}}"
COLOR_ACCENT_LIGHT="{{colors.tertiary_fixed_dim.default.hex}}"
COLOR_ACCENT_DARK="{{colors.tertiary_container.default.hex}}"
COLOR_TRASH_PAPER="{{colors.tertiary_container.default.hex}}"

# ==============================================================================
# 2. 路径配置与 A/B 切换逻辑
# ==============================================================================

TEMPLATE_DIR="$HOME/.config/matugen/templates/gtk-folder/Adwaita-Matugen"

# 获取当前正在使用的主题名称，用于决定下一棒交给 A 还是 B
CURRENT_THEME_NAME=$(gsettings get org.gnome.desktop.interface icon-theme | tr -d "'")

if [[ "$CURRENT_THEME_NAME" == "Adwaita-Matugen-A" ]]; then
    TARGET_THEME_NAME="Adwaita-Matugen-B"
else
    TARGET_THEME_NAME="Adwaita-Matugen-A"
fi

TARGET_DIR="$HOME/.local/share/icons/$TARGET_THEME_NAME"

# ==============================================================================
# 3. 预编译 Sed 替换规则
#    (将复杂的正则预定义为变量，减少主循环开销，提升可读性)
# ==============================================================================

# 规则集：文件夹 (Folders)
# 将 Adwaita 原版蓝色的各个层级映射到 Primary 色系
SED_CMD_FOLDERS="
s/#a4caee/$COLOR_FOLDER_MAIN/g;
s/#438de6/$COLOR_FOLDER_SHADOW/g;
s/#62a0ea/$COLOR_FOLDER_SHADOW/g;
s/#afd4ff/$COLOR_FOLDER_HIGHLIGHT/g;
s/#c0d5ea/$COLOR_FOLDER_HIGHLIGHT/g"

# 规则集：网络 (Network)
# 将 Adwaita 复杂的 14 色蓝灰光影映射到 Tertiary 色系
SED_CMD_NETWORK="
s/#62a0ea/$COLOR_ACCENT_LIGHT/g;
s/#1c71d8/$COLOR_ACCENT_MAIN/g;
s/#c0bfbc/$COLOR_ACCENT_MAIN/g;
s/#1a5fb4/$COLOR_ACCENT_DARK/g;
s/#14498a/$COLOR_ACCENT_DARK/g;
s/#9a9996/$COLOR_ACCENT_DARK/g;
s/#77767b/$COLOR_FOLDER_SHADOW/g;
s/#241f31/$COLOR_FOLDER_SHADOW/g;
s/#3d3846/$COLOR_FOLDER_SHADOW/g;
s/#434348/$COLOR_FOLDER_SHADOW/g;
s/#4e475a/$COLOR_FOLDER_SHADOW/g;
s/#716881/$COLOR_FOLDER_SHADOW/g;
s/#79718e/$COLOR_FOLDER_SHADOW/g;
s/#847a96/$COLOR_FOLDER_SHADOW/g"

# 规则集：垃圾桶 (Trash)
# 将绿色系映射到 Tertiary 色系，并处理废纸颜色
SED_CMD_TRASH="
s/#2ec27e/$COLOR_ACCENT_MAIN/g;
s/#33d17a/$COLOR_ACCENT_MAIN/g;
s/#26a269/$COLOR_ACCENT_DARK/g;
s/#26a168/$COLOR_ACCENT_DARK/g;
s/#9a9996/$COLOR_ACCENT_DARK/g;
s/#c3c2bc/$COLOR_ACCENT_DARK/g;
s/#42d390/$COLOR_ACCENT_LIGHT/g;
s/#ffffff/$COLOR_TRASH_PAPER/g;
s/#deddda/$COLOR_TRASH_PAPER/g;
s/#f6f5f4/$COLOR_TRASH_PAPER/g;
s/#e8e7e8/$COLOR_TRASH_PAPER/g;
s/#eeedec/$COLOR_TRASH_PAPER/g;
s/#efeeed/$COLOR_TRASH_PAPER/g;
s/#77767b/$COLOR_FOLDER_SHADOW/g"

# ==============================================================================
# 4. 执行核心流程 (极致性能优化)
# ==============================================================================

# [步骤 1] 极速 IO 重置
# 使用 mkdir -p 避免检查逻辑
# 使用 --reflink=auto 利用文件系统的写时复制特性 (CoW)，实现瞬间零拷贝
mkdir -p "$TARGET_DIR"
cp -rf --reflink=auto --no-preserve=mode,ownership "$TEMPLATE_DIR/"* "$TARGET_DIR/"
sed -i "s/Name=.*/Name=$TARGET_THEME_NAME/" "$TARGET_DIR/index.theme"

# [步骤 2] PNG 批量处理 (CPU 密集型)
# 使用 xargs -P0 自动检测 CPU 核心数，满载多进程并发处理
# 避免使用 while read 循环，减少 shell 解释器开销
find "$TARGET_DIR" -name "*.png" -print0 | xargs -0 -P0 -I {} magick "{}" \
    -channel RGB \
    -colorspace gray \
    -sigmoidal-contrast 10,50% \
    +level-colors "$COLOR_FOLDER_SHADOW","$COLOR_FOLDER_MAIN" \
    +channel \
    "{}"

# [步骤 3] SVG 批量处理 (IO/CPU 混合型)
# 使用 xargs 批量传递文件名给 sed，大幅减少 sed 进程启动次数 (O(N) -> O(1))
# 文件夹策略: 包含常规文件夹、用户目录、以及 Mimetype 目录
find "$TARGET_DIR/scalable" \
    \( -name "folder*.svg" \
    -o -name "user-home*.svg" \
    -o -name "user-desktop*.svg" \
    -o -name "user-bookmarks*.svg" \
    -o -name "inode-directory*.svg" \) \
    -print0 | xargs -0 -P0 sed -i "$SED_CMD_FOLDERS"

# 网络图标策略
find "$TARGET_DIR/scalable" -name "network*.svg" \
    -print0 | xargs -0 -P0 sed -i --follow-symlinks "$SED_CMD_NETWORK"

# 垃圾桶策略
find "$TARGET_DIR/scalable" -name "user-trash*.svg" \
    -print0 | xargs -0 -P0 sed -i --follow-symlinks "$SED_CMD_TRASH"

# [步骤 4] 原子化切换
# 直接修改 GSettings，GTK 会自动检测到主题变更并瞬间重绘
gsettings set org.gnome.desktop.interface icon-theme "$TARGET_THEME_NAME"

# 2. [新增] 同步 Flatpak 图标设置 (动态更新 override)
# 这会告诉所有 Flatpak 程序：现在的图标主题是这个 A 或 B
flatpak override --user --env=ICON_THEME="$TARGET_THEME_NAME"

exit 0
