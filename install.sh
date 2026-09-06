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

DEPS=(hyprland quickshell ghostty matugen starship zsh lsd zoxide fzf cava btop stow hyprlock hypridle hyprsunset wl-clipboard cliphist swaync mako walker rofi)
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

# ── Step 3: Copy static fallback colors ───────────────────────────────────────
header "Installing fallback theme colors..."

FALLBACK_DIR="$DOTFILES_DIR/theme-fallback"

if [ -d "$FALLBACK_DIR" ]; then
    cp -r "$FALLBACK_DIR"/. "$THEME_CURRENT/"
    success "Copied fallback colors to $THEME_CURRENT"
else
    warn "No fallback colors found at $FALLBACK_DIR — run matugen after install."
fi

# ── Step 4: Clear integration symlinks before stow ────────────────────────────
# (Recreated after stowing in Step 6 — stow aborts on absolute symlinks it
# doesn't own, so they must not exist when stow runs. Safe on re-runs.)
header "Clearing stale theme integration symlinks..."

rm -f "$HOME/.config/btop/themes/current.theme" "$HOME/.config/cava/themes/matugen"
success "Cleared (recreated after stow)"


# ── Step 5: Stow dotfiles ─────────────────────────────────────────────────────
header "Stowing dotfiles..."

# Back up any existing real files that would conflict with stow
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
CONFLICTS=()

while IFS= read -r -d '' f; do
    rel="${f#$DOTFILES_DIR/}"
    target="$HOME/$rel"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        CONFLICTS+=("$target")
    fi
done < <(find "$DOTFILES_DIR" -not -path "$DOTFILES_DIR/.git/*" -not -name '.git' -type f -print0)

if [ ${#CONFLICTS[@]} -gt 0 ]; then
    mkdir -p "$BACKUP_DIR"
    warn "Backing up ${#CONFLICTS[@]} existing config file(s) to $BACKUP_DIR"
    for f in "${CONFLICTS[@]}"; do
        rel="${f#$HOME/}"
        mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
        mv "$f" "$BACKUP_DIR/$rel"
        info "  Backed up: $f"
    done
    success "Backup complete"
fi

stow --dir="$DOTFILES_DIR" --target="$HOME" --restow .
success "Stow complete — all configs symlinked to \$HOME"

# ── Step 6: Create integration symlinks (AFTER stow) ──────────────────────────
header "Creating theme integration symlinks..."

# btop: color_theme = "current" looks for ~/.config/btop/themes/current.theme
mkdir -p "$HOME/.config/btop/themes"
ln -sf "$HOME/.config/theme/current/btop.theme" "$HOME/.config/btop/themes/current.theme"
success "btop theme symlink: ~/.config/btop/themes/current.theme -> ~/.config/theme/current/btop.theme"

# cava: theme = 'matugen' looks for ~/.config/cava/themes/matugen
mkdir -p "$HOME/.config/cava/themes"
ln -sf "$HOME/.config/theme/current/cava_theme" "$HOME/.config/cava/themes/matugen"
success "cava theme symlink: ~/.config/cava/themes/matugen -> ~/.config/theme/current/cava_theme"

# ── Step 7: Matugen (optional) ────────────────────────────────────────────────
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

# ── Step 8: System-level extras (fonts, SDDM, fastfetch art) ───────────────
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo ""
echo -e "  Next steps:"
echo -e "  ${CYAN}1.${RESET} Log out and back in (or restart Hyprland)"
echo -e "  ${CYAN}2.${RESET} Apply a wallpaper:  ${BOLD}matugen image ~/your-wallpaper.jpg${RESET}"
echo -e "  ${CYAN}3.${RESET} Colors live in:     ${BOLD}~/.config/theme/current/${RESET}"
echo -e "  ${CYAN}4.${RESET} Saved themes in:    ${BOLD}~/.config/theme/themes/${RESET}"
echo -e "  ${CYAN}5.${RESET} SDDM theme, fonts + fetch art handled by Step 8 (needs sudo)"
echo ""
