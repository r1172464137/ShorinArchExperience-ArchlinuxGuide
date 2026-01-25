#!/bin/bash

# ==============================================================================
# Shorin-Niri 更新工具 (全量备份版)
# ==============================================================================

# --- 配置区域 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
# 备份路径：使用缓存目录
BACKUP_ROOT="$HOME/.cache/shorin-niri-update"
# 备份文件名：固定名称，每次覆盖
BACKUP_FILE="$BACKUP_ROOT/backup.tar.gz"

# 必须包含 scripts 目录以便自我更新
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 颜色与日志 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; H_BLUE='\033[1;34m'; NC='\033[0m'

log() { echo -e "${H_BLUE}[Log]${NC} $1"; }
success() { echo -e "${H_GREEN}[Success]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[Warn]${NC} $1"; }
error() { echo -e "${H_RED}[Error]${NC} $1"; exit 1; }

# --- 核心函数: 智能递归链接 ---
link_recursive() {
  local src_dir="$1"
  local dest_dir="$2"
  
  mkdir -p "$dest_dir"
  find "$src_dir" -mindepth 1 -maxdepth 1 -not -path '*/.git*' | while read -r src_path; do
    local item_name=$(basename "$src_path")
    local need_recurse=false

    if [ "$item_name" == ".config" ] || [ "$item_name" == ".local" ]; then
        need_recurse=true
    elif [[ "$src_dir" == *".local" ]] && { [ "$item_name" == "share" ] || [ "$item_name" == "bin" ]; }; then
        need_recurse=true
    fi

    if [ "$need_recurse" = true ]; then
        link_recursive "$src_path" "$dest_dir/$item_name"
    else
        local target_path="$dest_dir/$item_name"
        if [ -L "$target_path" ] && [ "$(readlink -f "$target_path")" == "$src_path" ]; then
            continue
        fi
        if [ -e "$target_path" ] || [ -L "$target_path" ]; then
            rm -rf "$target_path"
        fi
        ln -sf "$src_path" "$target_path"
    fi
  done
}

# ==============================================================================
# 主逻辑
# ==============================================================================

if [ ! -d "$DOTFILES_REPO/.git" ]; then
    error "在 $DOTFILES_REPO 未找到仓库，请检查路径。"
fi

log "正在启动 Shorin-Niri 更新程序..."
cd "$DOTFILES_REPO" || exit 1

# ------------------------------------------------------------------------------
# 步骤 1: 物理备份 (Backup)
# ------------------------------------------------------------------------------
mkdir -p "$BACKUP_ROOT"

log "正在创建全量安全备份（包含 Git 历史）..."
# 修改点：去掉了 --exclude='.git'，备份整个目录
tar -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
success "备份已完成"

# ------------------------------------------------------------------------------
# 步骤 2: Git 更新 (Rebase + 自动身份修正)
# ------------------------------------------------------------------------------
log "正在检查远程更新..."
git fetch origin "$BRANCH"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HASH" == "$REMOTE_HASH" ]; then
    success "当前已是最新版本，无需更新。"
else
    # 检测本地修改
    HAS_LOCAL_CHANGES=false
    if [ -n "$(git status --porcelain)" ]; then
        HAS_LOCAL_CHANGES=true
        warn "检测到本地有修改，正在应用智能合并策略（保留您的修改）..."
        
        # 自动配置 Git 身份，防止 commit 失败
        if [ -z "$(git config user.email)" ]; then
            log "未检测到 Git 身份信息，正在设置临时身份以完成更新..."
            git config user.email "updater@shorin.local"
            git config user.name "Shorin Updater"
        fi
        
        # 1. 创建临时提交
        git add -A
        if ! git commit -m "TEMP_AUTO_UPDATE_SAVE" --quiet; then
             error "无法创建临时提交，请手动检查 git 状态。"
        fi
    fi

    # 刷新稀疏检出
    git config core.sparseCheckout true
    SPARSE_FILE=".git/info/sparse-checkout"
    truncate -s 0 "$SPARSE_FILE"
    for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

    # 2. 执行 Rebase 更新
    log "正在下载并合并核心文件..."
    if git pull --rebase -Xtheirs origin "$BRANCH"; then
        success "核心文件更新成功。"
    else
        git rebase --abort 2>/dev/null
        error "更新过程中发生冲突。已自动还原变更，请手动检查。"
    fi

    # 3. 恢复现场
    if [ "$HAS_LOCAL_CHANGES" = true ]; then
        log "正在恢复您的本地修改..."
        
        # 撤销那个临时的提交，保留文件内容
        git reset --soft HEAD~1
        git reset
        
        success "您的本地修改已重新应用。"
    fi
fi

# ------------------------------------------------------------------------------
# 步骤 3: 智能链接
# ------------------------------------------------------------------------------
log "正在验证并刷新配置文件链接..."
link_recursive "$DOTFILES_REPO/dotfiles" "$HOME"

echo ""
echo -e "${H_GREEN}========================================${NC}"
echo -e "${H_GREEN}          更新全部完成！                ${NC}"
echo -e "${H_GREEN}========================================${NC}"
echo -e "${H_BLUE}[备份信息]${NC} 全量备份文件位置: $BACKUP_FILE"
if [ "$HAS_LOCAL_CHANGES" = true ]; then
    echo -e "${H_YELLOW}[提示]${NC} 您的本地修改已保留在工作区中。"
fi