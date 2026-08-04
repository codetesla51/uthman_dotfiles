#!/usr/bin/env bash
WALL_DIR="/home/uthman/.config/omarchy/themes/snow_black/backgrounds"
THUMB_DIR="/tmp/wall_thumbs"
LOOKUP_FILE="/tmp/wall_lookup.json"
SCRIPT_PATH="/home/uthman/.config/rofi/wall.sh"
selected="$1"

mkdir -p "$THUMB_DIR"

if [[ -n "$selected" ]]; then
    cleaned=$(jq -r --arg key "$selected" '.[$key] // empty' "$LOOKUP_FILE")
    if [[ -z "$cleaned" ]]; then
        echo "Could not resolve: $selected"
        exit 1
    fi
    full_path="${WALL_DIR}/${cleaned}"
    nohup /home/uthman/.local/bin/set-wallpaper "$full_path" >/dev/null 2>&1 &
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
else
    pairs=()
    for f in "$WALL_DIR"/*.jpg "$WALL_DIR"/*.png "$WALL_DIR"/*.jpeg; do
        [[ -e "$f" ]] || continue
        base=$(basename "$f")
        name_part="${base%.*}"
        pretty=$(echo "$name_part" | tr '_-' '  ' | sed -e "s/\b\(.\)/\u\1/g" -e 's/ ([0-9]\+)$//')
        pairs+=("$pretty" "$base")

        thumb="${THUMB_DIR}/${base}.png"
        if [[ ! -e "$thumb" || "$f" -nt "$thumb" ]]; then
            magick "$f" -resize 300x300^ -gravity center -extent 300x300 \
                \( -size 300x300 xc:none -draw 'roundrectangle 0,0,299,299,30,30' \) \
                -alpha off -compose CopyOpacity -composite \
                -strip "$thumb" 2>/dev/null
        fi

        icon_path="$thumb"
        [[ -e "$icon_path" ]] || icon_path="$f"

        printf '%s\0icon\x1f%s\n' "$pretty" "$icon_path"
    done

    jq -n '
        def pairs2obj(a): reduce range(0; a|length; 2) as $i ({}; . + {(a[$i]): a[$i+1]});
        pairs2obj($ARGS.positional)
    ' --args "${pairs[@]}" > "$LOOKUP_FILE"

    rofi -show wallpaper -modes "wallpaper:$SCRIPT_PATH" -p '🖼  Wallpaper' -show-icons \
        -theme /home/uthman/.config/rofi/wallpaper.rasi \
        -theme-str 'entry { enabled: false; }'
fi
