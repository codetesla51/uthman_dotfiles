#!/usr/bin/env bash
# Keybindings browser — standalone (no omarchy)
if command -v omarchy-menu-keybindings >/dev/null 2>&1; then
  omarchy-menu-keybindings --print | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '⌨️  Keybindings' -i -lines 20
else
  # fallback: parse personal bindings.conf directly
  grep -E '^bindd?\s*=' ~/.config/hypr/bindings.conf | sed -E 's/bindd?\s*=\s*[^,]+,\s*[^,]+,\s*//' | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '⌨️  Keybindings' -i -lines 20
fi
