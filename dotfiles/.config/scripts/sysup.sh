#!/bin/bash

# ==============================================================================
# sysup - Arch Linux System Update Utility
# ==============================================================================

# 1. Define Colors
NC='\033[0m'
H_RED='\033[1;31m'
H_GREEN='\033[1;32m'
H_YELLOW='\033[1;33m'
H_BLUE='\033[1;34m'

# 2. Localization Logic
if env | grep -q "zh_CN"; then
    # Chinese String Definitions
    TAG_INFO="[信息]"
    TAG_SUCCESS="[成功]"
    TAG_WARN="[注意]"
    TAG_ERROR="[错误]"
    
    MSG_REQ_SUDO="正在请求管理员权限以更新系统..."
    MSG_SUDO_FAIL="需要管理员权限才能更新系统和 GRUB。已退出。"
    MSG_NO_HELPER="未找到 AUR 助手 (yay 或 paru)"
    MSG_PREPARING="准备使用 %s 更新系统..."
    MSG_FETCHING="正在获取 Arch Linux 最新新闻..."
    MSG_NEWS_HEADER=">>> 最近 {} 条 Arch Linux 新闻："
    MSG_CONFIRM="请阅读上述新闻。确认使用 %s 继续更新吗？[Y/n] "
    MSG_CANCEL="更新已取消。"
    MSG_ERR_FETCH="获取新闻失败（网络或源错误）"
    MSG_FORCE_ASK="是否忽略新闻强制更新？[y/N] "
    MSG_FORCING="正在强制更新..."
    MSG_EXIT="安全退出。"
    
    MSG_STEP_1="[1/4] 同步数据库并更新密钥环..."
    MSG_KEYRING_OK="密钥环与数据库已同步。"
    MSG_KEYRING_WARN="密钥环更新遇到问题，继续尝试系统更新..."
    MSG_STEP_2="[2/4] 正在升级系统..."
    MSG_STEP_3="[3/4] 检查 Flatpak 更新..."
    MSG_STEP_4="[4/4] 更新 GRUB 配置..."
    MSG_GRUB_OK="GRUB 更新成功。"
    MSG_GRUB_FAIL="GRUB 更新失败。"
else
    # English String Definitions
    TAG_INFO="[INFO]"
    TAG_SUCCESS="[OK]"
    TAG_WARN="[WARN]"
    TAG_ERROR="[ERROR]"
    
    MSG_REQ_SUDO="Requesting sudo privileges for system update..."
    MSG_SUDO_FAIL="Sudo privileges required. Exiting."
    MSG_NO_HELPER="No AUR helper found (yay/paru)"
    MSG_PREPARING="Preparing to update system with %s..."
    MSG_FETCHING="Fetching latest Arch Linux news..."
    MSG_NEWS_HEADER=">>> Recent {} Arch Linux news items:"
    MSG_CONFIRM="Read above. Proceed with %s? [Y/n] "
    MSG_CANCEL="Update cancelled."
    MSG_ERR_FETCH="Failed to fetch news (Network/Source error)"
    MSG_FORCE_ASK="Force update ignoring news? [y/N] "
    MSG_FORCING="Forcing update..."
    MSG_EXIT="Safe exit."
    
    MSG_STEP_1="[1/4] Syncing DB & Updating keyrings..."
    MSG_KEYRING_OK="Keyrings & DB synced."
    MSG_KEYRING_WARN="Keyring update encountered issues. Proceeding..."
    MSG_STEP_2="[2/4] Upgrading system..."
    MSG_STEP_3="[3/4] Checking Flatpak updates..."
    MSG_STEP_4="[4/4] Updating GRUB configuration..."
    MSG_GRUB_OK="GRUB updated successfully."
    MSG_GRUB_FAIL="GRUB update failed."
fi

