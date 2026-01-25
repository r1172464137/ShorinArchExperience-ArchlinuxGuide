#!/bin/bash

# ==============================================================================
# Shorin-Niri Updater Utility
# ==============================================================================
# 功能：备份 -> 更新(本地优先) -> 智能链接
# ==============================================================================

# --- 配置 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
BACKUP_ROOT="$HOME/.local/state/shorin-niri-backups"
# 必须包含 scripts 以便自我更新
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 颜色与日志 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${H_GREEN}[UPDATE]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[ATTENTION]${NC} $1"; }
error() { echo -e "${H_RED}[ERROR]${NC} $1"; exit 1; }

# --- 核心函数: 智能递归链接 ---
# 仅在链接不存在或错误时才执行操作，避免无效 IO
link_recursive() {
  local src_dir="$1"
  local dest_dir="$2"
  
  mkdir -p "$dest_dir"
  find "$src_dir" -mindepth 1 -maxdepth 1 -not -path '*/.git*' | while read -r src_path; do
    local item_name=$(basename "$src_path")
    local need_recurse=false

    # 判断是否需要递归穿透的系统目录
    if [ "$item_name" == ".config" ] || [ "$item_name" == ".local" ]; then
        need_recurse=true
    elif [[ "$src_dir" == *".local" ]] && { [ "$item_name" == "share" ] || [ "$item_name" == "bin" ]; }; then
        need_recurse=true
    fi

    if [ "$need_recurse" = true ]; then
        link_recursive "$src_path" "$dest_dir/$item_name"
    else
        local target_path="$dest_dir/$item_name"
        
        # [优化] 检查链接是否已经正确，如果是则跳过
        if [ -L "$target_path" ] && [ "$(readlink -f "$target_path")" == "$src_path" ]; then
            continue
        fi

        # 链接不存在或错误：清理旧文件并创建新链接
        if [ -e "$target_path" ] || [ -L "$target_path" ]; then
            rm -rf "$target_path"
        fi
        ln -sf "$src_path" "$target_path"
    fi
  done
}

# ==============================================================================
# 主逻辑开始
# ==============================================================================

if [ ! -d "$DOTFILES_REPO/.git" ]; then
    error "Repository not found at $DOTFILES_REPO."
fi

log "Starting Shorin-Niri Update..."
cd "$DOTFILES_REPO" || exit 1

# ------------------------------------------------------------------------------
# STEP 1: 物理备份 (Backup)
# ------------------------------------------------------------------------------
# 防止 Git 操作意外把文件搞丢，先全量备份
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_ROOT/full_backup_$TIMESTAMP.tar.gz"
mkdir -p "$BACKUP_ROOT"

log "Creating safety backup..."
tar --exclude='.git' -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
log "Backup saved to: $BACKUP_FILE"

# ------------------------------------------------------------------------------
# STEP 2: Git 更新 (本地优先策略)
# ------------------------------------------------------------------------------
log "Fetching updates from remote..."
git fetch origin "$BRANCH"

# 检测本地修改
HAS_LOCAL_CHANGES=false
if [ -n "$(git status --porcelain)" ]; then
    log "Local changes detected. Stashing them to apply updates..."
    # 暂存用户修改
    git stash push -m "Shorin_User_AutoUpdate_$TIMESTAMP"
    HAS_LOCAL_CHANGES=true
fi

# 刷新稀疏检出白名单
git config core.sparseCheckout true
SPARSE_FILE=".git/info/sparse-checkout"
truncate -s 0 "$SPARSE_FILE"
for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

# 拉取远程代码
if git pull --depth 1 --ff-only origin "$BRANCH"; then
    log "Core files downloaded successfully."
else
    error "Git pull failed. Please check your network connection."
fi

# 恢复用户修改
if [ "$HAS_LOCAL_CHANGES" = true ]; then
    log "Restoring your local changes..."
    
    # 尝试弹出暂存
    if ! git stash pop; then
        warn "Conflict detected between update and your changes."
        warn "Policy: KEEPING YOUR LOCAL CHANGES (Local Priority)."
        
        # --- 冲突解决: 本地优先 ---
        # 保留用户修改 (Theirs in stash context)，丢弃官方更新中冲突的部分
        git checkout --theirs .
        
        git add .
        git reset
        git stash drop
        
        success "Conflict resolved: Your customized files have been preserved."
    else
        success "Local changes merged successfully."
    fi
fi

# ------------------------------------------------------------------------------
# STEP 3: 智能链接 (Smart Link)
# ------------------------------------------------------------------------------
log "Verifying configuration links..."
link_recursive "$DOTFILES_REPO/dotfiles" "$HOME"

echo ""
log "Update Complete!"
echo -e "   - Backup location: $BACKUP_FILE"
