#!/bin/bash

# ── album-art.sh ──────────────────────────────────────────────────────────────
# Fetches current Spotify album art and saves it to a temp file.
# Waybar calls this and displays the image path.
# Dependencies: playerctl, curl
# ─────────────────────────────────────────────────────────────────────────────

CACHE_DIR="$HOME/.cache/waybar"
CACHE_IMG="$CACHE_DIR/album-art.png"
FALLBACK_IMG="$CACHE_DIR/album-art-fallback.png"
LAST_URL_FILE="$CACHE_DIR/album-art-last-url"

mkdir -p "$CACHE_DIR"

# Create a simple fallback image if it doesn't exist (solid dark square)
if [ ! -f "$FALLBACK_IMG" ]; then
    convert -size 48x48 xc:'#1a1a1a' "$FALLBACK_IMG" 2>/dev/null || \
    cp /usr/share/pixmaps/spotify.png "$FALLBACK_IMG" 2>/dev/null || \
    touch "$FALLBACK_IMG"
fi

# Check if spotify/any player is running
STATUS=$(playerctl --player=spotify status 2>/dev/null)

if [ -z "$STATUS" ] || [ "$STATUS" = "Stopped" ]; then
    echo "{\"text\": \"\", \"class\": \"hidden\"}"
    exit 0
fi

# Get the album art URL from playerctl metadata
ART_URL=$(playerctl --player=spotify metadata mpris:artUrl 2>/dev/null)

if [ -z "$ART_URL" ]; then
    echo "{\"text\": \"\", \"class\": \"hidden\"}"
    exit 0
fi

# Only re-download if the URL changed (avoid hammering the network)
LAST_URL=$(cat "$LAST_URL_FILE" 2>/dev/null)

if [ "$ART_URL" != "$LAST_URL" ]; then
    # Spotify returns https:// URLs
    curl -s -o "$CACHE_IMG" "$ART_URL" 2>/dev/null

    # Resize to a clean square for waybar
    convert "$CACHE_IMG" -resize 48x48^ -gravity center -extent 48x48 \
        -rounded-corners 6 "$CACHE_IMG" 2>/dev/null

    echo "$ART_URL" > "$LAST_URL_FILE"
fi

# Output JSON for waybar
echo "{\"text\": \"\", \"tooltip\": \"$(playerctl --player=spotify metadata xesam:title 2>/dev/null | sed 's/"/\\"/g') — $(playerctl --player=spotify metadata xesam:artist 2>/dev/null | sed 's/"/\\"/g')\", \"class\": \"playing\"}"