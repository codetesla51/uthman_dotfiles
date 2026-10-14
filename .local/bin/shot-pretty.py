#!/usr/bin/env python3
"""shot-pretty: composite a window shot onto blurred wallpaper, mac-style.

Usage: shot-pretty.py <window.png> <wallpaper> <output.png>

The shadow is the fiddly part. A small-radius rounded rect blurred hard
(e.g. radius 22, blur 45) fills its own corners in and degrades into a hard
rectangle around the window. So the shadow silhouette is drawn with a corner
radius that scales with the blur distance, which keeps the corners round.
"""
import sys
from PIL import Image, ImageFilter, ImageDraw, ImageEnhance

BORDER_CROP = 1     # strips Hyprland's 1px window border (border_size = 1).
                    # 4px total out of ~1900 - invisible loss, kills the frame.
PAD = 96            # smaller pad = window fills more of the frame. This is
                    # how you get a "zoomed in" look WITHOUT cropping content.
ZOOM = 1.06         # magnify the window (canvas grows to match, no cropping).
                    # 1.0 = as captured. 1.15 = noticeably close up.
RADIUS = 12         # must match Hyprland decoration rounding * monitor scale
FEATHER = 1.5       # mask edge softening (melts the baked AA fringe)

SHADOW_BLUR = 34    # softness
SHADOW_ALPHA = 105  # 0-255, was 200 - far too heavy
SHADOW_OFFSET_Y = 14
SHADOW_LIFT = 3     # dark contact shadow hugging the window

WALL_BLUR = 14      # light touch - wallpaper should still read as a wallpaper
WALL_DARKEN = 0.28  # keep enough brightness to see the image
WALL_SATURATE = 1.15
VIGNETTE = 0.22     # corner falloff so the window sits forward
GLASS_TINT = (18, 16, 24, 26)  # faint cool cast, like macOS window glass
GLASS_BLUR = 3


def rounded_mask(size, radius, feather):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255
    )
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    return mask


def soft_shadow(win_w, win_h, radius):
    """Return (mask, inset) for a shadow sized to the window.

    inset is how far the mask extends past the window's top-left, so the
    caller can paste it at PAD - inset.
    """
    reach = SHADOW_BLUR * 3  # room for the blur to fall off
    w, h = win_w + reach * 2, win_h + reach * 2
    # Radius must be large relative to the blur or the blur squares off the
    # corners. Growing it by the blur radius keeps the silhouette round.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [reach, reach, w - reach, h - reach],
        radius=radius + SHADOW_BLUR,
        fill=SHADOW_ALPHA,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))
    return mask, reach


def contact_shadow(win_w, win_h, radius):
    """Tight dark edge right under the window - the bit that reads as depth."""
    reach = 14
    mask = Image.new("L", (win_w + reach * 2, win_h + reach * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [reach, reach, win_w + reach, win_h + reach],
        radius=radius + 6,
        fill=70,
    )
    mask = mask.filter(ImageFilter.GaussianBlur(9))
    return mask, reach


def stamp_shadow(bg, mask, x, y):
    """Alpha-stamp a black shadow mask onto bg at (x, y), clipped to bounds."""
    cw, ch = bg.size
    mw, mh = mask.size
    left = max(0, -x)
    top = max(0, -y)
    right = min(mw, cw - x)
    bottom = min(mh, ch - y)
    if right <= left or bottom <= top:
        return bg
    layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    layer.paste((0, 0, 0, 255), (x, y),
                mask.crop((left, top, right, bottom)))
    return Image.alpha_composite(bg, layer)


def cover(img, w, h):
    s = max(w / img.width, h / img.height)
    img = img.resize((max(w, int(img.width * s) + 1), max(h, int(img.height * s) + 1)),
                     Image.LANCZOS)
    x = (img.width - w) // 2
    y = (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def magnify(img, factor):
    """Scale the window up like display zoom. Canvas is sized from the result,
    so the whole window stays in frame - nothing is cropped.

    Centre-cropping would be the other way to 'zoom', but it deletes pixels off
    every edge and hides real UI. This doesn't.
    """
    if factor <= 1:
        return img
    w, h = img.size
    return img.resize((int(w * factor), int(h * factor)), Image.LANCZOS)


def vignette(img, strength):
    """Radial corner falloff - pushes the window visually forward."""
    w, h = img.size
    small = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(small)
    d.ellipse([-w * 0.30, -h * 0.30, w * 1.30, h * 1.30], fill=255)
    small = small.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    out = Image.composite(img, Image.blend(img, dark, strength), small)
    return out


def edge_highlight(win, radius):
    """Crisp light stroke on the window silhouette - the macOS 'glass' edge.

    One outline on the boundary only. An earlier version also drew a second
    rect across the top, which rendered as a stray horizontal line under the
    titlebar.
    """
    w, h = win.size
    stroke = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(stroke).rounded_rectangle(
        [1, 1, w - 2, h - 2], radius=radius,
        outline=(255, 255, 255, 55), width=2,
    )
    return stroke


def main(win_path, wall_path, out_path):
    win = Image.open(win_path).convert("RGBA")
    if BORDER_CROP:
        b = BORDER_CROP
        win = win.crop((b, b, win.width - b, win.height - b))
    win = magnify(win, ZOOM)
    # Corners must scale with the window, or the rounding won't match the
    # compositor's after magnification.
    radius = int(round(RADIUS * ZOOM))
    win.putalpha(rounded_mask(win.size, radius, FEATHER))

    cw, ch = win.width + PAD * 2, win.height + PAD * 2

    bg = cover(Image.open(wall_path).convert("RGB"), cw, ch)
    bg = bg.filter(ImageFilter.GaussianBlur(WALL_BLUR))
    bg = ImageEnhance.Color(bg).enhance(WALL_SATURATE)
    bg = Image.blend(bg, Image.new("RGB", bg.size, (0, 0, 0)), WALL_DARKEN)
    bg = vignette(bg, VIGNETTE).convert("RGBA")

    for mask, inset in (soft_shadow(win.width, win.height, radius),
                        contact_shadow(win.width, win.height, radius)):
        bg = stamp_shadow(bg, mask, PAD - inset, PAD - inset + SHADOW_OFFSET_Y)

    # faint glass cast over the window body
    tint = Image.new("RGBA", win.size, GLASS_TINT)
    win = Image.alpha_composite(win, tint)
    win = Image.alpha_composite(win, edge_highlight(win, radius))

    bg.alpha_composite(win, (PAD, PAD))
    bg.save(out_path, "PNG")
    print(out_path)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])