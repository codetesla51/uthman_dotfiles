# dotfiles

Arch Linux, Hyprland, Quickshell, Matugen. Wallpaper sets the palette, everything else follows.

![screenshot](./assets/screenshots/screenshot-1.png)
![screenshot](./assets/screenshots/screenshot-2.png)
![screenshot](./assets/screenshots/screenshot-3.png)

## Fresh machine

```bash
yay -S hyprland quickshell kitty matugen starship zsh lsd zoxide fzf \
       cava btop rofi swayosd hyprlock hypridle hyprsunset sddm \
       xdg-desktop-portal-hyprland uwsm cliphist wl-clipboard \
       ttf-jetbrainsmono-nerd ttf-firacode-nerd inter-font
git clone https://github.com/codetesla51/uthman_dotfiles.git ~/dotfiles
cd ~/dotfiles && chmod +x install.sh && ./install.sh
set-wallpaper ~/Pictures/your-wallpaper.jpg
```

Reboot once after the first install (SDDM theme lands in `/usr/share/sddm/themes/`, user services start on fresh login). Lost after that: `SUPER+K` is the keybind cheatsheet.
## How theming works

Matugen reads the wallpaper, builds a Material You palette, and fills variables in each template. One command recolors everything with no restarts:

```bash
matugen image ~/Pictures/your-wallpaper.jpg
```

`~/.config/matugen/config.toml` maps each template to its outputs. The main ones:

| Template | Output |
|----------|--------|
| `waybar` | `~/.config/quickshell/colors.css` (the file the live shell polls) |
| `hyprland-*` | `snow_black/colors.conf` + `theme/current` |
| `hyprlock-*`, `kitty-*`, `gtk`, `btop` | matching live files under `theme/current` |
| `cava` | `snow_black/cava_theme` + `~/.config/cava/config` (rewritten directly) |
| `sddm` | `/usr/share/sddm/themes/elarun-custom/Palette.qml` (login follows every theme change) |
| `firefox` | `theme/current/firefox{,-usercontent}.css`, symlinked as `userChrome.css`/`userContent.css` |
| `rofi`, `neovim`, `swayosd`, `zed`, `obsidian`, `zathura` | per-app live outputs |

Active colors live in `~/.config/theme/current/` and are rewritten on every run. `snow_black/` keeps saved snapshots, `theme-fallback/` ships the static seed.

> [!TIP]
> `Colors.qml` polls `~/.config/quickshell/colors.css` every second. Matugen replaces the file (new inode) instead of editing it, so the poller re-reads rather than watching. Palette swaps propagate with no restart.

> [!WARNING]
> Always run full `matugen image` with the same wallpaper source when you mean "refresh". Running it against a different image silently re-palettes all outputs at once. After any regen, `git diff --stat` in `~/dotfiles` should show only what you expect.

## Quickshell desktop shell

The shell replaces Waybar and SwayNC with one QML codebase. Entry is `shell.qml`, which instantiates the bar plus standalone windows sharing one `Colors` palette object. The bar window sits at `y=0 h=54`. The center tab is a trapezoid in classic mode, and `SUPER ALT SPACE` flips it into a floating black capsule. Clock, NowPlaying (album art, title/artist, live visualizer, hover transport), and the bell live flat inside it. System pills (CPU, memory, temp, network, battery, WatchCat) ride left and right as glass pills.

Hyprland binds and scripts talk to the shell over IPC, always with the identical path string:

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
| `Clock` | Center time, click opens the clock card, right-click toggles long format |
| `Cpu`, `Memory`, `Temp` | Usage pills, click opens the system monitor |
| `Network` | Wi-Fi/Ethernet pill, click opens the wifi panel |
| `Battery` | Charge pill with warning/critical states, click opens the battery panel |
| `WatchCat` | Hotspot down-rate pill, click opens the watchdog panel |
| `Tray` | System tray container |
| `StatusPill` | One pill consolidating idle, DND, recording, and tray transient states |
| `BellButton` | Notification bell with unread badge |
| `NowPlaying` | Track art, title/artist, dancing visualizer, hover transport |

