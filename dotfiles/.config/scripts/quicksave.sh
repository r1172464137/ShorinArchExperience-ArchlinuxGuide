#!/bin/bash

if snapper -c root cleanup number && snapper -c home cleanup number; then
    notify-send "Old save files cleaned."
else
    notify-send "ERROR: Clean process failed."
fi

if snapper -c root create --description "quicksave" --cleanup-algorithm number && \
   snapper -c home create --description "quicksave" --cleanup-algorithm number; then
    notify-send "Quicksaved."
else
    notify-send "ERROR: Quicksave failed."
fi
