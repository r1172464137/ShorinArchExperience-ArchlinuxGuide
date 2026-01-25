function sysup --description "Arch Linux System Update Utility (Localized & Optimized)"
    # ==========================
    # 0. Define Colors & Styles
    # ==========================
    set -l nc '\033[0m'
    set -l h_red '\033[1;31m'
    set -l h_green '\033[1;32m'
    set -l h_yellow '\033[1;33m'
    set -l h_blue '\033[1;34m'
    set -l h_cyan '\033[1;36m'

    # ==========================
    # 1. Localization & Strings
    # ==========================
    # Default (English)
    set -l tag_info "[INFO]"
    set -l tag_success "[OK]"
    set -l tag_warn "[WARN]"
    set -l tag_error "[ERROR]"

    set -l msg_req_sudo "Requesting sudo privileges for system update..."
    set -l msg_sudo_fail "Sudo privileges required. Exiting."
    set -l msg_no_helper "No AUR helper found (yay/paru)"
    set -l msg_preparing "Preparing to update system with %s..."
    set -l msg_fetching "Fetching latest Arch Linux news..."
    set -l msg_news_header ">>> Recent {} Arch Linux news items:"
    set -l msg_confirm "Read above. Proceed with %s? [Y/n] "
    set -l msg_cancel "Update cancelled."
    set -l msg_err_fetch "Failed to fetch news (Network/Source error)"
    set -l msg_force_ask "Force update ignoring news? [y/N] "
    set -l msg_forcing "Forcing update..."
    set -l msg_exit "Safe exit."

    set -l msg_step_1 "[1/4] Syncing DB & Updating keyrings..."
    set -l msg_keyring_ok "Keyrings & DB synced."
    set -l msg_keyring_warn "Keyring update encountered issues. Proceeding..."
    set -l msg_step_2 "[2/4] Upgrading system..."
    set -l msg_step_3 "[3/4] Checking Flatpak updates..."
    set -l msg_step_4 "[4/4] Updating GRUB configuration..."
    set -l msg_grub_ok "GRUB updated successfully."
    set -l msg_grub_fail "GRUB update failed."

    # Chinese Override
    if env | grep -q "zh_CN"
        set tag_info "[信息]"
        set tag_success "[成功]"
        set tag_warn "[注意]"
        set tag_error "[错误]"

        set msg_req_sudo "正在请求管理员权限以更新系统..."
        set msg_sudo_fail "需要管理员权限才能更新系统和 GRUB。已退出。"
        set msg_no_helper "未找到 AUR 助手 (yay 或 paru)"
        set msg_preparing "准备使用 %s 更新系统..."
        set msg_fetching "正在获取 Arch Linux 最新新闻..."
        set msg_news_header ">>> 最近 {} 条 Arch Linux 新闻："
        set msg_confirm "请阅读上述新闻。确认使用 %s 继续更新吗？[Y/n] "
        set msg_cancel "更新已取消。"
        set msg_err_fetch "获取新闻失败（网络或源错误）"
        set msg_force_ask "是否忽略新闻强制更新？[y/N] "
        set msg_forcing "正在强制更新..."
        set msg_exit "安全退出。"

        set msg_step_1 "[1/4] 同步数据库并更新密钥环..."
        set msg_keyring_ok "密钥环与数据库已同步。"
        set msg_keyring_warn "密钥环更新遇到问题，继续尝试系统更新..."
        set msg_step_2 "[2/4] 正在升级系统..."
        set msg_step_3 "[3/4] 检查 Flatpak 更新..."
        set msg_step_4 "[4/4] 更新 GRUB 配置..."
        set msg_grub_ok "GRUB 更新成功。"
        set msg_grub_fail "GRUB 更新失败。"
    end

    # ==========================
    # 2. Helper Functions
    # ==========================
    function _log --inherit-variable nc --inherit-variable h_blue --inherit-variable tag_info
        echo -e "$h_blue$tag_info$nc $argv"
    end

    function _success --inherit-variable nc --inherit-variable h_green --inherit-variable tag_success
        echo -e "$h_green$tag_success$nc $argv"
    end

    function _warn --inherit-variable nc --inherit-variable h_yellow --inherit-variable tag_warn
        echo -e "$h_yellow$tag_warn$nc $argv"
    end

    function _error --inherit-variable nc --inherit-variable h_red --inherit-variable tag_error
        echo -e "$h_red$tag_error$nc $argv"
        return 1
    end

    # ==========================
    # 3. Request Privileges
    # ==========================
    _log "$msg_req_sudo"
    if not sudo -v
        _error "$msg_sudo_fail"
        return 1
    end

    # Keep sudo alive in background (Fish approach)
    fish -c "while true; sudo -n true; sleep 60; kill -0 $fish_pid 2>/dev/null || exit; end" & disown

    # ==========================
    # 4. Check Environment
    # ==========================
    set -l update_cmd ""
    if type -q yay
        set update_cmd "yay"
    else if type -q paru
        set update_cmd "paru"
    else
        _error "$msg_no_helper"
        return 1
    end

    set -l count_limit 15
    if test -n "$argv[1]"; set count_limit $argv[1]; end

    # ==========================
    # 5. Core Update Logic
    # ==========================
    function _perform_update --inherit-variable update_cmd --inherit-variable msg_step_1 --inherit-variable msg_keyring_ok --inherit-variable msg_keyring_warn --inherit-variable msg_step_2 --inherit-variable msg_step_3 --inherit-variable msg_step_4 --inherit-variable msg_grub_ok --inherit-variable msg_grub_fail --inherit-variable _log --inherit-variable _success --inherit-variable _warn --inherit-variable _error

        # --- Step 1: Sync DB & Keyring ---
        _log "$msg_step_1"
        set -l keyring_targets archlinux-keyring
        if pacman -Qq archlinuxcn-keyring >/dev/null 2>&1
            set -a keyring_targets archlinuxcn-keyring
        end

        if sudo pacman -Sy --needed --noconfirm $keyring_targets
            _success "$msg_keyring_ok"
        else
            _warn "$msg_keyring_warn"
        end

        # --- Step 2: System Update (Optimized -Su) ---
        _log "$msg_step_2"
        $update_cmd -Su

        # --- Step 3: Flatpak ---
        if type -q flatpak
            _log "$msg_step_3"
            flatpak update
        end

        # --- Step 4: Update GRUB ---
        _log "$msg_step_4"
        if sudo env LANG=en_US.UTF-8 grub-mkconfig -o /boot/grub/grub.cfg
            _success "$msg_grub_ok"
        else
            _error "$msg_grub_fail"
        end
    end

    # ==========================
    # 6. Main Execution
    # ==========================
    
    _log (printf "$msg_preparing" $update_cmd)
    _log "$msg_fetching"

    # Call Python Parser
    if curl -sS -L --connect-timeout 15 -A "Mozilla/5.0" "https://archlinux.org/feeds/news/" | python -c "
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
            color = '\033[1;31m'; prefix = '!!! '
        else:
            color = '\033[1;32m'; prefix = ''
        print(f'{color}[{date_str}] {prefix}{title}\033[0m')
except:
    sys.exit(1)
" "$count_limit" "$msg_news_header"

        # === Success Branch ===
        echo ""
        read -l -P (printf "$msg_confirm" $update_cmd) confirm
        switch $confirm
            case Y y ''
                _perform_update
            case '*'
                _warn "$msg_cancel"
                return 0
        end

    else
        # === Failure Branch ===
        echo ""
        _warn "$msg_err_fetch"
        read -l -P "$msg_force_ask" force_confirm
        switch $force_confirm
            case Y y
                _warn "$msg_forcing"
                _perform_update
            case '*'
                _log "$msg_exit"
                return 1
        end
    end
end
