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
| CalendarPanel.qml | month grid + reminders + pomodoro | `calendar` | `SUPER C` | drawer panel (720px) |
| NotificationCenter.qml + BellButton + Toasts | notifications daemon + drawer | `notifications` (+`toggleDnd`) | `SUPER ALT COMMA` | owns freedesktop Notifications bus |
| WifiPanel.qml + NetRate.qml | network manager + speedtest | `wifi` | `SUPER H` | cloudflare speedtest built in |
| SystemMonitor.qml | process/system stats window | `sysmon` | `SUPER U` | FloatingWindow 920x640 |
| BatteryPanel.qml + Battery.qml | battery panel + pill | `battery` | `SUPER ALT B` | UPower real data |
| ClipboardPanel.qml | cliphist GUI, images | `clipboard` | `SUPER CTRL V` | copy/delete/wipe |
| ThemePanel.qml | wallpaper/theme picker | `theme` | `SUPER E` | drives matugen pipeline |
| KeybindsPanel.qml | static keybind cheatsheet | `keybinds` | `SUPER K` | Enter executes bind |
| PowerMenu.qml | lock/logout/suspend/reboot/shutdown | `power` | `SUPER ESCAPE` | TODO: confirm step for destructive actions |
| FastFetchWindow.qml | system info card w/ avatar | `fastfetch` | `SUPER N` | FloatingWindow 560x340 |
| AudioVisualizer.qml | cava bars in draggable window | `visualizer` | `SUPER ALT V` | cava raw/ascii feed, scripts/cava-qs.conf |
| MediaOsd.qml | volume/brightness/mic OSD overlay | `media` (`volup/voldown/volmute/micmute/briup/bridown/brimax/brimin`) | Fn-row keys (XF86) | replaced omarchy swayosd; binds in bindings.conf |
| PluginMenu.qml | pick-and-open grid for **extras/plugins only** | `plugins` | `SUPER ALT P` | native modules excluded |
| ScreenTime.qml | usage tracker: GitHub heatmap, top apps ranked, week bars, login count | `screentime` | `SUPER ALT T` | samples focused window every 10s → SQLite; gap >4h = new login |
| PhoneLink.qml | KDE Connect wrapper: send files, clipboard sync, device status | `phonelink` | `SUPER ALT K` | needs kdeconnect-cli + paired phone |
| Bar pills (ArchLogo, Memory, Cpu, Network, Temp, Tray, DndIndicator, ScriptIndicator) | status pills | — | — | ScriptIndicator runs scripts/update.sh + idle.sh |

## Unwired / dormant

| File | State | To activate |
|---|---|---|
| modules/LockScreen.qml | PAM API fixed (`onCompleted`), UI needs redo (no blur/animations, Esc bypasses auth) | wire into shell.qml + rebind `SUPER CTRL L`; user chose hyprlock for now |

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
