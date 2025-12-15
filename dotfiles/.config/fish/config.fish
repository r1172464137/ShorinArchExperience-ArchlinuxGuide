if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""


starship init fish | source
zoxide init fish --cmd cd | source

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function ls
	command eza $argv
end

thefuck --alias | source

function f 

    command bash $HOME/.config/scripts/fastfetch-random-wife.sh

   end

function pac --description "Fuzzy search and install packages (Official Repo first)"
    # --- 配置区域 ---
    # 1. 定义颜色 (ANSI 标准色，兼容 Matugen)
    set color_official  "\033[34m"   
    set color_aur       "\033[35m"   
    set color_reset     "\033[0m"

    # 2. AUR 净化过滤器 (正则)
    # 修复点：这里必须用单引号 ''，否则正则表达式末尾的 $ 会被 fish 误判为变量
    set aur_filter      '^(mingw-|lib32-|cross-|.*-debug$)'

    # --- 逻辑区域 ---
    set preview_cmd 'yay -Si {2}'

    # 生成列表 -> 过滤 -> 上色 -> fzf
    set packages (begin
        # 1. 官方源：蓝色前缀
        pacman -Sl | awk -v c=$color_official -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, $1, r, $2, $3}'

        # 2. AUR 源：紫色前缀 + 过滤垃圾包
        yay -Sl aur | grep -vE "$aur_filter" | awk -v c=$color_aur -v r=$color_reset \
            '{printf "%s%-10s%s %-30s %s\n", c, $1, r, $2, $3}'
    end | \
    fzf --multi --ansi \
        --preview $preview_cmd --preview-window=right:60%:wrap \
        --height=95% --layout=reverse --border \
        --tiebreak=index \
        --nth=2 \
        --header 'Tab:多选 | Enter:安装 | Esc:退出' \
        --query "$argv" | \
    awk '{print $2}') # 直接提取纯净包名

    # --- 执行安装 ---
    if test -n "$packages"
        echo "正在准备安装: $packages"
        # 修复点：直接使用 $packages 列表，不要再用 awk 处理，否则多选会失效
        yay -S $packages
    end
end
function pacr --description "Fuzzy find and remove packages"
    # yay -Q: 列出已安装包
    set packages (yay -Q | fzf --multi --preview 'yay -Qi {1}' --layout=reverse --header 'Select packages to REMOVE' | awk '{print $1}')

    if test -n "$packages"
        # -Rns: 递归删除配置文件和不再需要的依赖
        yay -Rns $packages
    end
end
