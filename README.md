# dotfiles

> Arch Linux · Hyprland · Quickshell · Matugen. One rice where the wallpaper sets the palette and everything else follows.

![screenshot](./assets/screenshots/screenshot-1.png)
![screenshot](./assets/screenshots/screenshot-2.png)
![screenshot](./assets/screenshots/screenshot-3.png)

## What this is

A complete, daily-driven Arch Linux desktop configuration: Hyprland compositor, a Quickshell desktop shell written from scratch (bar, panels, launchers, utilities), Material You theming driven by the wallpaper, and a local Go control panel that edits all of it. Everything lives in one stow-managed repo, so the entire setup reproduces from a fresh install with two commands.

## Why it exists

Stock Wayland components (Waybar, SwayNC, rofi menus, static SDDM themes) each solve one slice and never agree on theme, behavior, or keybinds. This repo replaces that patchwork with a single QML codebase and a single palette pipeline, so a new feature means one new module file instead of a new daemon, a new config format, and a new theming hack. It is opinionated on purpose: one compositor, one shell language, one theme source.

## Why not use the alternatives

Omarchy (which this setup borrows vendor defaults from) is excellent if you want a maintained, batteries-included Hyprland distro layer. These dotfiles are the opposite trade: full ownership of every pixel and keybind, at the cost of maintaining it yourself. If you want Waybar, take Waybar — it has a larger community and more widgets. The Quickshell shell here exists because Waybar cannot do centered islands with album-art-driven UI, hover transport controls, or panels that share one live palette object. If you want a prebuilt rice, this is not that. It is a working system with sharp edges, documented below.

## Features

* Glassmorphic top bar with a centered Dynamic Island (clock, NowPlaying with hover transport, notifications bell) flanked by system pills
* 40+ Quickshell modules: wifi manager with speedtest, system monitor, package manager, PDF library, wallpaper storefront, ADB phone bridge, notification daemon, power menu, clipboard manager, control center, and more
* Wallpaper-driven theming: one `matugen image` call recolors the bar, apps, login screen, editor, and terminal with no restarts
* Go control panel (`localhost:8765`) editing theme, keybinds, monitors, audio, power, and processes from a browser
* WatchCat hotspot watchdog (per-process metering against a daily cap, notify-only)
* Snapper timeline snapshots with a documented bare-metal rollback path
* Every panel closable with `Esc`, every list navigable with `hjkl`

## Quick start

Prerequisites: Arch Linux, `yay`, and an NVIDIA/AMD/Intel GPU with working Wayland drivers.

```bash
# 1. dependencies. The installer warns about anything missing but does not abort,
# so you can install in rounds and re-run it.
yay -S hyprland quickshell ghostty matugen starship zsh lsd zoxide fzf \
       cava btop walker rofi swaync mako swayosd hyprlock hypridle hyprsunset sddm \
       xdg-desktop-portal-hyprland uwsm cliphist wl-clipboard \
       ttf-jetbrainsmono-nerd ttf-firacode-nerd inter-font
# The Iceland login-screen font is vendored in assets/fonts/. The installer handles it.
```