### Panels and windows

Overlays are `PanelWindow` layer-shell popups. Larger tools are regular Hyprland `FloatingWindow`s with matching float/center/size rules. Every panel closes on `Esc`.

| Module | Role | How it opens |
|--------|------|--------------|
| `WifiPanel` | Network manager, known networks, live throughput graph, Cloudflare speedtest | `SUPER+H`, network pill |
| `SystemMonitor` | Per-core CPU, RAM, network, process list with kill | `SUPER+U`, cpu/memory pills |
| `BatteryPanel` | Charge curve, power profile, time estimates | `SUPER ALT+B`, battery pill |
| `NotificationCenter` | Notification drawer, history, DND toggle | `SUPER+,` |
| `ControlCenter` | Bento grid: Now Playing, weather + pomodoro, quick toggles, network, activity, visualizer | `SUPER ALT+P` |
| `AppLauncher` | Spotlight-style launcher, wheel scroll | `SUPER+Space` |
| `PkgManager` | pacman + AUR search, queue, install progress, updates | `SUPER+I` |
| `PdfViewer` | PDF/EPUB library: recents, favorites, full-text search, Zathura handoff | `SUPER ALT+N`, `utpdf <file>` |
| `Wallshelf` | Wallhaven storefront: browse, bulk download, set-as-wallpaper | `SUPER CTRL+Space` |
| `PhoneBridge` | ADB phone bridge: drag-send files, clipboard push, remote browser + pull, ring, screenshot | `SUPER ALT+K` |
| `ThemePanel` | Wallpaper slideshow with preview, applies via `set-wallpaper` | `SUPER+E` |
| `PowerMenu` | Lock, logout, suspend, reboot, shutdown | `SUPER+Escape` |
| `ClipboardPanel` | Clipboard manager (Hyprland window): history with image previews (cliphist backend) plus a Sticky shelf of pinned snippets in LocalStorage, fired with `SUPER ALT 1-9` | `SUPER CTRL+V` (window), `SUPER CTRL+P` (pin current clipboard from anywhere) |
| `KeybindsPanel` | Searchable, executable keybind cheatsheet | `SUPER+K` |
| `FastFetchWindow` | System info card | `SUPER+N` |
| `ScreenTime` | App-usage heatmap and top apps, Go daemon backend | `SUPER ALT+T` |
| `DriveHealth` | SMART health, disk space, throughput, speed test | `SUPER ALT+D` |
| `WorkspaceViewer` | Fullscreen overview of every workspace with live windows | `SUPER ALT+O` |
| `ClockWindow` | Detached clock card | bar clock click |
| `MediaOsd` | Volume/brightness/mic overlay | Fn keys |
| `PassPrompt` | System password prompt (`SUDO_ASKPASS` backend) | privileged panel actions |

Unwired but still on disk: `QuickNotes` (scratch idea capture; nothing instantiates it, so its `notes` target is never served and the panel never opens) and `WhatsApp` (PARKED, not retired: kept with session intact but commented out of `Bar.qml` and unused over ban caution; WhatsApp pings come from PhoneBridge shade polling meanwhile). `NetRate` and `WeatherIcon` are shared helpers, not surfaces. If you rewire an unwired file, update `PLUGINS.md` and the cheatsheet entry with it.

`PhoneBridge.md` next to the module documents the ADB backend contract. `PLUGINS.md` is the registry of every module, its IPC target, and its bind. Keep both current when you change a module.

## Notifications

The shell is its own notification daemon. Toasts carry action buttons, screenshot notifications carry a Save button that files the image into `~/Pictures/Screenshots`, and everything lands in the history drawer. When an app ships no icon, the row falls back to a per-app Phosphor glyph (40+ apps mapped, from Firefox and WhatsApp down to `brightnessctl` and `grim`), so rows never show bare initial letters. `notify-send -a <AppName>` is all a sender needs for a correct icon.

