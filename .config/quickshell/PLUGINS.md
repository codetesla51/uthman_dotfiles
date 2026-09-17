# PLUGINS.md — quickshell plugin registry

Single source of truth for every quickshell plugin: installed, wired, and wanted.
Rules of the house (from AGENTS.md / memory.md):
- EVERYTHING lives inside quickshell — one QML codebase, no side programs/daemons.
- New plugin = new `modules/*.qml` + `IpcHandler` target + (optional) Hyprland bind in
  `~/.config/hypr/bindings.conf`. Always use the canonical path `~/.config/quickshell`.
- Update this file when you add/remove/wire a plugin. `memory.md` is a session log, not a registry.

## Installed

| Module | What it does | IPC target | Keybind | Notes |
|---|---|---|---|---|
| AppLauncher.qml | app launcher | `launcher` | `SUPER SPACE` | |
| Workspaces.qml | live Hyprland workspaces | — | — | bar pill, left row |
| Clock.qml | bar clock, alt format on right-click | — | — | left-click opens ClockWindow |
| ClockWindow.qml | small draggable clock window | `clockwin` | via bar clock click | FastFetch-style FloatingWindow |
| CalendarPanel.qml | retired — pomodoro moved into ControlCenter | — | — | file kept on disk, unwired; reminders dormant in LocalStorage |
| NotificationCenter.qml + BellButton + Toasts | notifications daemon + drawer | `notifications` (+`toggleDnd`) | `SUPER ALT COMMA` | owns freedesktop Notifications bus |
| WifiPanel.qml + NetRate.qml | network manager + speedtest | `wifi` | `SUPER H` | cloudflare speedtest built in |
| SystemMonitor.qml | process/system stats + killer: HOGS strip (top CPU/MEM), zombie/D-state auto-flag, hover row + K TERM / Shift+K KILL (PID 0/1 guarded) | `sysmon` | `SUPER U` | FloatingWindow 920x640 |
| BatteryPanel.qml + Battery.qml | battery panel + pill | `battery` | `SUPER ALT B` | UPower real data |
| ClipboardPanel.qml | cliphist GUI, images | `clipboard` | `SUPER CTRL V` | copy/delete/wipe |
| ThemePanel.qml | wallpaper/theme picker | `theme` | `SUPER E` | drives matugen pipeline |
| KeybindsPanel.qml | static keybind cheatsheet | `keybinds` | `SUPER K` | Enter executes bind |
| PowerMenu.qml | lock/logout/suspend/reboot/shutdown | `power` | `SUPER ESCAPE` | TODO: confirm step for destructive actions |
| FastFetchWindow.qml | system info card w/ avatar | `fastfetch` | `SUPER N` | FloatingWindow 560x340 |
| AudioVisualizer.qml | retired — visualizer lives inside ControlCenter now | — | — | file kept on disk, unwired; cava feed via `vizProc` in ControlCenter |
| PkgManager.qml | **package manager** — search pacman+AUR, queue, install progress, uninstall (native vs foreign), updates | `pkgman` (`packages` alias) | `SUPER I` | FloatingWindow 980×640 — Hyprland window, not popup; pacman for repo, yay for AUR; .desktop for rofi/walker |
| PdfViewer.qml | **PDF library** — recents, favs, title+full-text search, copy-path/show-in-files | `pdfviewer` | `SUPER ALT N` | FloatingWindow 960×640 — Hyprland window, not overlay; reads in Zathura; `utpdf <file>` wrapper |
| ControlCenter.qml | **control center** — bento grid (now playing, weather+pomodoro, quick controls, network, pet, activity, cava visualizer) | `controlcenter` | `SUPER ALT P` | FloatingWindow 760×580 tight glass, Esc to close; pomodoro replaced SUPER ALT C calendar |
| MediaOsd.qml | volume/brightness/mic OSD overlay | `media` (`volup/voldown/volmute/micmute/briup/bridown/brimax/brimin`) | Fn-row keys (XF86) | replaced omarchy swayosd; binds in bindings.conf |
| Pomodoro.qml | **pomodoro timer** — focus/short/long cycle, adjustable durations, session dots, daily stats, phase notifications | `pomodoro` | `SUPER ALT C` | FloatingWindow 400×540 glass, Esc to close; space/R/N keys |
| GitHubDash.qml | **github dashboard** — tabs: Overview (heatmap, stats, top repos) · Inbox · Pulls · Actions (running jobs); bg polls every 5 min, notify-sends on new | `github` | Utilities hub (no bind) | FloatingWindow 760×560 glass; 1-4 tabs, R refresh, rows open in browser |
| PluginMenu.qml | pick-and-open bento cards for **extras/plugins only** (glyph + desc + arrow, keyboard nav, blur) | `plugins` | SUPER+Space → "util" (desktop entry, no Hypr bind) | native modules excluded; hub for Pomodoro, GitHubDash, notes, phone, drives |
| ScreenTime.qml | usage tracker: GitHub heatmap, top apps ranked, week bars, login count | `screentime` | `SUPER ALT T` | samples focused window every 10s → SQLite; gap >4h = new login |
| PhoneBridge.qml | ADB file sender: drop-to-phone, pull browser, queue, progress | `phonebridge` | `SUPER ALT K` | wireless ADB, one-time cable tcpip; no app on phone |
| Bar pills (ArchLogo, Memory, Cpu, Network, Temp, Tray, DndIndicator, ScriptIndicator) | status pills | — | — | ScriptIndicator runs scripts/update.sh + idle.sh |

## Unwired / dormant

| File | State | To activate |
|---|---|---|
| modules/LockScreen.qml | PAM API fixed (`onCompleted`), UI needs redo (no blur/animations, Esc bypasses auth) | wire into shell.qml + rebind `SUPER CTRL L`; user chose hyprlock for now |
| modules/WhatsApp.qml + Toast.qml | PARKED 2026-09-17 (WhatsApp-ToS ban caution): code + session kept, unwired from Bar.qml, SUPER ALT W off, no daemon runs; WhatsApp pings via PhoneBridge shade polling | rewire `WhatsApp {}` in Bar.qml + restore bind + `SUPER HOME` |

## Roadmap (wanted, not started)

From memory.md roadmap — do NOT start until de-omarchification done:
1. WhatsApp notification center
2. Habit tracker
3. Gmail inbox integration
4. Password store integration

## Done recently (2026-09 session)

- [x] cava visualizer fixed (raw ascii mode) → draggable window
- [x] MediaOsd replaces swayosd on all fn keys
- [x] Clock window from bar clock click
