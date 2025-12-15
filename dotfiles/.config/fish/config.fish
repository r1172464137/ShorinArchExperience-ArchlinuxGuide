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

function pac --description "Fuzzy search and install packages with yay"
    # 1. 定义预览命令：当光标移动时，用 yay -Si 显示详细信息
    # {2} 代表 fzf 传入行的第 2 列（包名）
    set preview_cmd 'yay -Si {2}'

    # 2. 生成包列表并传递给 fzf
    # pacman -Sl 列出官方库，yay -Sl aur 列出 AUR
    # fzf 参数解释：
    # -m: 开启多选 (Tab键)
    # --preview: 显示预览窗
    # --nth=2: 搜索时主要匹配第2列（包名）
    set packages (begin; pacman -Sl; yay -Sl aur; end | \
        fzf --multi --preview $preview_cmd --preview-window=right:60%:wrap \
            --height=90% --layout=reverse --border \
            --header 'Tab:多选 | Enter:安装 | Esc:退出' \
            --query "$argv" | \
        awk '{print $2}') # 使用 awk 提取包名

    # 3. 如果用户选中了包（变量不为空），则执行安装
    if test -n "$packages"
        echo "正在准备安装: $packages"
        yay -S $packages
    end
end