## Screen time

The `screentime` Go daemon (separate checkout at `~/projects/screentime`, also runs as a user service) samples the focused window every 10 seconds into SQLite. `ScreenTime.qml` renders the heatmap and top apps from `screentime --export all`, and the control center activity bars read the same export. One source, both views agree.

## Companion repos

These live outside this repo but plug into the shell:

| Repo | What it is |
|------|------------|
| `~/projects/screentime` | Screen time Go daemon + SQLite store |
| `~/phonebridge` | ADB backend for the PhoneBridge module |
| `~/whatsapp-bridge` | WhatsApp daemon (parked) |
| `github.com/codetesla51/qemu-launch` | Bubble Tea QEMU launcher: ISOs from `~/Downloads`, per-VM store in `~/VMs` |

## WatchCat

Hotspot data watchdog for tethered laptops. Tracks every byte against a daily 1 GB cap. Notify-only: it never pauses or blocks traffic.

```bash
# daemon: nethogs per-process rates into sqlite plus live.json, 24/7
systemctl --user enable --now watchcat.service

# dashboard: static HTML regenerated from the database (auto-reloads every 30s)
python3 ~/.config/quickshell/scripts/watchcat-dash.py <out.html> 1024
```

The daemon samples in 12s chunks, flags "hot" processes (over 500 KB/s for 10s+), and warns at 500 MB and 1 GB via `notify-send`. History prunes to 7 days. Sudo is scoped to exactly one command in `/etc/sudoers.d/watchcat` (passwordless `nethogs`, nothing else).

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
| `SUPER ALT+O` / `SUPER+,` | Workspace overview / notification center |
| `SUPER+,` / `SUPER SHIFT+,` | Notifications / do-not-disturb |
| `SUPER CTRL+V` / `SUPER CTRL+P` / `SUPER+N` | Clipboard window / pin clipboard to sticky shelf / system info |
| `SUPER ALT+Space` / `SUPER SHIFT+Space` | Island style / bar sides |
| `SUPER+Escape` / `SUPER SHIFT+Q/R` | Power menu / shutdown / reboot |
| `SUPER+arrows`, `SUPER+1-0` | Focus, workspaces |
| Fn row | Volume/brightness/mic via the quickshell OSD |

The full list lives in `.config/hypr/bindings.conf` (vendored defaults alongside in `.config/hypr/vendor/`). Every panel also closes on `Esc`.

## Helper scripts