# 3. Define Logging Functions
log() { echo -e "${H_BLUE}${TAG_INFO}${NC} $1"; }
success() { echo -e "${H_GREEN}${TAG_SUCCESS}${NC} $1"; }
warn() { echo -e "${H_YELLOW}${TAG_WARN}${NC} $1"; }
error() { echo -e "${H_RED}${TAG_ERROR}${NC} $1"; exit 1; }

# 4. Request Privileges
log "$MSG_REQ_SUDO"
if ! sudo -v; then
    error "$MSG_SUDO_FAIL"
fi
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# 5. Check AUR Helper
UPDATE_CMD=""
if command -v yay >/dev/null 2>&1; then
    UPDATE_CMD="yay"
elif command -v paru >/dev/null 2>&1; then
    UPDATE_CMD="paru"
else
    error "$MSG_NO_HELPER"
fi

# 6. Setup Configuration
NEWS_URL="https://archlinux.org/feeds/news/"
COUNT_LIMIT=15
[ -n "$1" ] && COUNT_LIMIT="$1"

# 7. Update Function
perform_update() {
    # Step 1
    log "$MSG_STEP_1"
    KEYRING_TARGETS="archlinux-keyring"
    pacman -Qq archlinuxcn-keyring >/dev/null 2>&1 && KEYRING_TARGETS="$KEYRING_TARGETS archlinuxcn-keyring"
    
    if sudo pacman -Sy --needed --noconfirm $KEYRING_TARGETS; then
        success "$MSG_KEYRING_OK"
    else
        warn "$MSG_KEYRING_WARN"
    fi
    
    # Step 2
    log "$MSG_STEP_2"
    $UPDATE_CMD -Su

    # Step 3
    if command -v flatpak >/dev/null 2>&1; then
        log "$MSG_STEP_3"
        flatpak update
    fi

    # Step 4
    log "$MSG_STEP_4"
    if sudo env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg; then
        success "$MSG_GRUB_OK"
    else
        error "$MSG_GRUB_FAIL"
    fi
}

# 8. Main Execution
formatted_preparing=$(printf "$MSG_PREPARING" "$UPDATE_CMD")
log "$formatted_preparing"
log "$MSG_FETCHING"

# Python script
PYTHON_SCRIPT=$(cat <<'EOF'
import sys
import xml.etree.ElementTree as ET

try:
    limit = int(sys.argv[1])
    header_template = sys.argv[2]
    sys.stdin.reconfigure(encoding='utf-8')
    raw_data = sys.stdin.read()
    if not raw_data.strip(): sys.exit(1)

    root = ET.fromstring(raw_data)
    items = root.findall('./channel/item')[:limit]
    
    print(f'\n\033[1;33m{header_template.format(len(items))}\033[0m\n')

    for item in items:
        title = item.find('title').text
        pub_date = item.find('pubDate').text
        date_str = pub_date[:16]
        check_text = title.lower()
        if any(x in check_text for x in ['intervention', 'manual']):
            color = '\033[1;31m'
            prefix = '!!! '
        else:
            color = '\033[1;32m'
            prefix = ''
        print(f'{color}[{date_str}] {prefix}{title}\033[0m')
except:
    sys.exit(1)
EOF
)

# Run Curl and Python
if curl -sS -L --connect-timeout 15 -A "Mozilla/5.0" "$NEWS_URL" | python -c "$PYTHON_SCRIPT" "$COUNT_LIMIT" "$MSG_NEWS_HEADER"; then
    # Success: Ask to proceed
    printf "\n"
    printf "$MSG_CONFIRM" "$UPDATE_CMD"
    read -r confirm
    case "$confirm" in
        [Yy]*|"" ) perform_update ;;
        * ) warn "$MSG_CANCEL"; exit 0 ;;
    esac
else
    # Failure: Ask to force
    printf "\n"
    warn "$MSG_ERR_FETCH"
    printf "$MSG_FORCE_ASK"
    read -r force_confirm
    case "$force_confirm" in
        [Yy]* ) 
            warn "$MSG_FORCING"
            perform_update 
            ;;
        * ) 
            log "$MSG_EXIT"
            exit 1 
            ;;
    esac
fi
