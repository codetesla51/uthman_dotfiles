#!/usr/bin/env bash
# wallcut.sh — generate desktop-clock assets for every wallpaper.
#
# For each image in WALLDIR it writes, into OUTDIR (~/.cache/wallcut):
#   <name>.png        transparent subject cutout (rembg)
#   <name>.json       {"bbox":[x0,y0,x1,y1]} normalized, used for the readability guard
#   <name>-blur.jpg   pre-blurred copy, used as the clock's frost texture
#
# Usage:
#   wallcut.sh                 all wallpapers, skip ones already done
#   wallcut.sh --force         regenerate everything
#   wallcut.sh ~/some/dir      different wallpaper directory
#   wallcut.sh -f ~/wall.jpg   one wallpaper, re-cut it
#
# Env: JOBS=2 MODEL=u2netp OUTDIR=... WALLDIR=...
#
# rembg's default model is ~900 MB. This pins u2netp (~4.5 MB) on purpose.
# If rembg is not on PATH, a venv at ~/.local/share/wallcut/venv is used.
# Without rembg the script still writes the blur and a zero sidecar — the
# clock keeps its glass, it just has no subject cutout.

set -uo pipefail

WALLDIR="${WALLDIR:-$HOME/dotfiles/wallpapers}"
OUTDIR="${OUTDIR:-$HOME/.cache/wallcut}"
MODEL="${MODEL:-u2netp}"
JOBS="${JOBS:-2}"
FORCE=0
ONEFILE=""

for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *)          if [[ -f "$arg" ]]; then ONEFILE="$arg"; else WALLDIR="$arg"; fi ;;
    esac
done

# rembg is optional: without it the script still writes the blur, which is
# what keeps the clock from ever falling back to a flat fill.
if [[ -n "${REMBG:-}" && -x "$REMBG" ]]; then
    :
elif command -v rembg >/dev/null 2>&1; then
    REMBG="$(command -v rembg)"
elif [[ -x "$HOME/.local/share/wallcut/venv/bin/rembg" ]]; then
    REMBG="$HOME/.local/share/wallcut/venv/bin/rembg"
else
    REMBG=""
    echo "rembg not found — writing blurs only, no subject cutouts" >&2
fi

command -v python3 >/dev/null 2>&1 || { echo "python3 with Pillow is required" >&2; exit 1; }
mkdir -p "$OUTDIR"

gen() {
    local src="$1" name png meta blur
    src="$(realpath "$src")"
    name="$(basename "${src%.*}")"
    png="$OUTDIR/$name.png"
    meta="$OUTDIR/$name.json"
    blur="$OUTDIR/$name-blur.jpg"

    if [[ "$FORCE" -eq 0 && -f "$blur" && -f "$meta" ]]; then
        echo "skip $name"
        return 0
    fi

    echo "cut  $name"
    local srcimg="$src" tmp_png="" cut="$png"
    if [[ "${src,,}" == *.gif ]]; then
        srcimg="$OUTDIR/.$name.src.png"
        if ! python3 - "$src" "$srcimg" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
im.seek(0)
im.convert("RGBA").save(sys.argv[2])
PY
        then
            echo "FAIL $name"
            return 1
        fi
    fi

    # The blur lands before rembg runs, so a wallpaper with no detectable
    # subject (GIFs, abstract art) still gets clock glass instead of a flat
    # fallback.
    if ! python3 - "$srcimg" "$blur" <<'PY'
import os, sys
from PIL import Image, ImageFilter, ImageEnhance

src, blur = sys.argv[1:3]
wall = Image.open(src).convert("RGB")
if wall.width > 1920:
    wall = wall.resize((1920, round(wall.height * 1920 / wall.width)))
blurred = wall.filter(ImageFilter.GaussianBlur(max(8, wall.width // 90)))
blurred = ImageEnhance.Brightness(blurred).enhance(1.35)
tmp = blur + ".tmp.jpg"
blurred.save(tmp, quality=88)
os.replace(tmp, blur)
PY
    then
        [[ "$srcimg" != "$src" ]] && rm -f "$srcimg"
        echo "FAIL $name"
        return 1
    fi

    if [[ ! -f "$png" || ( "$FORCE" -eq 1 && -n "$REMBG" ) ]]; then
        tmp_png="$OUTDIR/.$name.tmp.png"
        if [[ -n "$REMBG" ]] && "$REMBG" i -m "$MODEL" "$srcimg" "$tmp_png" >/dev/null 2>&1; then
            cut="$tmp_png"
        else
            rm -f "$tmp_png"
            tmp_png=""
            # No subject: write a zero grid so the clock stays centered and
            # this wallpaper is not retried on every run.
            python3 - "$meta" <<'PY'
import json, os, sys
meta = sys.argv[1]
tmp = meta + ".tmp"
with open(tmp, "w") as f:
    json.dump({"v": 2, "gw": 32, "gh": 18, "grid": [0.0] * 576, "bbox": None}, f)
os.replace(tmp, meta)
PY
            [[ "$srcimg" != "$src" ]] && rm -f "$srcimg"
            echo "ok   $name (no cutout)"
            return 0
        fi
    fi

    if ! python3 - "$cut" "$meta" <<'PY'
import json, os, sys
from PIL import Image

# Sidecar: bbox for the fallback guard, and a coarse alpha grid (32x18) for
# true coverage of the clock area. Grid values are mean alpha per cell, 0..1.
GW, GH = 32, 18
cut, meta = sys.argv[1:3]
im = Image.open(cut)
alpha = im.getchannel("A")
bbox = alpha.getbbox()
w, h = im.size
small = alpha.resize((GW, GH), Image.BILINEAR)
grid = [round(v / 255.0, 3) for v in small.getdata()]
sidecar = {"v": 2, "gw": GW, "gh": GH, "grid": grid}
sidecar["bbox"] = [bbox[0] / w, bbox[1] / h, bbox[2] / w, bbox[3] / h] if bbox else None

# Write to a temp name, then rename: the clock watcher must never parse a
# half-written JSON.
tmp = meta + ".tmp"
with open(tmp, "w") as f:
    json.dump(sidecar, f)
os.replace(tmp, meta)
PY
    then
        [[ -n "$tmp_png" ]] && rm -f "$tmp_png"
        [[ "$srcimg" != "$src" ]] && rm -f "$srcimg"
        echo "FAIL $name"
        return 1
    fi

    # Rename the PNG last: its appearance is what tells the clock that the
    # cutout, sidecar, and blur are all complete.
    if [[ "$cut" == "$tmp_png" ]]; then
        mv -f "$tmp_png" "$png"
    fi
    [[ "$srcimg" != "$src" ]] && rm -f "$srcimg"
    echo "ok   $name"
}

export -f gen
export OUTDIR MODEL FORCE REMBG

if [[ -n "$ONEFILE" ]]; then
    if gen "$ONEFILE"; then
        echo "done — $(basename "$ONEFILE")"
        exit 0
    fi
    exit 1
fi

count=0
while IFS= read -r -d '' file; do
    gen "$file" &
    count=$((count + 1))
    if (( count % JOBS == 0 )); then wait; fi
# -L: the wallpaper picker leaves symlinks into ~/.cache/wallshelf here, and a
# plain -type f silently skips those.
done < <(find -L "$WALLDIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) -print0)

wait
echo "done — $count wallpapers checked, assets in $OUTDIR"
