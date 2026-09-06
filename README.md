# dotfiles

> Arch Linux · Hyprland · Quickshell · Matugen — wallpaper sets the palette, everything else follows.

![screenshot](./screenshot.png)

A minimal, dynamic rice for Arch Linux. [Hyprland](https://hyprland.org) as the compositor, [Quickshell](https://quickshell.outfoxxed.me) as the desktop shell, and [Matugen](https://github.com/InioX/matugen) (Material You) extracting a full palette from any wallpaper — change the wallpaper and every app recolors live, login screen included.

Standalone: no distro or framework required. It was originally scaffolded from [Omarchy](https://omarchy.org) defaults, but every Omarchy source has been vendored or removed — see [Omarchy independence](#omarchy-independence).

---

## Quick start

```bash
# 1. dependencies — installer warns if anything is missing, doesn't abort
yay -S hyprland quickshell ghostty matugen starship zsh lsd zoxide fzf \
       cava btop walker rofi swaync mako swayosd stow \
       hyprlock hypridle hyprsunset sddm \
       xdg-desktop-portal-hyprland uwsm cliphist wl-clipboard \
       ttf-jetbrainsmono-nerd ttf-firacode-nerd inter-font
# Iceland (login screen) is vendored in assets/fonts/ — installer handles it

# 2. clone + install
git clone https://github.com/codetesla51/uthman_dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

The installer will:
1. Check for missing deps (warns, doesn't exit)
2. Create `~/.config/theme/current/` and `~/.config/theme/themes/snow_black/`
3. Seed fallback colors so the rice works before the first `matugen` run
4. Link `btop` / `cava` theme integrations
5. Back up any real files that would conflict with stow to `~/.config-backup-<timestamp>/`, then `stow --restow .`
6. Offer to run `matugen image <wallpaper>` immediately
7. Install system extras (needs sudo): Inter + vendored Iceland fonts, `elarun-custom` SDDM theme + `/etc/sddm.conf.d` drop-in, Hollow Knight fastfetch art

> [!NOTE]
> Existing configs are never overwritten — they're moved to the timestamped backup dir first.

Apply a wallpaper after install:

```bash
matugen image ~/dotfiles/wallpapers/wallhaven-5y57x8_1920x1080.png
# shims also work
set-wallpaper <image>         # ~/.local/bin/set-wallpaper (wallpaper + regen in one go)
getTheme                      # ~/.local/bin/getTheme
```

---

## Stack

| Layer | What |
|-------|------|
| **Compositor** | Hyprland (Wayland) — standalone, defaults vendored in `.config/hypr/vendor/`, personal overrides in `.config/hypr/*.conf` |
| **Shell / Bar** | Quickshell — trapezium center island, glass panels (`shell.qml` → `components/Bar.qml`) |
| **Theming** | Matugen — 39 templates, writes to `~/.config/theme/current/*` + `~/.config/quickshell/colors.css` + SDDM `Palette.qml` (`~/.config/omarchy/current/theme/*` still written as legacy mirror) |
| **Terminal** | Ghostty (`config-file` sources `~/.config/theme/current/ghostty.conf`) |
| **Shell** | Zsh + Starship + `lsd`/`zoxide`/`fzf`/`mise` |
| **Launcher** | Walker + Rofi (`rofi/emoji.sh`, `clipboard.sh`, `wall.sh` via walker dmenu shim `~/.local/bin/omarchy-launch-walker` — name is legacy, script is local) |
| **Notifications** | Quickshell daemon (`org.freedesktop.Notifications`) — toast + drawer + history; `swaync`/`mako` kept as fallback |
| **Visualizer** | Cava + Cavasik + Quickshell `AudioVisualizer` |
| **Monitors** | btop, `SystemMonitor.qml` (CPU per-core rings, RAM, network, process kill), `swayosd` |
| **Login** | SDDM `elarun-custom` — dark password-only greeter, Hollow Knight mask, Iceland font, matugen palette (source in `sddm/`, installed to `/usr/share/sddm/themes/`) |
| **Fetch** | Fastfetch (kitty-direct logo, Hollow Knight art from `~/fastfetchImages/`, vendored in `assets/fastfetch/`) |
| **Editor** | Neovim (lazy) + Zed |
| **Multiplexer** | tmux (`C-Space` prefix) |

---

## How theming works

Matugen reads the wallpaper and generates a Material You palette, then fills `{{ colors.* }}` variables in each template and writes the result to every app.

```bash
matugen image ~/Pictures/your-wallpaper.jpg   # regenerates all 39 outputs live
```

`~/.config/matugen/config.toml` (`contrast = 0.2`, `variation = "standard"`):

| Template | Input | Output |
|----------|-------|--------|
| `waybar` | `templates/waybar-colors.css` | `~/.config/quickshell/colors.css` |
| `hyprland-theme` / `hyprland-current` | `templates/hyprland-colors.conf` | `snow_black/colors.conf` + `theme/current` (+ `omarchy/current` legacy mirror) |
| `hyprlock-current` / `hyprlock-standalone` | `templates/hyprlock-colors.conf` | `theme/current/hyprlock.conf` (+ `omarchy/current` legacy mirror) |
| `ghostty-theme` / `ghostty-current` | `templates/ghostty-theme.conf` | `snow_black/ghostty.conf` + `theme/current` (+ `omarchy/current` legacy mirror) |
| `gtk-theme` / `gtk-current` | `templates/gtk.css` | `snow_black/gtk.css` + `theme/current` (+ `omarchy/current` legacy mirror) |
| `btop-theme` / `btop-current` | `templates/btop.theme` | `~/.config/theme/themes/snow_black/btop.theme` + `~/.config/theme/current/btop.theme` |
| `cava-theme` / `cava-current` | `templates/cava_theme` | `~/.config/theme/themes/snow_black/cava_theme` + `~/.config/cava/config` |
| `walker-theme` / `walker-current` | `templates/walker.css` | `~/.config/theme/themes/snow_black/walker.css` + `~/.config/theme/current/walker.css` |
| `cavasik` | `templates/cavasik-colors.rgb` | `~/.config/theme/themes/snow_black/cavasik-colors.rgb` + `~/.config/cavasik/colors.rgb` |
| `mako` | `templates/mako.ini` | `~/.config/theme/themes/snow_black/mako.ini` + `~/.config/theme/current/mako.ini` |
| `chromium` | `templates/chromium.theme` | `snow_black` + `current` (+ `omarchy/current` legacy mirror) |
| `pear-desktop` | `templates/pear-desktop.css` | `snow_black` + `current` |
| `sddm` | `templates/sddm-palette.qml` | `/usr/share/sddm/themes/elarun-custom/Palette.qml` (login follows every theme change) |
| `firefox` / `rofi` / `neovim` / `swayosd` / `zed` / `obsidian` / `swaync` | respective templates | per-app `theme/current` outputs |

Active colors live in `~/.config/theme/current/` — rewritten on every `matugen image` run. Saved snapshots stay in `~/.config/theme/themes/snow_black/`. `theme-fallback/` ships the static snow_black seed. (`~/.config/omarchy/current/theme/` is still written as a legacy mirror — quickshell's ThemePanel and `set-wallpaper` check it as fallback, nothing else reads it.)

> [!TIP]
> `Colors.qml` in quickshell polls `~/.config/quickshell/colors.css` every 1s — matugen *replaces* the file (new inode), so palette swaps propagate with no restart.

---

## Quickshell desktop shell

Replaces Waybar/SwayNC. Entry is `shell.qml`:

```qml
ShellRoot {
    Bar {}                          // components/Bar.qml — left/center/right rows
    PowerMenu { colors: barPalette }
    AppLauncher { colors: barPalette }
    AudioVisualizer { colors: barPalette }
    Colors { id: barPalette }       // components/Colors.qml — Matugen palette loader
}
```

**Bar layout (shown in screenshot):** trapezium center island flush to top (`y=0 h=54`, 3-edge stroke), `05:42` clock, `NowPlaying` (art + 2-line title/artist + 5-bar visualizer + hover transport), right-side system pills (CPU/RAM/temp/network/battery). Left has Arch logo + workspace pills.

**Modules** in `~/.config/quickshell/modules/`: `ArchLogo`, `Workspaces`, `Clock`/`ClockWindow`, `Cpu`/`Memory`/`NetRate`/`Temp`/`Battery`, `Network`/`WifiPanel`, `Tray`, `BellButton`/`NotificationCenter`/`NotificationToast`, `NowPlaying`/`MediaOsd`, `SystemMonitor`, `FastFetchWindow`, `ThemePanel`, `AppLauncher`, `PowerMenu`, `PhoneLink`, `ScreenTime`, `ClipboardPanel`, `CalendarPanel`, `KeybindsPanel`, `LockScreen`, etc.

**Run:**

```bash
quickshell -p ~/.config/quickshell   # run
pkill -x quickshell                  # hard restart (avoids auto-reload races on writes)
# notifications IPC
quickshell -p ~/.config/quickshell ipc call notifications toggle
quickshell -p ~/.config/quickshell ipc call notifications toggleDnd
```

> [!WARNING]
> The quickshell daemon owns `org.freedesktop.Notifications`. Keep `swaync` masked/disabled or it will steal the bus back.

---

## Control panel

Go service — single binary, frontend embedded via `embed.FS`. Runs as a systemd user service on `http://localhost:8765`.

```bash
cd ~/dotfiles/panel
go build -o panel .
systemctl --user enable --now dotfiles-panel.service
```

~40 endpoints: `stats`, `system/info`, `processes`/`process/kill`, `logs/stream`+`logs/recent`, `keybinds`/`autostart`, `appearance`/`theme`/`wallpapers`/`wallpaper/set`, `hyprland`/`hypridle`/`ghostty`/`matugen`, `audio`/`brightness`/`network`/`monitors`/`monitor/set`, `dnd`/`mako`/`nightlight`/`waybar`, `wifi`/`wifi/scan`/`connect`/`disconnect`, `bluetooth`, `power`/`powerprofile`, `input`, `effects`, `disks`/`services`, `updates`, `fonts`, `reload`.

What it controls: live CPU/RAM/battery/network charts, theme + Ghostty font/opacity/cursor + Hyprland blur/shadows/gaps/animations, wallpapers (live matugen regen), keybinds (`bindings.conf` with auto-reload) + autostart, monitors/audio/brightness/network/waybar position/nightlight (`hyprsunset`), TLP profiles + battery health, input devices, journal streaming, process list with kill.

> [!NOTE]
> The panel writes to `~/dotfiles` first (stow-aware — symlinks respected), so every change is git-tracked.

---

## Structure

```
~/dotfiles/
├── .config/
│   ├── hypr/                 # Hyprland — standalone (vendored defaults + personal overrides)
│   │   ├── hyprland.conf     # sources vendor/* + theme/current
│   │   ├── bindings.conf     # personal keybinds
│   │   ├── autostart.conf    # startup apps
│   │   ├── envs.conf         # PATH / env
│   │   ├── monitors.conf     # displays
│   │   ├── input.conf        # devices
│   │   ├── looknfeel.conf    # gaps, blur, shadows, animations
│   │   ├── windowrules.conf
│   │   ├── hyprlock.conf / hypridle.conf / hyprsunset.conf / xdph.conf
│   │   ├── scripts/          # battery.sh, now_playing.sh, sysinfo.sh, etc.
│   │   └── shaders/          # 70+ glsl shaders (amber, crt, cyberpunk, gameboy, etc.)
│   ├── quickshell/           # desktop shell (replaces waybar)
│   │   ├── shell.qml
│   │   ├── components/Bar.qml, Colors.qml
│   │   ├── modules/          # 30+ QML modules (see above)
│   │   └── colors.css        # generated by matugen, watched live
│   ├── ghostty/config        # sources theme/current/ghostty.conf
│   ├── matugen/
│   │   ├── config.toml       # 39 templates
│   │   └── templates/        # 39 per-app templates (btop, cava, gtk, walker, rofi, nvim, zed, sddm, …)
│   ├── rofi/                 # themes + wall.sh / wal.sh / emoji.sh / clipboard.sh
│   ├── nvim/lua/plugins/     # colorscheme, theme hot-reload
│   ├── tmux/tmux.conf        # C-Space prefix, vim keys
│   ├── zed/settings.json
│   ├── btop/ cava/ fastfetch/ swaync/ swayosd/ gtk-3.0/ gtk-4.0/
│   ├── omarchy/              # legacy mirror (matugen outputs) + hooks — see Omarchy independence
│   ├── systemd/user/         # panel service
│   └── starship.toml
│   ├── .local/bin/omarchy-launch-walker   # rofi/walker dmenu shim
├── sddm/elarun-custom/       # login theme source (Main.qml, Palette.qml, logos) → /usr/share/sddm/themes/
├── assets/                   # vendored blobs: fastfetch knight art, Iceland font (stow-ignored)
├── panel/                    # Go control panel (main.go + static/ embedded UI)
├── wallpapers/               # 7 wallpapers (wallhaven collection)
├── theme-fallback/           # static snow_black seed (8 files)
├── Pictures/                 # screenshot drop folder (`shot` saves here)
├── .zshrc                    # zsh + lsd/zoxide/fzf/starship/mise
├── .stow-local-ignore        # README.md, install.sh, theme-fallback, screenshot.png, wallpapers
├── install.sh
└── screenshot.png            # 1920×1080 hero (this README)
```

---

## Customizing

- **Keybinds:** `~/.config/hypr/bindings.conf` (panel → Binds writes here, Hyprland reloads)
- **Autostart:** `~/.config/hypr/autostart.conf`
- **Look & feel:** `~/.config/hypr/looknfeel.conf` + `~/.config/theme/current/colors.conf`
- **Ghostty:** `~/.config/ghostty/config` — font/cursor/opacity; colors come from `ghostty.conf` template
- **Quickshell:** edit `modules/*.qml`; `Colors.qml` handles palette. Icons are literal Nerd Font glyphs, no `\uXXXX` escapes.
- **Matugen templates:** `~/.config/matugen/templates/*` → `config.toml` maps `input_path` → `output_path`
- **Neovim / Zed / tmux:** `~/.config/nvim/`, `~/.config/zed/settings.json`, `~/.config/tmux/tmux.conf`

---

## Omarchy independence

No Omarchy install required — nothing is sourced from `~/.local/share/omarchy/` and no `omarchy-*` package is needed. What remains of that history:

- **Vendored defaults** — `.config/hypr/vendor/` started as copies of Omarchy's Hyprland defaults, sanitized for standalone use.
- **Legacy mirror** — matugen still writes `~/.config/omarchy/current/theme/*`; harmless, kept for old overrides.
- **Legacy names** — `~/.local/bin/omarchy-launch-walker` is a local walker/dmenu shim, name kept so existing binds keep working.
- **Dead binds** — a few keybinds still call Omarchy helpers that don't exist here (`omarchy-menu*`, `omarchy-reminder*`, `omarchy-transcode`, `omarchy-launch-audio/bluetooth/wifi`, `omarchy-hyprland-window-*`, `omarchy-battery/weather-status`). They fail silent. Everything essential (screenshot, lock, volume, brightness, nightlight, gaps, touchpad, monitors) is a local script in `.local/bin/`.

Replacing the dead binds with local scripts is the remaining decoupling work.

---

## Credits

- [Omarchy](https://omarchy.org) — original scaffold this rice was built from (since fully decoupled)
- [Matugen](https://github.com/InioX/matugen) — Material You generation
- [Hyprland](https://hyprland.org) · [Quickshell](https://quickshell.outfoxxed.me) · [Ghostty](https://ghostty.org) · [Walker](https://github.com/abenz1267/walker)
- [Starship](https://starship.rs) · [FiraCode / JetBrainsMono Nerd Fonts](https://www.nerdfonts.com)

---

MIT — see [LICENSE](LICENSE) if present.
