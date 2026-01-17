function sysup --description "自动检测 locale，显示 Arch 新闻并更新系统"
    # ==========================
    # 1. 检查 AUR 助手 (Check Helpers)
    # ==========================
    set -l update_cmd ""
    if type -q yay; set update_cmd "yay"; else if type -q paru; set update_cmd "paru"; else
        echo -e "\n\033[1;31m!!! Error: No AUR helper found (yay/paru) !!!\033[0m"; return 1; end

    # ==========================
    # 2. 语言环境检测 (Language Detection)
    # ==========================
    set -l is_zh 0
    
    # 修改点：不再只看 $LANG，而是运行 'locale' 命令获取所有环境设置
    # 使用 string match (fish 的内置 grep) 扫描输出
    if locale | string match -q "*zh_CN*"
        set is_zh 1
    end

    # ==========================
    # 3. 定义本地化文本 (Localization Strings)
    # ==========================
    if test $is_zh -eq 1
        # --- 中文配置 (Chinese Config) ---
        set news_url "https://www.archlinuxcn.org/category/news/feed/"
        set msg_preparing "==> 准备使用 $update_cmd 更新系统..."
        set msg_fetching "==> 正在获取 Arch Linux 中文社区最新新闻..."
        set msg_confirm "请确认无重大问题。是否继续执行 $update_cmd? [Y/n] "
        set msg_executing "==> 执行 $update_cmd 更新..."
        set msg_cancel "==> 更新已取消。"
        set msg_err_fetch "!!! 警告: 无法获取新闻 (可能是网络或源的问题) !!!"
        set msg_force_ask "是否**强制**忽略新闻并继续更新? [y/N] "
        set msg_forcing "==> 正在强制更新..."
        set msg_exit "==> 安全退出。"
        set py_header ">>> 最近 {} 条 Arch 中文新闻:" 
    else
        # --- 英文配置 (English Config) ---
        set news_url "https://archlinux.org/feeds/news/"
        set msg_preparing "==> Preparing to update system with $update_cmd..."
        set msg_fetching "==> Fetching latest Arch Linux news..."
        set msg_confirm "Read above. Proceed with $update_cmd? [Y/n] "
        set msg_executing "==> Executing $update_cmd..."
        set msg_cancel "==> Update cancelled."
        set msg_err_fetch "!!! WARNING: Failed to fetch news (Network/Source error) !!!"
        set msg_force_ask "Force update ignoring news? [y/N] "
        set msg_forcing "==> Forcing update..."
        set msg_exit "==> Safe exit."
        set py_header ">>> Recent {} Arch Linux news items:"
    end

    # ==========================
    # 4. 获取并显示新闻 (Fetch & Display)
    # ==========================
    
    # 设定显示数量 (默认 5)
    set -l count_limit 15
    if test -n "$argv[1]"; set count_limit $argv[1]
    else if set -q ARCH_NEWS_COUNT; set count_limit $ARCH_NEWS_COUNT; end

    echo -e "\n\033[1;36m$msg_preparing\033[0m"
    echo -e "\033[1;36m$msg_fetching\033[0m"

    # 调用 Python 解析
    if curl -sS -L --connect-timeout 15 -A "Mozilla/5.0" "$news_url" | python -c "
import sys
import xml.etree.ElementTree as ET

try:
    limit = int(sys.argv[1])
    header_template = sys.argv[2]
    
    # 强制 UTF-8 
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
        date_str = pub_date[:16]

        check_text = title.lower()
        if any(x in check_text for x in ['intervention', '手动干预', '干预']):
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

        # === A. 成功分支 ===
        echo ""
        read -l -P "$msg_confirm" confirm
        switch $confirm
            case Y y ''
                echo -e "\n\033[1;36m$msg_executing\033[0m"
                $update_cmd
            case '*'
                echo -e "\n\033[1;33m$msg_cancel\033[0m"
        end

    else
        # === B. 失败分支 ===
        echo -e "\n\033[1;31m$msg_err_fetch\033[0m"
        
        read -l -P "$msg_force_ask" force_confirm
        switch $force_confirm
            case Y y
                echo -e "\n\033[1;31m$msg_forcing\033[0m"
                $update_cmd
            case '*'
                echo -e "\n\033[1;33m$msg_exit\033[0m"
        end
    end
end
