if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""
set -p PATH ~/.local/bin
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
# fa运行fastfetch
abbr fa fastfetch
# f运行带二次元美少女的fastfetch
function f 
    command bash $HOME/.config/scripts/fastfetch-random-wife.sh
   end
function fnsfw
    command env NSFW=1 bash $HOME/.config/scripts/fastfetch-random-wife.sh
   end
abbr reboot 'systemctl reboot'
function 滚
	sysup 
end
function 更新
	sysup 
end
function 清理
    command yay -Scc
    if test -d /var/cache/pacman/pkg/
        set -l targets /var/cache/pacman/pkg/download-*/
        if count $targets > /dev/null
            echo "正在清理残留的下载目录..."
            sudo rm -rf $targets
        end
    end
    echo "清理完成！"
end
function 安装
	command yay -S $argv
end
function 卸载
	command yay -Rns $argv
end
function clean
    command yay -Scc
    if test -d /var/cache/pacman/pkg/
        set -l targets /var/cache/pacman/pkg/download-*/
        if count $targets > /dev/null
            echo "正在清理残留的下载目录..."
            sudo rm -rf $targets
        end
    end
    echo "清理完成！"
end
function install
	command yay -S $argv
end
function remove 
	command yay -Rns $argv
end
