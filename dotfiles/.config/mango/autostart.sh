#! /bin/bash

waybar & 

#notification
mako & 

#polkit
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 & 

#wallpaper
swww-daemon &

fcitx5 & copyq & 

dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
# The next line of command is not necessary. It is only to avoid some situations where it cannot start automatically
/usr/lib/xdg-desktop-portal-wlr &

