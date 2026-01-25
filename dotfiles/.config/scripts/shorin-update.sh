#!/bin/bash

# ==============================================================================
# Shorin-Niri 更新工具 (极简体积版)
# ==============================================================================

# --- 配置区域 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
BACKUP_ROOT="$HOME/.cache/shorin-niri-update"
BACKUP_FILE="$BACKUP_ROOT/backup.tar.gz"
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 颜色与日志 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; H_BLUE='\033[1;34m'; NC='\033[0m'

log() { echo -e "${H_BLUE}[信息]${NC} $1"; }
success() { echo -e "${H_GREEN}[成功]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[注意]${NC} $1"; }
error() { echo -e "${H_RED}[错误]${NC} $1"; exit 1; }

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
# 步骤 1: 物理备份
# ------------------------------------------------------------------------------
mkdir -p "$BACKUP_ROOT"
log "正在创建安全备份..."
tar -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
success "备份已完成"

# ------------------------------------------------------------------------------
# 步骤 2: Git 更新 (浅克隆 + 本地优先)
# ------------------------------------------------------------------------------
log "正在检查远程更新..."

# [修改点] 使用 --depth 1 只获取最新的 1 个提交
# 这会将你的仓库转换为"浅仓库"(Shallow Repository)
git fetch --depth 1 origin "$BRANCH"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HASH" == "$REMOTE_HASH" ]; then
    success "当前已是最新版本，无需更新。"
else
    HAS_LOCAL_CHANGES=false
    if [ -n "$(git status --porcelain)" ]; then
        HAS_LOCAL_CHANGES=true
        warn "检测到本地有修改，正在应用智能合并策略..."
        
        if [ -z "$(git config user.email)" ]; then
            log "未检测到 Git 身份信息，正在设置临时身份..."
            git config user.email "updater@shorin.local"
            git config user.name "Shorin Updater"
        fi
        
        git add -A
        if ! git commit -m "TEMP_AUTO_UPDATE_SAVE" --quiet; then
             error "无法创建临时提交，请手动检查 git 状态。"
        fi
    fi

    git config core.sparseCheckout true
    SPARSE_FILE=".git/info/sparse-checkout"
    truncate -s 0 "$SPARSE_FILE"
    for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

    log "正在下载并合并核心文件..."
    # [修改点] 即使是浅克隆，rebase 也是依然有效的
    if git pull --rebase -Xtheirs origin "$BRANCH"; then
        success "核心文件更新成功。"
    else
        git rebase --abort 2>/dev/null
        error "更新冲突，已自动还原。请手动检查。"
    fi

    if [ "$HAS_LOCAL_CHANGES" = true ]; then
        log "正在恢复您的本地修改..."
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

# ------------------------------------------------------------------------------
# 步骤 4: 强力瘦身 (Aggressive Cleaning)
# ------------------------------------------------------------------------------
log "正在执行仓库强力瘦身（只保留最新版本）..."

# [修改点] 强力清理指令
# 1. expire=now: 立即让所有历史记录过期
# 2. prune=now: 立即删除所有过期的数据
# 3. aggressive: 即使花费更多 CPU 时间，也要压缩到最小
git reflog expire --expire=now --all
git gc --prune=now --aggressive 2>/dev/null

success "仓库维护完成，体积已最小化。"

echo ""
echo -e "${H_GREEN}========================================${NC}"
echo -e "${H_GREEN}          更新全部完成！                ${NC}"
echo -e "${H_GREEN}========================================${NC}"
echo -e "${H_BLUE}[备份信息]${NC} 全量备份文件位置: $BACKUP_FILE"
if [ "$HAS_LOCAL_CHANGES" = true ]; then
    echo -e "${H_YELLOW}[提示]${NC} 您的本地修改已保留在工作区中。"
fi