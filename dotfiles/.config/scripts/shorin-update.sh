#!/bin/bash

# ==============================================================================
# Shorin-Niri Updater Utility (Rebase Strategy Edition)
# ==============================================================================
# 核心策略：
# 1. 全量备份：防止任何意外。
# 2. 智能更新：使用 git rebase -Xtheirs。
#    - 官方新增的代码：会自动合并进来。
#    - 冲突的代码：无条件保留你的本地修改。
# 3. 状态还原：更新结束后，将你的修改恢复为"未提交"状态，保持 Git 状态清晰。
# ==============================================================================

# --- 配置区域 ---
DOTFILES_REPO="$HOME/.local/share/shorin-niri"
BACKUP_ROOT="$HOME/.local/state/shorin-niri-backups"
# 必须包含 scripts 目录以便自我更新
TARGET_DIRS=("dotfiles" "wallpapers") 
BRANCH="main"

# --- 颜色与工具函数 ---
H_RED='\033[1;31m'; H_GREEN='\033[1;32m'; H_YELLOW='\033[1;33m'; H_BLUE='\033[1;34m'; NC='\033[0m'

log() { echo -e "${H_BLUE}[INFO]${NC} $1"; }
success() { echo -e "${H_GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${H_YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${H_RED}[ERROR]${NC} $1"; exit 1; }

# --- 核心函数: 智能递归链接 ---
# 保持你原有的逻辑，这对于特定目录结构很有效
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
        # 仅在实际操作时打印，减少刷屏
        # echo "Linked: $item_name" 
    fi
  done
}

# ==============================================================================
# 主逻辑
# ==============================================================================

# 0. 预检查
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
# 使用 tar 排除 .git 目录，只备份文件内容
tar --exclude='.git' -czf "$BACKUP_FILE" -C "$DOTFILES_REPO" . 2>/dev/null
if [ $? -eq 0 ]; then
    success "Backup saved to: $BACKUP_FILE"
else
    warn "Backup failed! Proceeding with caution..."
fi

# ------------------------------------------------------------------------------
# STEP 2: Git 更新 (Rebase + Local Priority 策略)
# ------------------------------------------------------------------------------
log "Fetching updates from remote..."
git fetch origin "$BRANCH"

# 检查是否有更新
LOCAL_HASH=$(git rev-parse HEAD)
REMOTE_HASH=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL_HASH" == "$REMOTE_HASH" ]; then
    success "You are already up to date."
    # 即使没更新，也继续执行链接步骤，防止用户误删了链接
else
    # 检测本地修改
    HAS_LOCAL_CHANGES=false
    if [ -n "$(git status --porcelain)" ]; then
        HAS_LOCAL_CHANGES=true
        warn "Local changes detected. Applying rebase strategy..."
        
        # 1. 创建临时提交 (Temp Commit)
        # 这样 Git 才能在 rebase 过程中追踪文件变更
        git add -A
        git commit -m "TEMP_AUTO_UPDATE_SAVE_$TIMESTAMP" --quiet
    fi

    # 刷新稀疏检出白名单 (保留原有逻辑)
    git config core.sparseCheckout true
    SPARSE_FILE=".git/info/sparse-checkout"
    truncate -s 0 "$SPARSE_FILE"
    for item in "${TARGET_DIRS[@]}"; do echo "$item" >> "$SPARSE_FILE"; done

    # 2. 执行 Rebase 更新
    # --rebase: 将本地提交移动到远程提交之上
    # -Xtheirs: 极其重要！在 rebase 上下文中，"theirs" 代表当前分支(你的修改)。
    #           这意味着：如果发生冲突，保留你的修改，丢弃官方的。
    log "Merging updates..."
    if git pull --rebase -Xtheirs origin "$BRANCH"; then
        success "Core files downloaded and merged."
    else
        # 如果 Rebase 极其罕见地失败了（通常是二进制文件冲突），尝试终止
        git rebase --abort 2>/dev/null
        error "Update failed due to complex conflicts. Restored via 'git rebase --abort'. Please check manually."
    fi

    # 3. 恢复现场 (Soft Reset)
    if [ "$HAS_LOCAL_CHANGES" = true ]; then
        log "Restoring your local modification state..."
        
        # HEAD~1 指向更新后的官方代码
        # --soft 撤销刚才的"临时提交"，但把修改的文件保留在暂存区(Staged)
        git reset --soft HEAD~1
        
        # 再次 reset 把文件从暂存区移回工作区(Working Directory)
        # 这样用户用 git status 看到的就是红色的"修改过的文件"，完全恢复原状
        git reset
        
        success "Your local changes have been reapplied on top of the update."
    fi
fi

# ------------------------------------------------------------------------------
# STEP 3: 智能链接 (Smart Link)
# ------------------------------------------------------------------------------
log "Verifying configuration links..."
link_recursive "$DOTFILES_REPO/dotfiles" "$HOME"

echo ""
echo -e "${H_GREEN}========================================${NC}"
echo -e "${H_GREEN}   Update Completed Successfully!       ${NC}"
echo -e "${H_GREEN}========================================${NC}"
echo -e " - Backup: $BACKUP_FILE"
if [ "$HAS_LOCAL_CHANGES" = true ]; then
    echo -e " - Note: Your local changes are preserved in the working directory."
fi