```bash
# 2. clone and install. install.sh symlinks every config into place with stow,
# so ~/dotfiles stays the single source of truth and every edit is git-tracked.
git clone https://github.com/codetesla51/uthman_dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

```bash
# 3. set a wallpaper. This one command swaps the image AND regenerates the
# entire palette live across bar, apps, and login screen.
set-wallpaper ~/Pictures/your-wallpaper.jpg   # ~/.local/bin/set-wallpaper
getTheme                                      # ~/.local/bin/getTheme, prints current palette
```

Log out, pick Hyprland at the SDDM greeter, log in. `SUPER+K` opens the searchable keybind cheatsheet if you get lost.

> [!WARNING]
> Reboot once after the first install. The SDDM theme installs to `/usr/share/sddm/themes/` (needs root) and several user services only start on a fresh login.

## Stack

| Layer | Choice |
|-------|--------|
| Compositor | Hyprland (Wayland). Defaults vendored in `.config/hypr/vendor/`, personal overrides in `.config/hypr/*.conf` |
| Shell / bar | Quickshell. `shell.qml` wires `components/Bar.qml` (left/center/right rows) plus standalone windows |
| Theming | Matugen (Material You). ~40 templates write to `~/.config/theme/current/*`, `~/.config/quickshell/colors.css`, and the SDDM palette |
| Terminal | Ghostty + Kitty (both `config`/`kitty.conf` source the generated `ghostty.conf`/`kitty.conf`) |
| Shell | Zsh + Starship + `lsd` / `zoxide` / `fzf` / `mise` |
| Launcher | Quickshell AppLauncher (Spotlight-style). Walker + Rofi kept for emoji, clipboard, and dmenu shims |
| Notifications | Quickshell daemon (owns `org.freedesktop.Notifications`): toasts, drawer, history. `swaync`/`mako` remain as fallback only |
| Audio OSD | Quickshell MediaOsd (replaces swayosd), bound to the Fn row |
| Monitors | btop plus `SystemMonitor.qml` (per-core CPU, RAM, network, process kill) |
| Login | SDDM `elarun-custom`: dark password-only greeter, Hollow Knight mask, Iceland font, matugen palette. Source in `sddm/`, installed to `/usr/share/sddm/themes/` |
| Fetch | Fastfetch (Hollow Knight art vendored in `assets/fastfetch/`) |
| Editor | Neovim (lazy) + Zed, both matugen-themed |
| Multiplexer | tmux (`C-Space` prefix, vim keys) |
| Boot | Limine on the ESP. Root is btrfs (`@`, `@home`, `@log`, `@pkg`) with snapper timelines |
| Phone | PhoneBridge module over a standalone `~/phonebridge` ADB backend (separate repo, not vendored here) |

## How theming works

Matugen reads the wallpaper, builds a Material You palette, and fills `{{ colors.* }}` variables in each template. One command recolors everything with no restarts:

```bash
matugen image ~/Pictures/your-wallpaper.jpg
```

`~/.config/matugen/config.toml` (`contrast = 0.2`, `variation = "standard"`) maps each template to its outputs. The main ones:

| Template | Output |
|----------|--------|
| `waybar` | `~/.config/quickshell/colors.css` (the file the live shell polls) |
| `hyprland-*` | `snow_black/colors.conf` + `theme/current` (+ `omarchy/current` legacy mirror) |
| `hyprlock-*`, `ghostty-*`, `kitty-*`, `gtk`, `btop`, `walker`, `mako` | matching `snow_black` snapshot + `theme/current` live file |
| `cava` | `snow_black/cava_theme` + `~/.config/cava/config` (rewritten directly) |
| `sddm` | `/usr/share/sddm/themes/elarun-custom/Palette.qml` (login follows every theme change) |
| `firefox` (+ chrome wiring) | `theme/current/firefox{,-usercontent}.css`, symlinked as `userChrome.css`/`userContent.css`; `firefox/user.js` enables it |
| `rofi`, `neovim`, `swayosd`, `zed`, `obsidian`, `swaync`, `zathura`, `pear-desktop`, `cavasik` | per-app live outputs |

Active colors live in `~/.config/theme/current/` and are rewritten on every run. `snow_black/` keeps saved snapshots, `theme-fallback/` ships the static seed. (`~/.config/omarchy/current/theme/` is still written as a legacy mirror. ThemePanel and `set-wallpaper` check it as a fallback. Nothing else reads it.)

> [!TIP]
> `Colors.qml` polls `~/.config/quickshell/colors.css` every second. Matugen *replaces* the file (new inode) instead of editing it, so the poller re-reads rather than watching. Palette swaps propagate with no restart.

> [!WARNING]
> Always run full `matugen image` with the same wallpaper source when you mean "refresh". Running it against a different image with different flags silently re-palettes all 40 outputs at once. After any regen, `git diff --stat` in `~/dotfiles` should show only what you expect.

## Quickshell desktop shell

The shell replaces Waybar and SwayNC with one QML codebase. Entry is `shell.qml`, which instantiates the bar plus standalone windows sharing one `Colors` palette object:

```qml
ShellRoot {
    Bar {}                          // components/Bar.qml: left / center / right rows
    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    Colors { id: barPalette }       // components/Colors.qml: Matugen palette loader
}
```

The bar window sits at `y=0 h=54`. The center island is a trapezoid tab in classic mode (`SUPER ALT SPACE` flips it against the floating black capsule). Clock, NowPlaying (album art, two-line title/artist, live visualizer bars, hover transport that un-highlights on click), and the bell live flat inside it. System pills (CPU, memory, temp, network, battery, WatchCat) ride left and right as glass pills.

Every visual module takes `property var colors` and every panel closes on `Esc`. Hyprland binds and scripts talk to the shell over IPC, always with the identical path string:

```bash
quickshell -p ~/.config/quickshell                 # run. Never -p . or a realpath.
quickshell -p ~/.config/quickshell ipc show        # list every target
quickshell -p ~/.config/quickshell ipc call wifi toggle
quickshell -p ~/.config/quickshell ipc call notifications toggleDnd
```

> [!WARNING]
> The quickshell daemon owns `org.freedesktop.Notifications`. Keep `swaync` masked or it steals the bus back and toasts stop appearing.

> [!NOTE]
> Mismatched `-p` strings fail with `Target not found` even while a shell is clearly running. Autostart, binds, and manual calls must all use `~/.config/quickshell` verbatim.

### Bar pills

Thin widgets. They display state and delegate detail to panels.

| Module | Role |
|--------|------|
| `ArchLogo` | Distro pill, brand accent |
| `Workspaces` | Live Hyprland workspaces, segmented control |
| `Clock` | Center time, click opens the calendar window, right-click toggles long format |
| `Cpu`, `Memory`, `Temp` | Usage pills, click opens the system monitor |
| `Network` | Wi-Fi/Ethernet pill with capped SSID width, click opens the wifi panel |
| `Battery` | Charge pill with warning/critical states, click opens the battery panel |
| `WatchCat` | Hotspot down-rate pill, click opens the watchdog panel |
| `Tray` | System tray container |
| `StatusPill` | One pill consolidating idle, DND, recording, and tray transient states |
| `BellButton` | Notification bell with unread badge |
| `NowPlaying` | Track art, title/artist, dancing visualizer, hover transport |
| `DndIndicator`, `ScriptIndicator` | Do-not-disturb moon and generic script output |

### Panels and windows

Full surfaces. Overlays are `PanelWindow` layer-shell popups. Larger tools are regular Hyprland `FloatingWindow`s with matching float/center/size rules.

| Module | Role | How it opens |
|--------|------|--------------|
| `WifiPanel` | Network manager, known networks, live throughput graph, Cloudflare speedtest | `SUPER+H`, network pill |
| `SystemMonitor` | Per-core CPU, RAM, network, process list with kill | `SUPER+U`, cpu/memory pills |
| `BatteryPanel` | Charge curve, power profile, time estimates | `SUPER ALT+B`, battery pill |
| `NotificationCenter` | Notification drawer, history, DND toggle | `SUPER+,` |
| `ControlCenter` | Bento grid: Now Playing, weather + pomodoro, quick toggles, network, activity, visualizer | `SUPER ALT+P` |
| `AppLauncher` | Spotlight-style launcher, 7 visible rows, wheel scroll | `SUPER+Space` |
| `PkgManager` | pacman + AUR search, queue, install progress, updates | `SUPER+I` |
| `PdfViewer` | PDF/EPUB library: recents, favorites, title + full-text search, Zathura handoff | `SUPER ALT+N`, `utpdf <file>` |
| `Wallshelf` | Wallhaven storefront: browse, bulk download, local manager, set-as-wallpaper | `SUPER CTRL+Space` |
| `PhoneBridge` | ADB phone bridge: drag-send files, clipboard push, remote browser + pull, ring, screenshot | `SUPER ALT+K` |
| `ThemePanel` | Wallpaper slideshow with preview, applies via `set-wallpaper` | `SUPER+E` |
| `PowerMenu` | Lock, logout, suspend, reboot, shutdown | `SUPER+Escape` |
| `ClipboardPanel` | Clipboard history with image previews (cliphist backend) | `SUPER CTRL+V` |
| `KeybindsPanel` | Searchable, executable keybind cheatsheet | `SUPER+K` |
| `FastFetchWindow` | System info card | `SUPER+N` |
| `ScreenTime` | App-usage heatmap and top apps, Go daemon backend | `SUPER ALT+T` |
| `DriveHealth` | SMART health, disk space, throughput, speed test | `SUPER ALT+D` |
| `WorkspaceViewer` | Fullscreen overview of every workspace with live windows | `SUPER ALT+O` |
| `ClockWindow` | Detached clock card | bar clock click |
| `NowPlayingCard` | Island hover expansion, art-backed | hover the island |
| `MediaOsd` | Volume/brightness/mic overlay | Fn keys |
| `PassPrompt` | System password prompt (`SUDO_ASKPASS` backend) | privileged panel actions |
| `QuickNotes` | Scratch idea capture | IPC |
| `PluginMenu` | Grid opener for extras and plugins only (native modules excluded) | `SUPER ALT+P` legacy slot, now ControlCenter |
| `LockScreen` | Lockscreen with blur, clock, battery | lock bind |
| `Workspaces`, `WorkspaceViewer` | Pager pill plus fullscreen overview | bar, `SUPER ALT+O` |

Retired but still on disk, unwired: `CalendarPanel` (pomodoro moved into ControlCenter) and the standalone `AudioVisualizer` window (visualizer lives in ControlCenter now). `WhatsApp` (panel + `~/whatsapp-bridge` daemon, incl. per-chat mute, channel tags, shared `Toast`) is PARKED, not retired: kept with session intact but unwired and unused over ban caution; WhatsApp pings come from PhoneBridge shade polling meanwhile. `NetRate` and `WeatherIcon` are shared helpers, not surfaces. If you rewire a retired file, update `PLUGINS.md` and the cheatsheet entry with it.

`PhoneBridge.md` next to the module documents the ADB backend contract (`~/phonebridge` CLI, pairing, notify allowlist). `PLUGINS.md` is the registry of every module, its IPC target, and its bind. Keep both current when you change a module.

## Control panel

Go service. Single binary, frontend embedded via `embed.FS`, runs as a user service on `http://localhost:8765`:

```bash
cd ~/dotfiles/panel
go build -o panel .
systemctl --user enable --now dotfiles-panel.service
```

Around 40 endpoints cover live CPU/RAM/battery/network charts, theme plus Ghostty font/opacity/cursor plus Hyprland blur/shadows/gaps/animations, wallpapers with live matugen regen, keybinds (`bindings.conf` with auto-reload) and autostart, monitors, audio, brightness, network, nightlight (`hyprsunset`), TLP profiles and battery health, input devices, journal streaming, and process listing with kill.

> [!NOTE]
> The panel writes into `~/dotfiles` first (stow-aware, symlinks respected), so every change it makes is git-tracked and revertible.

## WatchCat

Hotspot data watchdog for tethered laptops. Tracks every byte against a daily 1 GB cap. Notify-only: it never pauses or blocks traffic.

```bash
# daemon: nethogs per-process rates into sqlite plus live.json, 24/7
systemctl --user enable --now watchcat.service

# dashboard: static HTML regenerated from the database (auto-reloads every 30s)
python3 ~/.config/quickshell/scripts/watchcat-dash.py <out.html> 1024
```

The daemon samples in 12s chunks, flags "hot" processes (over 500 KB/s for 10s+), and warns at 500 MB and 1 GB via `notify-send`. History prunes to 7 days. The `WatchCatPanel.qml` viewer shows live rates, the cap number-line, today's totals, and top talkers. Sudo is scoped to exactly one command in `/etc/sudoers.d/watchcat` (passwordless `nethogs`, nothing else).

## PhoneBridge backend

The QML module is a thin client. All ADB work lives in the standalone `~/phonebridge` backend (separate checkout, documented in `PhoneBridge.md`): pairing over USB-then-WiFi (`adb tcpip 5555` once), drag-send via `adb push` into Download, clipboard push through the bundled relay app, remote browse and pull into `~/PhoneBridge`, find-my-phone ring, screenshots, and a notification forwarder that polls the shade every 4s and pings the desktop with sender names only. If the module says "no phone", the backend (not the UI) is where to look.

## Keybinds

`SUPER+K` opens the searchable cheatsheet. The same list is executable from there. Essentials:

| Keys | Action |
|------|--------|
| `SUPER+Space` / `SUPER+K` | Launcher / keybind cheatsheet |
| `SUPER+Return`, `SUPER SHIFT+F` | Terminal, file manager |
| `SUPER+H` / `SUPER+U` / `SUPER ALT+B` | Wi-Fi panel / system monitor / battery panel |
| `SUPER+E` / `SUPER+I` / `SUPER ALT+N` | Theme / packages / PDF library |
| `SUPER CTRL+Space` | Wallpaper store |
| `SUPER ALT+P` / `T` / `K` / `D` / `Y` | Control center / screen time / phone / drives / WatchCat |
| `SUPER ALT+O` / `SUPER ALT+`,` | Workspace overview / notification center |
| `SUPER+,` / `SUPER SHIFT+,` | Notifications / do-not-disturb |
| `SUPER CTRL+V` / `SUPER+N` | Clipboard / system info |
| `SUPER ALT+Space` / `SUPER SHIFT+Space` | Island style / bar sides |
| `SUPER+Escape` / `SUPER SHIFT+Q/R` | Power menu / shutdown / reboot |
| `SUPER+arrows`, `SUPER+1-0` | Focus, workspaces |
| Fn row | Volume/brightness/mic via the quickshell OSD |

The full list lives in `.config/hypr/bindings.conf` (vendored defaults alongside in `.config/hypr/vendor/`). Every panel also closes on `Esc`.

## Structure

```
~/dotfiles/
├── .config/
│   ├── hypr/                 # Hyprland: vendor defaults + personal *.conf overrides
│   │   ├── bindings.conf     # every keybind (cheatsheet reads this)
│   │   ├── windowrules.conf  # float/center/size for each quickshell window
│   │   ├── looknfeel.conf    # gaps, blur, shadows, animations, layerrules
│   │   ├── monitors.conf / input.conf / autostart.conf / envs.conf
│   │   └── vendor/           # upstream omarchy defaults, do not hand-edit
│   ├── quickshell/           # desktop shell (see module tables above)
│   │   ├── shell.qml         # root: bar + standalone windows + shared palette
│   │   ├── components/       # Bar.qml, Colors.qml
│   │   ├── modules/          # 40+ feature files
│   │   ├── scripts/          # temperature.sh, watchcat daemon + dashboard, idle helpers
│   │   ├── wallshelf.json    # wallpaper store config (API key lives in gitignored wallshelf.ini)
│   │   ├── colors.css        # generated by matugen, polled live, do not hand-edit
│   │   ├── PLUGINS.md        # module registry: IPC target + bind per module
│   │   └── AGENTS.md         # contributor rules for this codebase (read before editing)
│   ├── matugen/              # config.toml + 40 templates (btop, gtk, rofi, nvim, zed, sddm, zathura, …)
│   ├── ghostty/config        # sources theme/current/ghostty.conf
│   ├── kitty/kitty.conf      # sources theme/current/kitty.conf
│   ├── zathura/zathurarc     # matugen-rendered (do not hand-edit, edit the template)
│   ├── rofi/                 # themes + wall.sh / wal.sh / emoji.sh / clipboard.sh
│   ├── nvim/lua/plugins/ / zed/settings.json / tmux/tmux.conf
│   ├── btop/ cava/ fastfetch/ swaync/ swayosd/ gtk-3.0/ gtk-4.0/
│   ├── omarchy/              # legacy mirror some outputs still write
│   ├── systemd/user/         # panel + helper services
├── .local/bin/             # set-wallpaper, getTheme, record, shot, filemanager, …
│   ├── sddm/elarun-custom/   # login theme source → /usr/share/sddm/themes/
│   ├── firefox/user.js       # enables userChrome.css theming
├── panel/                    # Go control panel (main.go + embedded UI)
├── wallpapers/               # local only, git-ignored, never committed
├── assets/                   # vendored blobs + README screenshots (stow-ignored)
├── theme-fallback/           # static snow_black seed
├── .zshrc                    # zsh + lsd/zoxide/fzf/starship/mise
├── .stow-local-ignore
└── install.sh
```

`AGENTS.md` inside `.config/quickshell/` is the contributor contract for the shell: canonical IPC path, panel vs pill vs card patterns, the Amber Bento style tokens, and the verification loop. Read it before touching any `.qml` file.

## Customizing

* Keybinds: `.config/hypr/bindings.conf` (panel Binds page edits this file, Hyprland reloads it)
* Look and feel: `.config/hypr/looknfeel.conf` plus `~/.config/theme/current/colors.conf`
* Bar and modules: `.config/quickshell/modules/*.qml`, then `pkill -x quickshell` and relaunch (never trust hot reload for verdicts)
* New theme template: add it under `.config/matugen/templates/`, map it in `config.toml`, run `matugen image` once
* Terminal: `.config/ghostty/config` and `.config/kitty/kitty.conf` for font and behavior. Colors always come from the generated files

## Gotchas

* Quickshell owns the notification bus. If toasts stop appearing, something (usually `swaync`) grabbed `org.freedesktop.Notifications` first. Mask it.
* Generated files are not source. `colors.css`, `zathurarc`, `cava/config`, and everything under `theme/current/` get overwritten by matugen. Edit the template, never the output.
* Nerd Font codepoints drift between font builds. A glyph that exists can still render as the wrong symbol (a PDF icon once shipped as a dollar sign). Verify by glyph name with fontTools, not by codepoint presence.
* `walshelf.ini` holds the Wallhaven API key and is gitignored on purpose. Never move the key into `wallshelf.json` (tracked).
* The tree is usually dirty. Theme outputs regenerate on every wallpaper change, so `git status` almost always shows modifications. That is normal. Commit only your own files.
* No boot-menu snapshot entries. Snapper timelines run hourly, but recovery is manual (see below), not a Limine menu.

## Disaster recovery (snapper)

Root is btrfs (`@` + `@home` + `@log` + `@pkg`, snapshots in `.snapshots`, hourly timelines enabled).

Most breakages (bad update, nuked `/etc` file, dead Hypr config) still reach a TTY. Log in as root there and roll back. No USB needed:

```bash
snapper list                          # pick a number from before the breakage
snapper rollback 80
reboot
```

A USB stick with an Arch ISO is only needed when nothing boots at all: kernel panic, no login prompt. On this setup that means a bad kernel + initramfs after an interrupted update, a broken `mkinitcpio.conf` (check HOOKS before every `mkinitcpio -P`), a full `/` partition (snapshots live on it too), a bad `/etc/fstab` line, or a damaged ESP/`limine.conf` in `/boot`. Then:

```bash
# from the ISO:
mount -o subvol=@ /dev/sda2 /mnt
arch-chroot /mnt
snapper list
snapper rollback 80
reboot
```

`@home`/`@log`/`@pkg` are separate subvolumes, so rollback never touches your files, logs, or package cache. Snapper keeps the broken `@` as a backup, so a bad rollback is itself reversible. The kernel cmdline pins `rootflags=subvol=@`, and snapper's own rollback restores under the same `@` name, so Limine entries boot it unchanged.

Day-to-day (no reboot involved):

```bash
snapper create -d "before i break things"
snapper undochange 82..0 /etc          # un-break one directory
snapper status 82..0                  # preview what changed first
```

## Credits

* [Matugen](https://github.com/InioX/matugen): Material You generation
* [Hyprland](https://hyprland.org) · [Quickshell](https://quickshell.outfoxxed.me) · [Ghostty](https://ghostty.org) · [Walker](https://github.com/abenz1267/walker)
* [Starship](https://starship.rs) · [FiraCode / JetBrainsMono Nerd Fonts](https://www.nerdfonts.com)
* [Limine](https://limine-bootloader.org) · [Snapper](http://snapper.io) · [Wallhaven](https://wallhaven.cc) (wallpaper source)
