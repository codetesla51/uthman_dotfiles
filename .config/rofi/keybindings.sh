#!/usr/bin/env bash
# Keybindings browser — standalone (no omarchy)
if command -v omarchy-menu-keybindings >/dev/null 2>&1; then
  omarchy-menu-keybindings --print | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '⌨️  Keybindings' -i -lines 20
else
  # The live Hyprland config is Lua; bindings.conf is a legacy copy. Parse the
  # Lua binds so newly added personal binds (desktop clock, etc.) show up here.
  python3 - <<'PY' | rofi -dmenu -theme ~/.config/rofi/list.rasi -p '⌨️  Keybindings' -i -lines 20
import pathlib, re

path = pathlib.Path.home() / ".config/hypr/bindings.lua"
if path.exists():
    for line in path.read_text().splitlines():
        m = re.match(r'\s*hl\.bind\("([^"]+)".*description = "([^"]+)"', line)
        if m:
            print(f"{m.group(2)}  —  {m.group(1)}")
PY
fi
