#!/usr/bin/env bash
# Keybindings browser: reuse omarchy's keybindings formatter, show via rofi
omarchy-menu-keybindings --print | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '⌨️  Keybindings' -i -lines 20
