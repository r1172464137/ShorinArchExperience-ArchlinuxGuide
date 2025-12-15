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
    # 1. 定义预览命令
    set preview_cmd 'yay -Si {2}'

    # 2. 生成列表并搜索
    # 关键修改：加入了 --tiebreak=index
    set packages (begin; pacman -Sl; yay -Sl aur; end | \
        fzf --multi --preview $preview_cmd --preview-window=right:60%:wrap \
            --height=90% --layout=reverse --border \
            --tiebreak=index \
            --header 'Tab:多选 | Enter:安装 | Esc:退出' \
            --query "$argv" | \
        awk '{print $2}')

    # 3. 执行安装
    if test -n "$packages"
        echo "正在准备安装: $packages"
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
