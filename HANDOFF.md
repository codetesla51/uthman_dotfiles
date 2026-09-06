# HANDOFF — standalone Arch + Hyprland conversion (final state, 2026-09-06)

## Setup: COMPLETE
All 8 phases done. 198 binds live, no config errors, bar renders,
launcher/volume/brightness/screenshot/lock/nightlight/gaps/layout/touchpad tested,
panel active on :8765, swaybg wallpaper at boot, zsh+starship default prompt.

## Key facts for future sessions
- Hyprland 0.56.2 prefers `hyprland.lua` over `hyprland.conf`. No lua file may
  ever exist in `~/.config/hypr/` or the rice goes dark. `hyprctl reload` is safe.
- Env for hyprctl: `export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ | head -1)`
  plus `WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000` for grim.
- `hyprctl keyword` WORKS in conf mode (monitor, gaps, layout, device).
- Screenshots: `grim /tmp/x.png` then read the image. Overlay errors do NOT
  reliably appear in hyprland.log — screenshot is ground truth.
- Quickshell owns `org.freedesktop.Notifications`. dunst/mako/swaync masked.
  Media/volume keys go through quickshell `media` IPC (pamixer backend).
- Panel: `cd ~/dotfiles/panel && go build -o panel .`, service
  `dotfiles-panel.service`, `curl localhost:8765/api/stats`.
- Helper scripts (repo: `.local/bin/`): shot, lock, nightlight, idle-toggle,
  touchpad, bright, vol (cycle-sink via pactl), winfx (transparent/gaps),
  record (needs recorder app), mon-toggle, layout-toggle. All use
  python3/awk — no jq dependency.
- Prompt: ghostty forces `command = /usr/bin/zsh`; `.zshrc` guards missing
  plugin sources; SUPER+RETURN opens ghostty directly (no xdg-terminal-exec).

## Left for the user (needs sudo password — agent cannot do this)
sudo pacman -S --needed libnotify jq tmux kvantum gnome-calculator hyprpicker gpu-screen-recorder tesseract zsh-syntax-highlighting zsh-autosuggestions
- libnotify → time/battery/weather popups; jq → zoom binds; tmux → tmux.conf;
  kvantum → QT_STYLE_OVERRIDE already set; hyprpicker → SUPER+PRINT;
  gpu-screen-recorder → SUPER+R; tesseract → shot ocr; zsh-* → prompt plugins.
- `chsh -s /usr/bin/zsh` for zsh on TTYs (ghostty already forced).
- Change sudo password (was pasted in chat on 2026-09-06).
- Niche dead binds (harmless, fail silent): reminders, transcode, voxtype,
  window-pop/close-all/square-aspect, monitor-mirror/scaling-cycle, lid-switch
  helpers, bt/audio launcher panels, weather/battery scripts.

## Dieser Commit
Standalone conversion: install.sh fixes, getTheme cap, lua-vs-conf boot fix,
windows.conf Omarchy source removal, monitors 1.2, swaybg autostart,
quickshell IPC rewire, 11 helper scripts, prompt fixes, panel rename+build.
