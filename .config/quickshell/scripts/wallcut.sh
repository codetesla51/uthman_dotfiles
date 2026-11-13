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
#
# Env: JOBS=2 MODEL=u2netp OUTDIR=... WALLDIR=...
#
# rembg's default model is ~900 MB. This pins u2netp (~4.5 MB) on purpose.
# If rembg is not on PATH, a venv at ~/.local/share/wallcut/venv is used.

set -uo pipefail

WALLDIR="${WALLDIR:-$HOME/dotfiles/wallpapers}"
OUTDIR="${OUTDIR:-$HOME/.cache/wallcut}"
MODEL="${MODEL:-u2netp}"
JOBS="${JOBS:-2}"
FORCE=0

for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
        *)          WALLDIR="$arg" ;;
    esac
done

if [[ -n "${REMBG:-}" && -x "$REMBG" ]]; then
    :
elif command -v rembg >/dev/null 2>&1; then
    REMBG="$(command -v rembg)"
elif [[ -x "$HOME/.local/share/wallcut/venv/bin/rembg" ]]; then
    REMBG="$HOME/.local/share/wallcut/venv/bin/rembg"
else
    cat >&2 <<'EOF'
rembg not found. Install it once:

  python3 -m venv ~/.local/share/wallcut/venv
  ~/.local/share/wallcut/venv/bin/pip install 'rembg[cpu,cli]'

Then rerun this script.
EOF
    exit 1
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

    if [[ "$FORCE" -eq 0 && -f "$png" && -f "$blur" && -f "$meta" ]]; then
        echo "skip $name"
        return 0
    fi

    echo "cut  $name"
    local tmp_png="$OUTDIR/.$name.tmp.png" cut="$png"
    if [[ ! -f "$png" || "$FORCE" -eq 1 ]]; then
        if ! "$REMBG" i -m "$MODEL" "$src" "$tmp_png" >/dev/null 2>&1; then
            rm -f "$tmp_png"
            echo "FAIL $name"
            return 1
        fi
        cut="$tmp_png"
    fi

    if ! python3 - "$src" "$cut" "$meta" "$blur" <<'PY'
import json, os, sys
from PIL import Image, ImageFilter, ImageEnhance

src, cut, meta, blur = sys.argv[1:5]

# Sidecar: bbox for the fallback guard, and a coarse alpha grid (32x18) for
# true coverage of the clock area. Grid values are mean alpha per cell, 0..1.
GW, GH = 32, 18
im = Image.open(cut)
alpha = im.getchannel("A")
bbox = alpha.getbbox()
w, h = im.size
small = alpha.resize((GW, GH), Image.BILINEAR)
grid = [round(v / 255.0, 3) for v in small.getdata()]
sidecar = {"v": 2, "gw": GW, "gh": GH, "grid": grid}
if bbox:
    sidecar["bbox"] = [bbox[0] / w, bbox[1] / h, bbox[2] / w, bbox[3] / h]
else:
    sidecar["bbox"] = None

# Write sidecar and blur to temp names, then rename: the clock watcher must
# never parse a half-written JSON or load a half-written JPEG.
tmp_meta = meta + ".tmp"
with open(tmp_meta, "w") as f:
    json.dump(sidecar, f)
os.replace(tmp_meta, meta)

wall = Image.open(src).convert("RGB")
if wall.width > 1920:
    wall = wall.resize((1920, round(wall.height * 1920 / wall.width)))
blurred = wall.filter(ImageFilter.GaussianBlur(max(8, wall.width // 90)))
blurred = ImageEnhance.Brightness(blurred).enhance(1.35)
tmp_blur = blur + ".tmp.jpg"
blurred.save(tmp_blur, quality=88)
os.replace(tmp_blur, blur)
PY
    then
        rm -f "$tmp_png"
        echo "FAIL $name"
        return 1
    fi

    # Rename the PNG last: its appearance is what tells the clock that the
    # cutout, sidecar, and blur are all complete.
    if [[ "$cut" == "$tmp_png" ]]; then
        mv -f "$tmp_png" "$png"
    fi
    echo "ok   $name"
}

export -f gen
export OUTDIR MODEL FORCE REMBG

count=0
while IFS= read -r -d '' file; do
    gen "$file" &
    count=$((count + 1))
    if (( count % JOBS == 0 )); then wait; fi
# -L: the wallpaper picker leaves symlinks into ~/.cache/wallshelf here, and a
# plain -type f silently skips those.
done < <(find -L "$WALLDIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0)

wait
echo "done — $count wallpapers checked, assets in $OUTDIR"
