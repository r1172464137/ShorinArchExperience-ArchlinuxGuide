#!/bin/bash
mkdir -p ~/Pictures/Screenshots
grim -g "$(slurp)" - | tee $HOME/Pictures/Screenshots/$(date +'%Y-%m-%d-%H%M%S.png') >(wl-copy)

