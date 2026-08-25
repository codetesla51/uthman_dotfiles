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
    if ! command -v "$dep" &>/dev/null; then
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

# ── Step 4: Create integration symlinks ───────────────────────────────────────
header "Creating theme integration symlinks..."

# btop: color_theme = "current" looks for ~/.config/btop/themes/current.theme
mkdir -p "$HOME/.config/btop/themes"
ln -sf "$HOME/.config/theme/current/btop.theme" "$HOME/.config/btop/themes/current.theme"
success "btop theme symlink: ~/.config/btop/themes/current.theme -> ~/.config/theme/current/btop.theme"

# cava: theme = 'matugen' looks for ~/.config/cava/themes/matugen
mkdir -p "$HOME/.config/cava/themes"
ln -sf "$HOME/.config/theme/current/cava_theme" "$HOME/.config/cava/themes/matugen"
success "cava theme symlink: ~/.config/cava/themes/matugen -> ~/.config/theme/current/cava_theme"


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

# ── Step 6: Matugen (optional) ────────────────────────────────────────────────
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  Installation complete!${RESET}"
echo ""
echo -e "  Next steps:"
echo -e "  ${CYAN}1.${RESET} Log out and back in (or restart Hyprland)"
echo -e "  ${CYAN}2.${RESET} Apply a wallpaper:  ${BOLD}matugen image ~/your-wallpaper.jpg${RESET}"
echo -e "  ${CYAN}3.${RESET} Colors live in:     ${BOLD}~/.config/theme/current/${RESET}"
echo -e "  ${CYAN}4.${RESET} Saved themes in:    ${BOLD}~/.config/theme/themes/${RESET}"
echo ""
