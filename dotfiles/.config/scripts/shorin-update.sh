#!/bin/bash

# ==============================================================================
# Shorin-Niri Updater Utility (Auto-Identity Fix)
# ==============================================================================

# --- 配置区域 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
BACKUP_ROOT="$HOME/.local/state/shorin-niri-backups"
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 颜色与日志 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; H_BLUE='\033[1;34m'; NC='\033[0m'

log() { echo -e "${H_BLUE}[INFO]${NC} $1"; }
success() { echo -e "${H_GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${H_RED}[ERROR]${NC} $1"; exit 1; }

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
    error "Repository not found at $DOTFILES_REPO."
fi

log "Starting Shorin-Niri Update..."
cd "$DOTFILES_REPO" || exit 1

# ------------------------------------------------------------------------------
# STEP 1: 物理备份 (Backup)
# ------------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_ROOT/backup_$TIMESTAMP.tar.gz"
mkdir -p "$BACKUP_ROOT"

log "Creating safety backup..."
tar --exclude='.git' -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
success "Backup saved to: $BACKUP_FILE"

# ------------------------------------------------------------------------------
# STEP 2: Git 更新 (Rebase + 自动身份修正)
# ------------------------------------------------------------------------------
log "Fetching updates from remote..."
git fetch origin "$BRANCH"

LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HASH" == "$REMOTE_HASH" ]; then
    success "You are already up to date."
else
    # 检测本地修改
    HAS_LOCAL_CHANGES=false
    if [ -n "$(git status --porcelain)" ]; then
        HAS_LOCAL_CHANGES=true
        warn "Local changes detected. Applying rebase strategy..."
        
        # [修复点] 自动配置 Git 身份，防止 commit 失败
        if [ -z "$(git config user.email)" ]; then
            log "No git identity found. Setting temporary local identity..."
            git config user.email "updater@shorin.local"
            git config user.name "Shorin Updater"
        fi
        
        # 1. 创建临时提交
        git add -A
        # 尝试提交，如果失败则报错退出
        if ! git commit -m "TEMP_AUTO_UPDATE_SAVE_$TIMESTAMP" --quiet; then
             error "Failed to create temporary commit. Please check git status."
        fi
    fi

    # 刷新稀疏检出
    git config core.sparseCheckout true
    SPARSE_FILE=".git/info/sparse-checkout"
    truncate -s 0 "$SPARSE_FILE"
    for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

    # 2. 执行 Rebase 更新
    log "Merging updates..."
    if git pull --rebase -Xtheirs origin "$BRANCH"; then
        success "Core files downloaded and merged."
    else
        git rebase --abort 2>/dev/null
        error "Update failed. Restored via 'git rebase --abort'. Please check manually."
    fi

    # 3. 恢复现场
    if [ "$HAS_LOCAL_CHANGES" = true ]; then
        log "Restoring your local modification state..."
        
        # 撤销那个临时的提交，保留文件内容
        git reset --soft HEAD~1
        git reset
        
        success "Your local changes have been reapplied."
    fi
fi

# ------------------------------------------------------------------------------
# STEP 3: 智能链接
# ------------------------------------------------------------------------------
log "Verifying configuration links..."
link_recursive "$DOTFILES_REPO/dotfiles" "$HOME"

echo ""
echo -e "${H_GREEN}Update Completed Successfully!${NC}"