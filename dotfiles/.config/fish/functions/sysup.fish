function sysup --description "Check Arch news and update system"
    # ==========================
    # 1. Check AUR Helper
    # ==========================
    set -l update_cmd ""
    if type -q yay; set update_cmd "yay"; else if type -q paru; set update_cmd "paru"; else
        echo -e "\n\033[1;31m!!! Error: No AUR helper found (yay/paru) !!!\033[0m"; return 1; end

    # ==========================
    # 2. Configuration (English Only)
    # ==========================
    set -l news_url "https://archlinux.org/feeds/news/"
    set -l msg_preparing "==> Preparing to update system with $update_cmd..."
    set -l msg_fetching "==> Fetching latest Arch Linux news..."
    set -l msg_confirm "Read above. Proceed with $update_cmd? [Y/n] "
    set -l msg_executing "==> Executing $update_cmd..."
    set -l msg_cancel "==> Update cancelled."
    set -l msg_err_fetch "!!! WARNING: Failed to fetch news (Network/Source error) !!!"
    set -l msg_force_ask "Force update ignoring news? [y/N] "
    set -l msg_forcing "==> Forcing update..."
    set -l msg_exit "==> Safe exit."
    set -l py_header ">>> Recent {} Arch Linux news items:"

    # ==========================
    # 3. Fetch & Display News
    # ==========================
    
    # Set display limit (Default 5)
    set -l count_limit 15
    if test -n "$argv[1]"; set count_limit $argv[1]
    else if set -q ARCH_NEWS_COUNT; set count_limit $ARCH_NEWS_COUNT; end

    echo -e "\n\033[1;36m$msg_preparing\033[0m"
    echo -e "\033[1;36m$msg_fetching\033[0m"

    # Call Python to parse RSS
    if curl -sS -L --connect-timeout 15 -A "Mozilla/5.0" "$news_url" | python -c "
import sys
import xml.etree.ElementTree as ET

try:
    limit = int(sys.argv[1])
    header_template = sys.argv[2]
    
    # Force UTF-8 handling
    sys.stdin.reconfigure(encoding='utf-8')
    raw_data = sys.stdin.read()
    
    if not raw_data.strip():
        sys.exit(1)

    root = ET.fromstring(raw_data)
    items = root.findall('./channel/item')[:limit]

    print(f'\n\033[1;33m{header_template.format(len(items))}\033[0m\n')

    for item in items:
        title = item.find('title').text
        pub_date = item.find('pubDate').text
        date_str = pub_date[:16] # Truncate date for cleaner look

        check_text = title.lower()
        # Highlight if title contains 'intervention' or 'manual'
        if any(x in check_text for x in ['intervention', 'manual']):
            color = '\033[1;31m' # Red
            prefix = '!!! '
        else:
            color = '\033[1;32m' # Green
            prefix = ''
        
        print(f'{color}[{date_str}] {prefix}{title}\033[0m')

except Exception as e:
    sys.stderr.write(f'\nParse Error: {e}\n')
    sys.exit(1)
" "$count_limit" "$py_header"

        # === A. Success Branch ===
        echo ""
        read -l -P "$msg_confirm" confirm
        switch $confirm
            case Y y ''
                # --- Keyring Check Logic Start ---
                echo -e "\n\033[1;34m==> Checking/Updating keyrings first...\033[0m"
                set -l keyring_targets archlinux-keyring
                # Check if archlinuxcn-keyring is installed
                if pacman -Qq archlinuxcn-keyring >/dev/null 2>&1
                    set -a keyring_targets archlinuxcn-keyring
                end
                
                # -Sy: Sync DB. --needed: Only reinstall if newer. --noconfirm: Automated.
                if sudo pacman -Sy --needed --noconfirm $keyring_targets
                    echo -e "\033[1;32m==> Keyrings verified.\033[0m"
                else
                    echo -e "\033[1;31m!!! Warning: Keyring update encountered issues. Proceeding...\033[0m"
                end
                # --- Keyring Check Logic End ---

                echo -e "\n\033[1;36m$msg_executing\033[0m"
                $update_cmd
            case '*'
                echo -e "\n\033[1;33m$msg_cancel\033[0m"
        end

    else
        # === B. Failure Branch ===
        echo -e "\n\033[1;31m$msg_err_fetch\033[0m"
        
        read -l -P "$msg_force_ask" force_confirm
        switch $force_confirm
            case Y y
                # --- Keyring Check Logic Start (Duplicate for force update) ---
                echo -e "\n\033[1;34m==> Checking/Updating keyrings first...\033[0m"
                set -l keyring_targets archlinux-keyring
                if pacman -Qq archlinuxcn-keyring >/dev/null 2>&1
                    set -a keyring_targets archlinuxcn-keyring
                end
                
                if sudo pacman -Sy --needed --noconfirm $keyring_targets
                    echo -e "\033[1;32m==> Keyrings verified.\033[0m"
                else
                    echo -e "\033[1;31m!!! Warning: Keyring update encountered issues. Proceeding...\033[0m"
                end
                # --- Keyring Check Logic End ---

                echo -e "\n\033[1;31m$msg_forcing\033[0m"
                $update_cmd
            case '*'
                echo -e "\n\033[1;33m$msg_exit\033[0m"
        end
    end
end
