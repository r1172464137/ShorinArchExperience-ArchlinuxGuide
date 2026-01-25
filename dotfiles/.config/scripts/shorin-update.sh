#!/bin/bash

# ==============================================================================
# Shorin-Niri Updater
# ==============================================================================

# --- 配置 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
BACKUP_ROOT="$HOME/.cache/shorin-niri-update"
BACKUP_FILE="$BACKUP_ROOT/backup.tar.gz"
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 样式 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; H_BLUE='\033[1;34m'; NC='\033[0m'

log() { echo -e "${H_BLUE}[信息]${NC} $1"; }
success() { echo -e "${H_GREEN}[成功]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[注意]${NC} $1"; }
error() { echo -e "${H_RED}[错误]${NC} $1"; exit 1; }

# --- 链接函数 ---
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
# 主流程
# ==============================================================================

if [ ! -d "$DOTFILES_REPO/.git" ]; then
    error "未找到仓库: $DOTFILES_REPO"
fi

cd "$DOTFILES_REPO" || exit 1

# 1. 备份
mkdir -p "$BACKUP_ROOT"
log "正在创建备份..."
tar -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
success "备份完成"

# 2. 更新
log "检查更新..."
git fetch --depth 1 origin "$BRANCH"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HASH" == "$REMOTE_HASH" ]; then
    success "已是最新版本"
else
    HAS_LOCAL_CHANGES=false
    if [ -n "$(git status --porcelain)" ]; then
        HAS_LOCAL_CHANGES=true
        warn "检测到本地修改，准备合并..."
        
        if [ -z "$(git config user.email)" ]; then
            git config user.email "updater@shorin.local"
            git config user.name "Shorin Updater"
        fi
        
        git add -A
        git commit -m "TEMP_SAVE" --quiet || error "无法创建临时提交"
    fi

    git config core.sparseCheckout true
    SPARSE_FILE=".git/info/sparse-checkout"
    truncate -s 0 "$SPARSE_FILE"
    for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

    log "正在下载并合并..."
    if git pull --rebase -Xtheirs origin "$BRANCH"; then
        success "核心更新成功"
    else
        git rebase --abort 2>/dev/null
        error "更新冲突，已还原，请手动检查。"
    fi

    if [ "$HAS_LOCAL_CHANGES" = true ]; then
        log "恢复本地修改..."
        git reset --soft HEAD~1
        git reset
        success "本地修改已恢复"
    fi
fi

# 3. 链接
log "刷新配置链接..."
link_recursive "$DOTFILES_REPO/dotfiles" "$HOME"

# 4. 清理
log "清理仓库..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive 2>/dev/null

echo ""
echo -e "${H_GREEN}更新完成${NC}"
echo -e "${H_BLUE}备份路径:${NC} $BACKUP_FILE"