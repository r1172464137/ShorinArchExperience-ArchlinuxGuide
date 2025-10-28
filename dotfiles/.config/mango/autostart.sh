#! /bin/bash

waybar & 

#notification
mako & 

#polkit
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 & 

#wallpaper
swww-daemon &

fcitx5 & copyq & 


