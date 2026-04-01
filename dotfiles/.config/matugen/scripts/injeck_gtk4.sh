#!/bin/bash
for d in ~/.config/gtk-4.0; do
    mkdir -p "$d"
    f="$d/gtk.css"
    if ! grep -qFx '@import url("colors.css");' "$f" 2>/dev/null; then
        echo '@import url("colors.css");' >> "$f"
    fi
done
