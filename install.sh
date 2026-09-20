#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dotfiles install.sh
# Arch Linux · Hyprland · Matugen dynamic theming
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_CURRENT="$HOME/.config/theme/current"
THEME_SNOW_BLACK="$HOME/.config/theme/themes/snow_black"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}  ${RESET} $*"; }
success() { echo -e "${GREEN}  ${RESET} $*"; }
warn()    { echo -e "${YELLOW}  ${RESET} $*"; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Step 1: Check dependencies ────────────────────────────────────────────────
header "Checking dependencies..."

# Note: notifications are owned by the Quickshell shell (org.freedesktop.Notifications),
# and the app launcher is the local rofi shim ~/.local/bin/walker-dmenu — so neither
# walker, mako nor swaync is a real dependency.
DEPS=(hyprland quickshell kitty matugen starship zsh lsd zoxide fzf cava btop stow hyprlock hypridle hyprsunset wl-clipboard cliphist rofi)
MISSING=()

for dep in "${DEPS[@]}"; do
    # wl-clipboard ships wl-copy/wl-paste, not a `wl-clipboard` binary
    check="$dep"
    [ "$dep" = "wl-clipboard" ] && check="wl-copy"
    if ! command -v "$check" &>/dev/null; then
        MISSING+=("$dep")
        warn "Not found: $dep"
    else
        success "Found: $dep"
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    warn "Missing dependencies: ${MISSING[*]}"
    warn "Install with: yay -S ${MISSING[*]}"
    echo ""
    read -rp "  Continue anyway? [y/N] " cont
    [[ "$cont" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# ── Step 2: Create theme directories ──────────────────────────────────────────
header "Creating theme directories..."

mkdir -p "$THEME_CURRENT"
mkdir -p "$THEME_SNOW_BLACK"
success "Created $THEME_CURRENT"
success "Created $THEME_SNOW_BLACK"

# ~/.local must already exist as a real dir before stow runs: if it does not,
# stow folds the whole tree into one symlink and ~/.local/share (Zed, mise,
# pip and node data) would be redirected into this repo. Same reasoning as the
# theme dirs above, which stop stow from folding .config.
mkdir -p "$HOME/.local/bin" "$HOME/.local/share"

# ── Step 3: Copy static fallback colors ───────────────────────────────────────
header "Installing fallback theme colors..."

FALLBACK_DIR="$DOTFILES_DIR/theme-fallback"

if [ -d "$FALLBACK_DIR" ]; then
    cp -r "$FALLBACK_DIR"/. "$THEME_CURRENT/"
    success "Copied fallback colors to $THEME_CURRENT"
else
    warn "No fallback colors found at $FALLBACK_DIR — run matugen after install."
fi

# ── Step 4: Stow dotfiles ─────────────────────────────────────────────────────
# Theme wiring (btop/cava/gtk symlinks) ships inside the repo as relative
# symlinks into the $HOME theme dirs. They are calibrated for stow's default
# folded layout with the repo at ~/dotfiles, so one stow pass links
# everything — no post-stow fixups to run or forget.
header "Stowing dotfiles..."

if [ "$DOTFILES_DIR" != "$HOME/dotfiles" ]; then
    warn "Repo is not at ~/dotfiles — relative theme symlinks (btop/cava/gtk) will not resolve from here."
fi

# Ask stow where it would collide (dry run) and back those paths up first.
# Deriving the list from stow itself — not re-implementing stow's ignore
# rules — keeps this in lockstep with .stow-local-ignore, so a fresh install
# can never abort mid-stow. Foreign symlinks stow wouldn't own (e.g. service
# files) are preserved in the backup and re-created by stow in canonical form.
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
readarray -t CONFLICTS < <(stow --dir="$DOTFILES_DIR" --target="$HOME" --no --verbose=2 . 2>&1 \
    | sed -n -e 's/.*existing target is not owned by stow: *//p' \
             -e 's/.*cannot stow .* over existing target \([^ ]*\).*/\1/p' \
    | sort -u)

# Legacy installs left .config/btop and .config/cava as real directories with
# absolute wiring links. Moving them aside (preserved in the backup) lets
# stow fold them, so fresh and upgraded machines end up byte-identical.
for d in btop cava; do
    t="$HOME/.config/$d"
    if [ -d "$t" ] && [ ! -L "$t" ]; then
        mkdir -p "$BACKUP_DIR"
        mv "$t" "$BACKUP_DIR/$d"
        warn "  Normalized legacy real dir .config/$d into a stow fold (backup: $BACKUP_DIR/$d)"
    fi
done

if [ ${#CONFLICTS[@]} -gt 0 ]; then
    mkdir -p "$BACKUP_DIR"
    warn "Backing up ${#CONFLICTS[@]} conflicting path(s) to $BACKUP_DIR"
    for rel in "${CONFLICTS[@]}"; do
        target="$HOME/$rel"
        if [ -L "$target" ]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
            cp -P "$target" "$BACKUP_DIR/$rel" && rm -f "$target"
        elif [ -e "$target" ]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
            mv "$target" "$BACKUP_DIR/$rel"
        else
            continue
        fi
        info "  Backed up: $target"
    done
    success "Backup complete"
fi

# ~/.config already exists as a real directory (Step 2), so stow descends
# into it and links each subtree — it never folds .config into one symlink.
stow --dir="$DOTFILES_DIR" --target="$HOME" --restow .
success "Stow complete — all configs symlinked to \$HOME"

# ── Step 5: Matugen (optional) ────────────────────────────────────────────────
header "Matugen dynamic theming (optional)"

echo ""
read -rp "  Generate colors from a wallpaper now? [y/N] " run_matugen

if [[ "$run_matugen" =~ ^[Yy]$ ]]; then
    read -rp "  Wallpaper path: " wallpaper_path
    wallpaper_path="${wallpaper_path/#\~/$HOME}"

    if [ -f "$wallpaper_path" ]; then
        info "Running: matugen image $wallpaper_path"
        # Use getTheme wrapper if available (handles reload + compat symlinks)
        if [[ -x "$DOTFILES_DIR/.local/bin/getTheme" ]]; then
            bash "$DOTFILES_DIR/.local/bin/getTheme" "$wallpaper_path" || matugen image "$wallpaper_path" --mode dark --type scheme-fidelity --contrast 0.2
        else
            matugen image "$wallpaper_path" --mode dark --type scheme-fidelity --contrast 0.2 || matugen image "$wallpaper_path"
        fi
        mkdir -p ~/.config/theme/current ~/.config/omarchy/current 2>/dev/null || true
        ln -sfn "$(realpath "$wallpaper_path")" ~/.config/theme/current/background 2>/dev/null || true
        ln -sfn "$(realpath "$wallpaper_path")" ~/.config/omarchy/current/background 2>/dev/null || true
        success "Matugen ran successfully — colors updated!"
    else
        warn "File not found: $wallpaper_path"
        warn "Run manually later: matugen image ~/your-wallpaper.jpg"
    fi
else
    info "Skipped. Run later with: matugen image ~/your-wallpaper.jpg"
fi

# ── Step 6: System-level extras (fonts, SDDM, fastfetch art) ───────────────
header "System extras (needs sudo for fonts/SDDM)..."

# Inter from repos; Iceland is vendored (SDDM runs as its own user and
# cannot read $HOME fonts, so both must live in /usr/share/fonts).
if fc-list | grep -qi " inter"; then
    success "Inter already installed"
else
    info "Installing inter-font (sudo)..."
    sudo pacman -S --needed --noconfirm inter-font && success "Inter installed" || warn "inter-font install failed"
fi
if fc-list | grep -qi iceland; then
    success "Iceland already installed"
else
    info "Installing vendored Iceland to /usr/share/fonts (sudo)..."
    sudo cp "$DOTFILES_DIR/assets/fonts/Iceland-Regular.ttf" /usr/share/fonts/TTF/ && sudo fc-cache -f && success "Iceland installed" || warn "Iceland install failed"
fi

# SDDM theme (source of truth: sddm/elarun-custom/; Palette.qml refreshes
# on every matugen run via the [templates.sddm] template).
if [ -d /usr/share/sddm/themes/elarun-custom ]; then
    success "SDDM theme already installed"
else
    info "Installing elarun-custom SDDM theme (sudo)..."
    sudo cp -r "$DOTFILES_DIR/sddm/elarun-custom" /usr/share/sddm/themes/ && sudo chown -R "$USER:$USER" /usr/share/sddm/themes/elarun-custom && success "SDDM theme installed" || warn "SDDM install failed"
fi
if grep -q "Current=elarun-custom" /etc/sddm.conf.d/10-theme.conf 2>/dev/null; then
    success "SDDM already points at elarun-custom"
else
    info "Pointing SDDM at elarun-custom (sudo)..."
    sudo mkdir -p /etc/sddm.conf.d && printf '[Theme]\nCurrent=elarun-custom\n' | sudo tee /etc/sddm.conf.d/10-theme.conf >/dev/null && success "SDDM configured" || warn "SDDM config failed"
fi

# fastfetch art (absolute path referenced by fastfetch config + quickshell)
mkdir -p "$HOME/fastfetchImages"
if [ -f "$HOME/fastfetchImages/The_Knight__Hollow_Knight_-removebg-preview.png" ]; then
    success "fastfetch art already present"
else
    cp "$DOTFILES_DIR/assets/fastfetch/The_Knight__Hollow_Knight_-removebg-preview.png" "$HOME/fastfetchImages/" && success "fastfetch art installed"
fi

# Firefox theme: matugen userChrome.css + user.js pref, symlinked into the
# default profile (no prefs.js edits — user.js is read-only for Firefox).
for _ffbase in "$HOME/.mozilla/firefox" "$HOME/.config/mozilla/firefox"; do
    [ -f "$_ffbase/profiles.ini" ] || continue
    _profdir=$(ls -d "$_ffbase"/*.default-release 2>/dev/null | head -1)
    [ -z "$_profdir" ] && _profdir=$(ls -d "$_ffbase"/*.default* 2>/dev/null | head -1)
    [ -z "$_profdir" ] && continue
    mkdir -p "$_profdir/chrome"
    if [ -f "$HOME/.config/theme/current/firefox.css" ]; then
        # Real files, not symlinks: Firefox's sandboxed UI process silently
        # skips a symlinked userChrome.css. getTheme re-copies these on every
        # theme switch.
        cp -f "$HOME/.config/theme/current/firefox.css" "$_profdir/chrome/userChrome.css"
        cp -f "$HOME/.config/theme/current/firefox-usercontent.css" "$_profdir/chrome/userContent.css"
        ln -sf "$DOTFILES_DIR/firefox/user.js" "$_profdir/user.js"
        success "Firefox theme wired: $_profdir"
    else
        warn "No theme CSS yet in ~/.config/theme/current — run matugen (Step 5) first, then re-run install"
    fi
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo ""
echo -e "  Next steps:"
echo -e "  ${CYAN}1.${RESET} Log out and back in (or restart Hyprland)"
echo -e "  ${CYAN}2.${RESET} Apply a wallpaper:  ${BOLD}matugen image ~/your-wallpaper.jpg${RESET}"
echo -e "  ${CYAN}3.${RESET} Colors live in:     ${BOLD}~/.config/theme/current/${RESET}"
echo -e "  ${CYAN}4.${RESET} Saved themes in:    ${BOLD}~/.config/theme/themes/${RESET}"
echo -e "  ${CYAN}5.${RESET} SDDM theme, fonts + fetch art handled by Step 6 (needs sudo)"
echo ""
