function shorin-update
    set -l script_path "$HOME/.config/scripts/shorin-update.sh"
    if test -f "$script_path"
        # 赋予执行权限
        chmod +x "$script_path"
        # 执行脚本
        "$script_path"
    else
        echo -e "\e[31m错误：找不到更新脚本！\e[0m"
        echo "路径: $script_path"
    end
end
