#!/usr/bin/env bash
# Clipboard manager: cliphist history + rofi + wl-copy (Wayland clipboard)
selected=$(cliphist list | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '📋  Clipboard' -i -display-columns 2 -lines 12)
[[ -z "$selected" ]] && exit 0
printf '%s\n' "$selected" | cliphist decode | wl-copy