`~/.local/bin/` (stowed from this repo) holds the CLI surface: `set-wallpaper`, `getTheme`, `shot`, `record`, `utpdf`, `vol`, `bright`, `nightlight`, `lock`, `phone-pair`, `qemu-launch`, and more. These are what binds, panels, and muscle memory call.

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
│   │   ├── modules/          # 50 feature files
│   │   ├── scripts/          # temperature.sh, watchcat daemon + dashboard, idle helpers
│   │   ├── colors.css        # generated by matugen, polled live, do not hand-edit
│   │   ├── PLUGINS.md        # module registry: IPC target + bind per module
│   │   └── AGENTS.md         # contributor rules for this codebase (read before editing)
│   ├── matugen/              # config.toml + templates (btop, gtk, rofi, nvim, zed, sddm, zathura, …)
│   ├── kitty/kitty.conf      # sources theme/current/kitty.conf
│   ├── systemd/user/         # helper services
├── .local/bin/             # set-wallpaper, getTheme, record, shot, …
├── sddm/elarun-custom/     # login theme source → /usr/share/sddm/themes/
├── firefox/user.js         # enables userChrome.css theming
├── wallpapers/             # local only, git-ignored, never committed
├── assets/                 # vendored blobs + README screenshots (stow-ignored)
├── theme-fallback/         # static snow_black seed
├── .zshrc                  # zsh + lsd/zoxide/fzf/starship/mise
├── .stow-local-ignore
└── install.sh
```

`AGENTS.md` inside `.config/quickshell/` is the contributor contract for the shell: canonical IPC path, panel vs pill vs card patterns, the Amber Bento style tokens, and the verification loop. Read it before touching any `.qml` file.

## Customizing

* Keybinds: `.config/hypr/bindings.conf` (panel Binds page edits this file, Hyprland reloads it)
* Look and feel: `.config/hypr/looknfeel.conf` plus `~/.config/theme/current/colors.conf`
* Bar and modules: `.config/quickshell/modules/*.qml`, then restart quickshell (never trust hot reload for verdicts)
* New theme template: add it under `.config/matugen/templates/`, map it in `config.toml`, run `matugen image` once
* Terminal: `.config/kitty/kitty.conf` for font and behavior. Colors always come from the generated files

## Gotchas

* Quickshell owns the notification bus. If toasts stop appearing, something (usually `swaync`) grabbed `org.freedesktop.Notifications` first. Mask it.
* Generated files are not source. `colors.css`, `zathurarc`, `cava/config`, and everything under `theme/current/` get overwritten by matugen. Edit the template, never the output.
* Nerd Font codepoints drift between font builds. A glyph that exists can still render as the wrong symbol. Verify by glyph name with fontTools, not by codepoint presence. Same goes for Phosphor icons: this repo's build is ligature-mapped, so codepoints were resolved through its GSUB table.
* `wallshelf.ini` holds the Wallhaven API key and is gitignored on purpose. Never move the key into `wallshelf.json` (tracked).
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

`@home`/`@log`/`@pkg` are separate subvolumes, so rollback never touches your files, logs, or package cache. Snapper keeps the broken `@` as a backup, so a bad rollback is itself reversible.

Day-to-day (no reboot involved):

```bash
snapper create -d "before i break things"
snapper undochange 82..0 /etc          # un-break one directory
snapper status 82..0                  # preview what changed first
```

## Locked out (passwords, login, screen lock)

Three ladders, in order. This disk is **not encrypted** (plain btrfs on `/dev/sda2`, ESP on `/dev/sda1`), so a forgotten password is an inconvenience, never data loss. There is no scenario here where snapshots can't reach your files as long as you can boot an ISO.

**Ladder 1: a TTY.** `CTRL ALT F3` through `F6` (SDDM owns `tty1`, so do not fight it there). Log in as your user or as root and fix it directly:

```bash
passwd uthman                  # forgotten user password (as root)
loginctl unlock-sessions       # stuck at the hyprlock screen
snapper rollback 80            # broke it with an update, see above
```

SDDM login-looping but the TTY works almost always means the Hyprland session dies on start: check `~/.config/hypr/` for the last edit and `journalctl --user -xe` for the crash line before rolling anything back.

**Ladder 2: no TTY at all, or both passwords lost.** Boot an Arch ISO. `sudo` on this machine requires a password (no `NOPASSWD` backdoor outside the scoped `nethogs` rule), so if no password works anywhere, the ISO is the backstop, not a trick:

```bash
# from the ISO (by-UUID so a renamed disk can't fool you):
mount -o subvol=@ /dev/disk/by-uuid/600e2481-86c4-40a8-9c2a-a287f3fc1c64 /mnt
mount -o subvol=@home /dev/disk/by-uuid/600e2481-86c4-40a8-9c2a-a287f3fc1c64 /mnt/home
arch-chroot /mnt
passwd uthman                  # or: snapper list + snapper rollback 80
reboot
```

`@home` is a separate subvolume, so even a full `@` rollback never touches your files. If you only need one file back, mount `@home` and copy it to a USB stick without chrooting at all.

**Know before it happens.** Root TTY login needs the root password; if root was never given one (locked `!` account), Ladder 1's `passwd` path doesn't exist and you go straight to Ladder 2. Worth verifying now, while nothing is broken: `sudo passwd -S root` should not report `L`.
