#!/usr/bin/env python3
"""
PixelBot TUI — the same bot, in a terminal.

    pixelbot                 # or: ~/.config/quickshell/scripts/pixelbot-tui.py
    pixelbot --scale 2       # force a bigger bot if the terminal is tall
    pixelbot --no-sound
    pixelbot ask "how is my machine doing?"

The bot watches the same things the bar module does: CPU, battery/AC, music,
muted audio, screen recording, and idle. When the bar is running it reads the
bar bot's live state over IPC, so both stay in sync (including system-wide idle
and browser audio that has no MPRIS player). Without the bar it falls back to
local probes and its own idle timer. Click it to wave, drag it around, or use
the keys below. Sounds are only for alerts, errors, low battery, recording,
happy/hello — ambient moods stay quiet.

Press `i` in the TUI to ask the bot something. Dahl AI answers using the live
machine context. The key is read from DAHL_API_KEY, DAHL_API_KEY_FILE, or
~/.config/pixelbot/dahl.key (chmod 600). Override the model with DAHL_MODEL.

    space  wave            m  cycle moods       a  automatic
    i      ask AI          e  error demo        s  sound on/off
    r      recenter        +/-  size            q  quit

Mouse: click inside the bot to wave, drag it anywhere, wheel to resize.
Sound files are shared with the bar module (assets/pixelbot/*.wav).
"""

import glob
import json
import math
import os
import re
import select
import shutil
import signal
import subprocess
import sys
import termios
import textwrap
import threading
import time
import tty
import urllib.error
import urllib.request

HOME = os.path.expanduser("~")
CONFIG = os.path.join(HOME, ".config/quickshell")
COLORS_CSS = os.path.join(CONFIG, "colors.css")
SOUND_DIR = os.path.join(CONFIG, "assets", "pixelbot")
RECORDERS = "meetcap|wf-recorder|wl-screenrec|obs|gpu-screen-recorder"
AI_KEY_FILE = os.environ.get(
    "DAHL_API_KEY_FILE",
    os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")),
                 "pixelbot", "dahl.key"),
)
AI_URL = os.environ.get("DAHL_BASE_URL", "https://inference.dahl.global/v1").rstrip("/") \
    + "/chat/completions"
AI_MODEL = os.environ.get("DAHL_MODEL", "zai-org/GLM-5.3-Flash")
AI_MODELS = [m.strip() for m in os.environ.get("DAHL_MODELS", "").split(",") if m.strip()]
if not AI_MODELS:
    AI_MODELS = [AI_MODEL, "deepseek-ai/DeepSeek-V4-Flash-0731", "MiniMaxAI/MiniMax-M2.7"]
AI_SYSTEM = (
    "You are a concise terminal assistant. Answer the user's question directly. "
    "Use at most two short sentences. Do not roleplay, do not invent data, "
    "do not repeat the question, and do not add a status report unless asked. "
    "The only machine data you know is this live context: {context}"
)


MOODS = [
    "idle", "sleepy", "hello", "muted", "music", "charging",
    "busy", "recording", "lowbat", "happy", "alert", "error",
]
# Ambient moods are visible but silent: no idle/music/muted/busy chirping.
AUDIBLE_MOODS = {"alert", "error", "lowbat", "recording", "happy", "hello"}
MOOD_LINE = {
    "idle": "standing by",
    "sleepy": "zzz — nobody has touched me in a while",
    "hello": "hey!",
    "muted": "audio is muted",
    "music": "moving to the beat",
    "charging": "charging — {bat}%",
    "busy": "working hard — cpu {cpu}%",
    "recording": "screen recording is running",
    "lowbat": "battery low — {bat}%",
    "happy": "nice one",
    "alert": "something wants your attention",
    "error": "something failed — press e / a to clear",
}

DEFAULT_COLORS = {
    "background": "#17130f",
    "foreground": "#ebe1da",
    "primary": "#f3bc87",
    "secondary": "#dfc1a8",
    "tertiary": "#9bcee3",
    "error": "#ffb4ab",
    "surface": "#17130f",
    "on_surface": "#efe5df",
    "surface_variant": "#50453b",
    "outline": "#a39487",
}

RESET = "\x1b[0m"
CURSOR_OFF = "\x1b[?25l"
CURSOR_ON = "\x1b[?25h"
ALT_ON = "\x1b[?1049h"
ALT_OFF = "\x1b[?1049l"
MOUSE_ON = "\x1b[?1000h\x1b[?1003h\x1b[?1006h"
MOUSE_OFF = "\x1b[?1006l\x1b[?1003l\x1b[?1000l"
WRAP_OFF = "\x1b[?7l"
WRAP_ON = "\x1b[?7h"
SYNC_ON = "\x1b[?2026h"
SYNC_OFF = "\x1b[?2026l"


SPRITE_W = 16
SPRITE_H = 18
PIXEL_COLORS = {
    "H": "#b9c3d8", "T": "#9aa6bf", "A2": "#aab4c8", "L": "#8793ad",
    "cy": "#5ad1ff", "am": "#f9a15b", "rd": "#f38ba8", "gn": "#a6e3a1",
    "dm": "#5b6478", "ye": "#f9e2af", "bl": "#89dceb", "pu": "#b4a1ff",
}


def hex_rgb(value):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def mix_hex(color, factor):
    factor = max(-0.6, min(0.6, factor))
    n = int(color.lstrip("#"), 16)
    target = 255 if factor > 0 else 0
    amount = abs(factor)
    r = round(((n >> 16) & 255) + (target - ((n >> 16) & 255)) * amount)
    g = round(((n >> 8) & 255) + (target - ((n >> 8) & 255)) * amount)
    b = round((n & 255) + (target - (n & 255)) * amount)
    return f"#{r:02x}{g:02x}{b:02x}"


def blend(fg, bg, alpha):
    return tuple(round(f * alpha + b * (1.0 - alpha)) for f, b in zip(fg, bg))


class Palette:
    def __init__(self):
        self.raw = dict(DEFAULT_COLORS)
        self.mtime = 0
        self.refresh(force=True)

    def refresh(self, force=False):
        try:
            mtime = os.path.getmtime(COLORS_CSS)
        except OSError:
            mtime = 0
        if not force and mtime == self.mtime:
            return
        self.mtime = mtime
        try:
            with open(COLORS_CSS, "r", encoding="utf-8") as fh:
                text = fh.read()
            found = dict(DEFAULT_COLORS)
            for m in re.finditer(r"@define-color\s+(\w+)\s+#([0-9a-fA-F]{6})\s*;", text):
                found[m.group(1).lower()] = "#" + m.group(2)
            self.raw = found
        except OSError:
            self.raw = dict(DEFAULT_COLORS)

        raw = self.raw
        bg = hex_rgb(raw["background"])
        fg = hex_rgb(raw["foreground"])
        self.rgb = {
            "B": blend(fg, bg, 0.78),
            "S": bg,
            "V": blend(hex_rgb(raw["surface_variant"]), bg, 0.72),
            "A": hex_rgb(raw["primary"]),
            "O": hex_rgb(raw["secondary"]),
            "R": hex_rgb(raw["error"]),
            "G": hex_rgb(raw["tertiary"]),
            "D": hex_rgb(raw["outline"]),
            "Y": hex_rgb(raw["secondary"]),
            "T": hex_rgb(raw["tertiary"]),
            "BG": bg,
            "FG": fg,
            "DIM": blend(hex_rgb(raw["outline"]), bg, 0.58),
            "MUTED": blend(hex_rgb(raw["outline"]), bg, 0.40),
        }
        self.bg_seq = self.bg("BG")

    def bg(self, role):
        r, g, b = self.rgb[role]
        return f"\x1b[48;2;{r};{g};{b}m"

    def bg_hex(self, color):
        r, g, b = hex_rgb(color)
        return f"\x1b[48;2;{r};{g};{b}m"

    def fg(self, role, bold=False):
        r, g, b = self.rgb[role]
        return f"\x1b[{'1;' if bold else ''}38;2;{r};{g};{b}m"

    def color_for_mood(self, mood):
        if mood == "error":
            return "R"
        if mood == "alert":
            return "O"
        if mood in ("idle", "sleepy", "muted"):
            return "D"
        return "A"


def draw_sprite(mood, frame, gaze=None):
    """Return a 16x18 matrix of shaded hex colors (None = transparent).

    This is the terminal port of the Canvas sprite in PixelBot.qml: same
    proportions, face plate, edge shading and mood animations.
    """
    pal = PIXEL_COLORS

    def open_eyes(c, look):
        return [(5 + look, 6, 2, 2, c), (9 + look, 6, 2, 2, c)]

    def blink(c):
        return [(5, 7, 2, 1, c), (9, 7, 2, 1, c)]

    def hap(c):
        return [(5, 7, 1, 1, c), (6, 6, 1, 1, c), (7, 7, 1, 1, c),
                (9, 7, 1, 1, c), (10, 6, 1, 1, c), (11, 7, 1, 1, c)]

    def wide(c):
        return [(5, 5, 2, 3, c), (9, 5, 2, 3, c)]

    def low(c):
        return [(5, 7, 2, 2, c), (9, 7, 2, 2, c)]

    def x_eyes(c):
        out = []
        for x in (5, 9):
            for ax, ay in ((0, 0), (2, 0), (1, 1), (0, 2), (2, 2)):
                out.append((x + ax, 5 + ay, 1, 1, c))
        return out

    def heart(c):
        out = []
        for x in (5, 9):
            out.extend([(x, 5, 1, 1, c), (x + 2, 5, 1, 1, c),
                        (x, 6, 3, 1, c), (x + 1, 7, 1, 1, c)])
        return out

    flat = lambda c: [(7, 9, 2, 1, c)]
    smile = lambda c: [(6, 8, 1, 1, c), (7, 9, 2, 1, c), (9, 8, 1, 1, c)]
    mouth_o = lambda c: [(7, 8, 2, 2, c)]
    frown = lambda c: [(6, 9, 1, 1, c), (7, 8, 2, 1, c), (9, 9, 1, 1, c)]
    zig = lambda c: [(6, 9, 1, 1, c), (7, 8, 1, 1, c),
                     (8, 9, 1, 1, c), (9, 8, 1, 1, c)]

    def qgaze(f):
        k = f % 52
        if (20 <= k < 22) or (40 <= k < 42):
            return 'b'
        if 28 <= k < 36:
            return -1
        return 1 if k >= 44 else 0

    g = gaze if gaze is not None else qgaze(frame)
    eyes = lambda c: blink(c) if g == 'b' else open_eyes(c, g)
    k = frame & 7
    m = 'dance' if mood == 'music' else mood
    if m not in ('walk', 'dance', 'happy', 'hello', 'alert', 'busy',
                 'recording', 'lowbat', 'charging', 'error', 'muted',
                 'offline', 'focus', 'sleepy'):
        m = 'idle'

    P = {'tip': pal['cy'], 'la': 0, 'ra': 0, 'll': 0, 'rl': 0,
         'ox': 0, 'oy': 0, 'dim': False, 'hp': False, 'ov': [], 'ex': []}

    if m == 'walk':
        s = (frame >> 1) & 1
        P['ll'] = s
        P['rl'] = 1 - s
        P['la'] = s
        P['ra'] = 1 - s
        P['ov'] = open_eyes(pal['cy'], 1) + flat(pal['cy'])
    elif m == 'dance':
        A = [(2, 2), (1, 1), (2, 0), (1, 1), (0, 2), (1, 1), (2, 2), (0, 0)][k]
        P['la'], P['ra'] = A
        P['ll'] = 1 if k in (2, 3) else 0
        P['rl'] = 1 if k in (6, 7) else 0
        P['ox'] = (0, -1, -1, 0, 0, 1, 1, 0)[k]
        P['oy'] = -1 if (k & 1) else 0
        P['tip'] = (pal['cy'], pal['pu'], pal['rd'], pal['ye'])[(frame >> 1) & 3]
        P['ov'] = hap(pal['cy']) + smile(pal['cy'])
        P['ex'] = ([(15, 0, 1, 3, pal['ye']), (14, 2, 1, 1, pal['ye'])]
                   if frame % 6 < 3 else
                   [(1, 0, 1, 3, pal['ye']), (0, 2, 1, 1, pal['ye'])])
    elif m == 'happy':
        J = (0, -1, -2, -2, -1, 0, 0, 0)[k]
        cols = (pal['rd'], pal['ye'], pal['gn'], pal['cy'], pal['pu'], pal['am'])
        P['oy'] = J
        P['la'] = P['ra'] = 2 if J < 0 else 0
        P['ll'] = P['rl'] = 1 if J < 0 else 0
        P['tip'] = pal['ye']
        P['ov'] = hap(pal['cy']) + smile(pal['cy'])
        for i in range(6):
            P['ex'].append(((i * 5 + frame * 3) % 16,
                            (frame * 2 + i * 3) % 4, 1, 1, cols[i]))
    elif m == 'hello':
        P['ra'] = 2 if frame & 1 else 1
        P['ov'] = hap(pal['cy']) + smile(pal['cy'])
    elif m == 'alert':
        P['ox'] = (0, 1, 0, -1)[frame & 3]
        P['la'] = P['ra'] = 2
        P['tip'] = pal['am']
        P['ov'] = wide(pal['am']) + mouth_o(pal['am'])
        if frame & 1:
            P['ex'] = [(0, 2, 1, 1, pal['ye']), (15, 2, 1, 1, pal['ye']),
                       (0, 4, 1, 1, pal['ye']), (15, 4, 1, 1, pal['ye'])]
    elif m == 'busy':
        P['tip'] = pal['am'] if (frame >> 1) & 1 else pal['cy']
        P['la'] = frame & 1
        P['ra'] = 1 - P['la']
        P['ov'] = open_eyes(pal['cy'], -1 if (frame >> 2) & 1 else 1) + [
            (4, 9, 8, 1, '#262b38'), (4 + frame % 6, 9, 3, 1, pal['cy'])]
    elif m == 'recording':
        P['tip'] = pal['rd']
        P['ov'] = eyes(pal['cy']) + flat(pal['cy'])
        if (frame >> 2) & 1:
            P['ov'].append((11, 5, 2, 1, pal['rd']))
    elif m == 'lowbat':
        P['oy'] = 1
        P['tip'] = pal['rd'] if (frame >> 3) & 1 else pal['dm']
        P['ov'] = low(pal['am']) + frown(pal['am'])
        if frame % 6 < 4:
            P['ov'].append((5, 9, 1, 1, pal['bl']))
    elif m == 'charging':
        P['tip'] = pal['gn'] if (frame >> 1) & 1 else pal['cy']
        P['ov'] = (hap(pal['gn']) if (frame >> 2) & 1 else heart(pal['rd']))             + smile(pal['gn'])
        if (frame >> 1) & 1:
            P['ov'].extend([(8, 11, 1, 1, pal['ye']),
                            (7, 12, 2, 1, pal['ye']),
                            (7, 13, 1, 1, pal['ye'])])
    elif m == 'error':
        P['tip'] = pal['rd']
        P['ox'] = 1 if frame % 14 < 2 else 0
        P['la'] = P['ra'] = 2
        P['ov'] = x_eyes(pal['rd']) + zig(pal['rd'])
    elif m == 'muted':
        P['tip'] = pal['dm']
        P['ov'] = eyes(pal['cy']) + [
            (5, 9, 6, 1, pal['dm']), (7, 9, 1, 1, '#0e1015'),
            (9, 9, 1, 1, '#0e1015')]
    elif m == 'offline':
        P['tip'] = pal['dm']
        P['la'] = P['ra'] = 1
        P['ov'] = open_eyes(pal['cy'], -1 if (frame >> 1) & 1 else 1)             + zig(pal['am'])
        P['ex'] = ([(10, 1, 1, 1, pal['ye']), (6, 0, 1, 1, pal['ye'])]
                   if frame & 1 else
                   [(6, 1, 1, 1, pal['ye']), (10, 0, 1, 1, pal['ye'])])
    elif m == 'focus':
        P['tip'] = pal['pu']
        P['hp'] = True
        P['oy'] = (frame >> 3) & 1
        P['ov'] = blink(pal['cy']) + flat(pal['cy'])
    elif m == 'sleepy':
        P['dim'] = True
        P['oy'] = (frame >> 3) & 1
        P['ov'] = blink(pal['dm'])
        z = (frame >> 3) % 3
        if z == 1:
            P['ex'] = [(13, 2, 1, 1, pal['A2'])]
        elif z == 2:
            P['ex'] = [(12, 0, 3, 1, pal['A2']), (13, 1, 1, 1, pal['A2']),
                       (12, 2, 3, 1, pal['A2'])]
    else:
        P['tip'] = mix_hex(pal['cy'], 0.4) if (frame >> 3) & 1 else pal['cy']
        P['ov'] = eyes(pal['cy']) + flat(pal['cy'])

    grid = [[None] * SPRITE_W for _ in range(SPRITE_H)]
    ids = [[None] * SPRITE_W for _ in range(SPRITE_H)]

    def put(x, y, w, h, c, ident=None):
        for yy in range(max(0, y), min(SPRITE_H, y + h)):
            for xx in range(max(0, x), min(SPRITE_W, x + w)):
                grid[yy][xx] = c
                ids[yy][xx] = ident

    def arm(side, p):
        if side < 0:
            return ((1, 11), (0, 9), (0, 6))[p]
        return ((13, 11), (14, 9), (14, 6))[p]

    la = arm(-1, P['la'])
    ra = arm(1, P['ra'])
    ly = 13 if P['ll'] else 14
    ry = 13 if P['rl'] else 14
    parts = [
        ('t', 7, 2, 2, 2, P['tip']),
        ('h', 2, 4, 12, 7, pal['H']),
        ('b', 4, 11, 8, 3, pal['T']),
        ('a', la[0], la[1], 2, 3, pal['A2']),
        ('a', ra[0], ra[1], 2, 3, pal['A2']),
        ('l', 4, ly, 2, 3, pal['L']),
        ('l', 10, ry, 2, 3, pal['L']),
    ]
    for ident, x, y, w, h, c in parts:
        put(x, y, w, h, c, ident)

    shaded = [[None] * SPRITE_W for _ in range(SPRITE_H)]
    for y in range(SPRITE_H):
        for x in range(SPRITE_W):
            c = grid[y][x]
            if not c:
                continue
            up = grid[y - 1][x] if y > 0 else None
            left = grid[y][x - 1] if x > 0 else None
            down = grid[y + 1][x] if y < SPRITE_H - 1 else None
            right = grid[y][x + 1] if x < SPRITE_W - 1 else None
            t = 0.14 - 0.32 * (y - 2) / 14
            if not up:
                t += 0.22
            if not left:
                t += 0.10
            if not down:
                t -= 0.22
            if not right:
                t -= 0.14
            if up and ids[y - 1][x] == 'h' and ids[y][x] != 'h':
                t -= 0.16
            if P['dim']:
                t -= 0.38
            shaded[y][x] = mix_hex(c, t)

    out = [[None] * SPRITE_W for _ in range(SPRITE_H)]

    def put_out(x, y, w, h, c):
        for yy in range(max(0, y), min(SPRITE_H, y + h)):
            for xx in range(max(0, x), min(SPRITE_W, x + w)):
                out[yy][xx] = c

    ox, oy = P['ox'], P['oy']
    for y in range(SPRITE_H):
        for x in range(SPRITE_W):
            if shaded[y][x]:
                put_out(x + ox, y + oy, 1, 1, shaded[y][x])

    put_out(ox + 3, oy + 5, 10, 5, '#07080b' if P['dim'] else '#0e1015')
    put_out(ox + 3, oy + 5, 10, 1, '#05060a')
    put_out(ox + 3, oy + 5, 1, 5, '#05060a')
    put_out(ox + 3, oy + 9, 10, 1, '#1b2030')
    put_out(ox + 12, oy + 5, 1, 5, '#1b2030')

    highlight = mix_hex(pal['H'], 0.1 if P['dim'] else 0.55)
    for x, y in ((3, 4), (4, 4), (2, 5)):
        put_out(ox + x, oy + y, 1, 1, highlight)

    if P['hp']:
        a, b, d = '#7c6bd6', '#a496f0', '#574aa8'
        for x, y, w, h in ((0, 6, 3, 4), (13, 6, 3, 4)):
            put_out(ox + x, oy + y, w, h, a)
            put_out(ox + x, oy + y, w, 1, b)
            put_out(ox + x, oy + y + h - 1, w, 1, d)
        put_out(ox + 3, oy + 3, 4, 1, a)
        put_out(ox + 9, oy + 3, 4, 1, a)
        put_out(ox + 2, oy + 4, 1, 2, a)
        put_out(ox + 13, oy + 4, 1, 2, a)

    for x, y, w, h, c in P['ov']:
        put_out(ox + x, oy + y, w, h, c)
    for x, y, w, h, c in P['ex']:
        put_out(x, y, w, h, c)

    return out


class DahlBusy(RuntimeError):
    pass


class AI:
    """Small async wrapper around Dahl's OpenAI-compatible chat endpoint."""

    def __init__(self):
        self.key = self._read_key()
        self.busy = False
        self.answer = ""
        self.error = ""
        self.question = ""
        self.history = []              # last three question/answer pairs
        self.lock = threading.Lock()

    @staticmethod
    def _read_key():
        value = os.environ.get("DAHL_API_KEY", "").strip()
        if value:
            return value
        paths = [AI_KEY_FILE, os.path.join(HOME, ".config", "pixelbot", "dahl.key")]
        seen = set()
        for path in paths:
            if not path or path in seen:
                continue
            seen.add(path)
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    value = fh.read().strip()
                if value:
                    return value
            except OSError:
                continue
        return ""

    @property
    def available(self):
        return bool(self.key)

    def clear(self):
        with self.lock:
            if self.busy:
                return
            self.answer = ""
            self.error = ""
            self.question = ""

    def ask(self, question, context):
        """Start an answer in a background thread; the TUI never blocks."""
        question = " ".join(question.split())
        if not question:
            return
        with self.lock:
            if self.busy:
                return
            if not self.key:
                self.error = "no Dahl key — set DAHL_API_KEY or " + AI_KEY_FILE
                self.answer = ""
                return
            self.busy = True
            self.answer = ""
            self.error = ""
            self.question = question
        threading.Thread(
            target=self._worker, args=(question, context),
            name="pixelbot-ai", daemon=True,
        ).start()

    def ask_sync(self, question, context):
        """For `pixelbot ask`; returns (answer, error)."""
        question = " ".join(question.split())
        if not question:
            return "", "empty question"
        if not self.key:
            return "", "no Dahl key — set DAHL_API_KEY or " + AI_KEY_FILE
        try:
            return self._request(question, context), ""
        except Exception as exc:  # network errors are shown, never crash the TUI
            return "", str(exc)[:240]

    def _worker(self, question, context):
        try:
            answer = self._request(question, context)
        except Exception as exc:
            with self.lock:
                self.busy = False
                self.error = str(exc)[:240]
        else:
            with self.lock:
                self.busy = False
                self.answer = answer

    def _request(self, question, context):
        with self.lock:
            history = list(self.history[-6:])
        messages = [{"role": "system", "content": AI_SYSTEM.format(context=context)}]
        messages.extend(history)
        messages.append({"role": "user", "content": question})

        last_busy = None
        for attempt in range(2):
            for model in AI_MODELS:
                try:
                    content = self._request_once(messages, model)
                except DahlBusy as exc:
                    last_busy = exc
                    time.sleep(0.7 + 0.4 * attempt)
                    continue
                with self.lock:
                    self.history = (self.history + [
                        {"role": "user", "content": question},
                        {"role": "assistant", "content": content},
                    ])[-6:]
                return content
        raise RuntimeError(str(last_busy) if last_busy else "Dahl is busy")

    @staticmethod
    def _clean(content):
        content = content.strip()
        if "</think>" in content:
            content = content.split("</think>", 1)[-1].strip()
        content = content.replace("**", "")
        parts = [p.strip() for p in re.split(r"(?<=[.!?])\s*", content) if p.strip()]
        if len(parts) > 2:
            content = " ".join(parts[:2])
        return content[:4000].rstrip()

    def _request_once(self, messages, model):
        payload = {
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 180,
            "stream": False,
            "stop": ["\n\n"],
        }
        request = urllib.request.Request(
            AI_URL,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": "Bearer " + self.key,
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "pixelbot-tui/1.0",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=75) as response:
                raw = response.read()
        except urllib.error.HTTPError as exc:
            try:
                detail = exc.read().decode("utf-8", "replace")[:180]
            except OSError:
                detail = ""
            if exc.code in (429, 500, 502, 503, 504):
                raise DahlBusy(f"Dahl HTTP {exc.code}: {detail}") from None
            raise RuntimeError(f"Dahl HTTP {exc.code}: {detail}") from None
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Dahl unreachable: {exc.reason}") from None
        except OSError as exc:
            raise RuntimeError(f"Dahl request failed: {exc}") from None

        try:
            data = json.loads(raw.decode("utf-8", "replace"))
        except json.JSONDecodeError:
            raise RuntimeError("Dahl returned invalid JSON") from None
        choices = data.get("choices") or []
        if not choices:
            raise RuntimeError("Dahl returned no choices")
        content = ((choices[0].get("message") or {}).get("content") or "").strip()
        if not content:
            raise RuntimeError("Dahl returned an empty answer")
        return self._clean(content)


class Monitor:
    def __init__(self):
        self.cpu = 0
        self.battery = 100
        self.charging = False
        self.discharging = False
        self.recording = False
        self.music = False
        self.muted = False
        self.ac = False
        self.system_idle = False
        self.shell_ok = False
        self.shell_next = 0.0
        self.busy_latch = False
        self.prev_total = 0
        self.prev_idle = 0
        self.last_poll = 0.0
        self.last_input = time.monotonic()

    def _cpu(self):
        try:
            with open("/proc/stat", "r", encoding="utf-8") as fh:
                fields = [int(v) for v in fh.readline().split()[1:]]
            total = sum(fields)
            idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
            if self.prev_total:
                dt = total - self.prev_total
                di = idle - self.prev_idle
                if dt > 0:
                    self.cpu = max(0, min(100, round(100 * (1 - di / dt))))
            self.prev_total, self.prev_idle = total, idle
        except (OSError, ValueError):
            pass

    def _battery(self):
        paths = sorted(glob.glob("/sys/class/power_supply/BAT*/capacity"))
        if not paths:
            self.battery, self.charging, self.discharging = 100, False, False
            return
        try:
            with open(paths[0], "r", encoding="utf-8") as fh:
                self.battery = int(fh.read().strip())
            status_path = os.path.join(os.path.dirname(paths[0]), "status")
            with open(status_path, "r", encoding="utf-8") as fh:
                status = fh.read().strip()
            self.charging = status == "Charging"
            self.discharging = status == "Discharging"
        except (OSError, ValueError):
            pass

    def _ac(self):
        self.ac = False
        try:
            for path in glob.glob("/sys/class/power_supply/*/online"):
                supply = os.path.dirname(path)
                try:
                    with open(os.path.join(supply, "type"), "r", encoding="utf-8") as fh:
                        if fh.read().strip() != "Mains":
                            continue
                except OSError:
                    continue
                with open(path, "r", encoding="utf-8") as fh:
                    if fh.read().strip() == "1":
                        self.ac = True
                        return
        except OSError:
            pass

    def _recording(self):
        try:
            pattern = r"(^|/)(" + RECORDERS + r")( |$)"
            res = subprocess.run(
                ["pgrep", "-f", pattern],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.0,
            )
            self.recording = res.returncode == 0
        except (OSError, subprocess.SubprocessError):
            self.recording = False

    def _muted(self):
        try:
            res = subprocess.run(
                ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
                capture_output=True, text=True, timeout=1.0,
            )
            self.muted = "[MUTED]" in res.stdout
        except (OSError, subprocess.SubprocessError):
            self.muted = False

    def _music(self):
        self.music = False
        try:
            res = subprocess.run(
                ["playerctl", "-a", "status"],
                capture_output=True, text=True, timeout=1.0,
            )
            if any(line.strip() == "Playing" for line in res.stdout.splitlines()):
                self.music = True
                return
        except (OSError, subprocess.SubprocessError):
            pass

        # Browsers often play audio without publishing MPRIS (Firefox in
        # particular). Fall back to live PipeWire sink inputs; skip our own
        # paplay feedback chirps.
        try:
            res = subprocess.run(
                ["pactl", "list", "sink-inputs"],
                capture_output=True, text=True, timeout=1.0,
            )
            if res.returncode != 0:
                return
            for block in res.stdout.split("Sink Input #")[1:]:
                if "Corked: no" not in block:
                    continue
                app = re.search(r'application\.name = "([^"]*)"', block)
                name = app.group(1).lower() if app else ""
                if name == "paplay":
                    continue
                self.music = True
                return
        except (OSError, subprocess.SubprocessError):
            pass

    def _poll_shell(self, now):
        """Use the bar bot's live state when it is running.

        This is the same data the bar renders, so the TUI gets system-wide idle,
        UPower battery/AC, native MPRIS + PipeWire music, and the actual mute
        state instead of re-deriving them differently.
        """
        if now < self.shell_next:
            return self.shell_ok
        self.shell_next = now + 1.0
        try:
            res = subprocess.run(
                ["quickshell", "-p", CONFIG, "ipc", "call", "bot", "status"],
                capture_output=True, text=True, timeout=1.0,
            )
            if res.returncode != 0:
                raise RuntimeError("shell ipc failed")
            fields = {}
            for token in res.stdout.split():
                if "=" in token:
                    key, value = token.split("=", 1)
                    fields[key] = value
            if "cpu" not in fields or "bat" not in fields or "idle" not in fields:
                raise RuntimeError("shell status incomplete")
            self.cpu = max(0, min(100, int(fields["cpu"])))
            self.battery = max(0, min(100, int(fields["bat"])))
            self.charging = fields.get("charging") == "true"
            if "ac" in fields:
                self.ac = fields.get("ac") == "true"
            else:
                self._ac()
            self.recording = fields.get("recording") == "true"
            self.music = fields.get("music") == "true"
            self.muted = fields.get("muted") == "true"
            self.system_idle = fields.get("idle") == "true"
            self.shell_ok = True
            if self.cpu >= 80:
                self.busy_latch = True
            elif self.cpu <= 65:
                self.busy_latch = False
            return True
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, RuntimeError):
            self.shell_ok = False
            return False

    def poll(self, now):
        if now - self.last_poll < 2.0:
            return
        self.last_poll = now
        if self._poll_shell(now):
            return
        self._cpu()
        self._battery()
        self._ac()
        self._recording()
        self._muted()
        self._music()
        if self.cpu >= 80:
            self.busy_latch = True
        elif self.cpu <= 65:
            self.busy_latch = False

    def touch(self):
        self.last_input = time.monotonic()

    def away(self, now):
        if self.shell_ok:
            # A click/keypress in the TUI is input the shell's IdleMonitor may
            # not have processed yet; trust it for a few seconds.
            if now - self.last_input < 5.0:
                return False
            return self.system_idle
        return now - self.last_input >= 180


class Bot:
    def __init__(self, palette):
        self.palette = palette
        self.monitor = Monitor()
        self.forced = ""
        self.failed = False
        self.ping_until = 0.0
        self.ok_until = 0.0
        self.poke_until = time.monotonic() + 3.0
        self.frame = 0
        self.mood = self.current_mood(time.monotonic())
        self.last_mood = self.mood
        self.boot_at = time.monotonic()
        self.sound_on = True
        self.last_sound = 0.0
        self.origin = None          # (x_chars, y_rows) when dragged
        self.scale_override = None
        self.gaze = None
        self.hover = False
        self.dragging = False
        self.pressed = False
        self.press_at = None
        self.grab = (0, 0)
        self.ai = AI()
        self.ask_mode = False
        self.ask_buf = ""

    def current_mood(self, now):
        m = self.monitor
        if self.forced:
            return self.forced
        if self.failed:
            return "error"
        if now < self.ping_until:
            return "alert"
        if now < self.ok_until:
            return "happy"
        if now < self.poke_until:
            return "hello"
        if m.battery <= 15 and m.discharging:
            return "lowbat"
        if m.recording:
            return "recording"
        if m.busy_latch:
            return "busy"
        if m.charging:
            return "charging"
        if m.music:
            return "music"
        if m.muted:
            return "muted"
        if m.away(now):
            return "sleepy"
        return "idle"

    def play(self, name):
        if not self.sound_on:
            return
        now = time.monotonic()
        if now - self.last_sound < 0.22:
            return
        self.last_sound = now
        path = os.path.join(SOUND_DIR, name + ".wav")
        if not os.path.exists(path):
            return
        try:
            subprocess.Popen(
                ["paplay", path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass

    def update(self, now):
        self.monitor.poll(now)
        mood = self.current_mood(now)
        if mood != self.last_mood:
            self.mood = mood
            self.last_mood = mood
            if now - self.boot_at > 0.7 and mood in AUDIBLE_MOODS:
                self.play(mood)

    def wave(self, now):
        was = self.mood
        self.poke_until = now + 2.0
        if was == "hello":
            self.play("hello")
        self.monitor.touch()

    def cycle_forced(self):
        if not self.forced:
            self.forced = MOODS[0]
        else:
            idx = MOODS.index(self.forced) if self.forced in MOODS else -1
            self.forced = "" if idx == len(MOODS) - 1 else MOODS[idx + 1]
        self.last_mood = ""  # force an announcement on the next update
        self.monitor.touch()

    def phrase(self):
        line = MOOD_LINE.get(self.mood, "")
        return line.format(cpu=self.monitor.cpu, bat=self.monitor.battery)

    def ai_context(self):
        m = self.monitor
        power = "charging" if m.charging else ("discharging" if m.discharging else "on AC")
        return (
            f"{time.strftime('%a %Y-%m-%d %H:%M')}; CPU {m.cpu}%; "
            f"battery {m.battery}% {power}; music={'on' if m.music else 'off'}; "
            f"muted={'yes' if m.muted else 'no'}; recording={'yes' if m.recording else 'no'}; "
            f"user_away={'yes' if m.away(time.monotonic()) else 'no'}; mood={self.mood}."
        )

    def begin_ask(self):
        if self.ai.busy:
            self.ai.error = "still thinking — wait for the answer"
            return
        self.ask_mode = True
        self.ask_buf = ""
        self.ai.clear()
        self.monitor.touch()

    def submit_ask(self):
        question = self.ask_buf.strip()
        self.ask_mode = False
        self.ask_buf = ""
        self.monitor.touch()
        if question:
            self.ai.ask(question, self.ai_context())

    def cancel_ask(self):
        self.ask_mode = False
        self.ask_buf = ""
        self.monitor.touch()


class Screen:
    def __init__(self):
        self.cols, self.rows = shutil.get_terminal_size(fallback=(80, 24))

    def refresh(self):
        self.cols, self.rows = shutil.get_terminal_size(fallback=(80, 24))

    def scale(self, bot):
        fit_w = max(1, (self.cols - 4) // (SPRITE_W * 2))
        fit_h = max(1, (self.rows - 6) // SPRITE_H)
        if bot.scale_override is not None:
            return max(1, min(6, bot.scale_override, fit_w, fit_h))
        return max(1, min(4, fit_w, fit_h))

    def layout(self, bot):
        scale = self.scale(bot)
        w = SPRITE_W * 2 * scale
        h = SPRITE_H * scale
        if bot.origin is None:
            x = max(0, (self.cols - w) // 2)
            y = 3 + max(0, (self.rows - 3 - 3 - h) // 2)
        else:
            x, y = bot.origin
        x = max(0, min(x, max(0, self.cols - w)))
        y = max(3, min(y, max(3, self.rows - 4 - h)))
        return scale, w, h, x, y

    def render(self, bot):
        p = bot.palette
        scale, w, h, ox, oy = self.layout(bot)
        lines = []
        lines.append(self._header(bot))
        lines.append(p.bg_seq + p.fg("DIM") + "─" * self.cols + RESET)

        top_blank = max(0, oy - 2)
        for _ in range(top_blank):
            lines.append(p.bg_seq + "\x1b[K")

        px = draw_sprite(bot.mood, bot.frame, bot.gaze)
        for sy in range(SPRITE_H):
            row = [p.bg_seq, " " * ox]
            current = None
            for sx in range(SPRITE_W):
                color = px[sy][sx]
                if color not in (None, "BG"):
                    seq = p.bg_hex(color)
                else:
                    seq = p.bg("BG")
                if seq != current:
                    row.append(seq)
                    current = seq
                row.append(" " * (2 * scale))
            row.append(p.bg_seq)
            row.append("\x1b[K")
            for _ in range(scale):
                lines.append("".join(row))

        used = len(lines)
        subtitle = bot.phrase()
        if bot.dragging:
            subtitle = "put me down gently"
        elif bot.hover:
            subtitle = "click me"
        ai_lines = self._ai_lines(bot, max(0, self.rows - used - 3))
        subtitle_color = p.fg(p.color_for_mood(bot.mood), True)
        if not ai_lines:
            plain = self._ai_plain(bot)
            if plain and not bot.dragging and not bot.hover:
                subtitle = plain
                subtitle_color = p.fg("R" if bot.ai.error else "A", True)
        footer_count = 3 + len(ai_lines)
        blank_below = self.rows - footer_count - used
        for _ in range(max(0, blank_below)):
            lines.append(p.bg_seq + "\x1b[K")

        lines.append(self._center(p, subtitle, subtitle_color))
        lines.extend(ai_lines)
        lines.append(self._stats(bot))
        lines.append(self._hints(bot))
        return SYNC_ON + "\x1b[H" + "\r\n".join(lines) + "\x1b[K\x1b[J" + SYNC_OFF

    def _ai_plain(self, bot):
        ai = bot.ai
        if bot.ask_mode:
            return "ask> " + (bot.ask_buf or "_")
        if ai.busy:
            return "thinking..."
        if ai.error:
            return "AI error: " + ai.error
        if ai.answer:
            return "PIXEL " + " ".join(ai.answer.split())
        return ""

    def _ai_lines(self, bot, capacity):
        if capacity <= 0:
            return []
        p = bot.palette
        ai = bot.ai
        limit = max(8, self.cols - 2)

        if bot.ask_mode:
            text = "ask> " + (bot.ask_buf or "_") + "▌"
            text = text[-limit:]
            return [p.bg_seq + "  " + p.fg("A", True) + text + RESET + p.bg_seq + "\x1b[K"]

        if ai.busy:
            return [p.bg_seq + "  " + p.fg("A", True) + "thinking..." + RESET
                    + p.bg_seq + "\x1b[K"]

        if ai.error:
            text = " ".join(("AI error: " + ai.error).split())
            return [p.bg_seq + "  " + p.fg("R", True) + text[:limit] + RESET
                    + p.bg_seq + "\x1b[K"]

        if not ai.answer:
            return []

        body = " ".join(ai.answer.split())
        width = max(20, self.cols - 8)
        chunks = textwrap.wrap(body, width=width, break_long_words=True,
                               break_on_hyphens=True)
        shown = chunks[:capacity]
        out = []
        for index, chunk in enumerate(shown):
            if index == len(shown) - 1 and len(chunks) > capacity:
                chunk += "…"
            prefix = "PIXEL " if index == 0 else "      "
            role = "A" if index == 0 else "FG"
            text = (prefix + chunk)[:limit]
            out.append(p.bg_seq + "  " + p.fg(role, index == 0) + text + RESET
                       + p.bg_seq + "\x1b[K")
        return out

    def _center(self, p, text, color):
        text = text[: max(0, self.cols - 2)]
        left = max(0, (self.cols - len(text)) // 2)
        return p.bg_seq + " " * left + color + text + RESET + p.bg_seq + "\x1b[K"

    def _header(self, bot):
        p = bot.palette
        title = "▌ PIXEL BOT"
        mood = bot.mood.upper()
        if bot.forced:
            mood += " · FORCED"
        left = p.bg_seq + p.fg("A", True) + title + RESET + p.bg_seq
        right = p.fg(p.color_for_mood(bot.mood), True) + mood + RESET + p.bg_seq
        pad = max(1, self.cols - len(title) - len(mood) - 2)
        return left + " " * pad + right + "\x1b[K"

    def _stats(self, bot):
        p = bot.palette
        m = bot.monitor
        fields = [
            ("CPU", f"{m.cpu}%", "A" if m.cpu >= 80 else "FG"),
            ("BAT", f"{m.battery}%", "R" if m.battery <= 15 and m.discharging else "FG"),
            ("AC", "on" if m.ac else "off", "G" if m.ac else "DIM"),
            ("MUS", "on" if m.music else "off", "A" if m.music else "DIM"),
            ("REC", "on" if m.recording else "off", "R" if m.recording else "DIM"),
            ("MUTE", "on" if m.muted else "off", "R" if m.muted else "DIM"),
            ("SND", "on" if bot.sound_on else "off", "G" if bot.sound_on else "DIM"),
        ]
        parts = [p.bg_seq]
        for i, (label, value, role) in enumerate(fields):
            if i:
                parts.append(p.fg("MUTED") + "  ·  ")
            parts.append(p.fg("DIM") + label + " ")
            parts.append(p.fg(role, True) + value + RESET + p.bg_seq)
        line = "".join(parts)
        visible = "  ·  ".join(f"{label} {value}" for label, value, _ in fields)
        if len(visible) > self.cols:
            line = p.bg_seq + p.fg("DIM") + visible[: self.cols] + RESET + p.bg_seq
        return line + "\x1b[K"

    def _hints(self, bot):
        p = bot.palette
        hint = "i ask AI · space wave · m mood · a auto · e error · s sound · r reset · +/- size · q quit   |   drag to move"
        if len(hint) > self.cols:
            hint = "i ask AI · space wave · m mood · s sound · r reset · q quit"
        if len(hint) > self.cols:
            hint = "i ask · space wave · m mood · q quit"
        return p.bg_seq + p.fg("MUTED") + hint[: self.cols] + RESET + p.bg_seq + "\x1b[K"


class MouseReader:
    SGR = re.compile(r"\x1b\[<(\d+);(\d+);(\d+)([Mm])")
    CSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z~]")

    def __init__(self):
        self.buf = ""

    def feed(self, data):
        self.buf += data
        events = []
        while self.buf:
            m = self.SGR.match(self.buf)
            if m:
                events.append(("mouse", int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)))
                self.buf = self.buf[m.end():]
                continue
            if self.buf.startswith("\x1b[<"):
                break  # incomplete SGR mouse event, wait for the rest
            if self.buf.startswith("\x1b["):
                m = self.CSI.match(self.buf)
                if m:
                    self.buf = self.buf[m.end():]
                    continue
                if len(self.buf) < 8:
                    break
                self.buf = self.buf[1:]
                continue
            ch = self.buf[0]
            self.buf = self.buf[1:]
            events.append(("key", ch))
        return events


class App:
    def __init__(self, sound=True, scale=None):
        self.palette = Palette()
        self.bot = Bot(self.palette)
        if not sound:
            self.bot.sound_on = False
        if scale:
            self.bot.scale_override = max(1, min(6, scale))
        self.screen = Screen()
        self.reader = MouseReader()
        self.running = True
        self.old_term = None
        self.need_resize = True

    def setup(self):
        self.old_term = termios.tcgetattr(0)
        tty.setraw(0)
        self.screen.refresh()
        if self.screen.cols < 36 or self.screen.rows < 22:
            raise RuntimeError(
                f"terminal is {self.screen.cols}x{self.screen.rows}; "
                "PixelBot needs at least 36x24"
            )
        sys.stdout.write(ALT_ON + CURSOR_OFF + MOUSE_ON + WRAP_OFF)
        sys.stdout.write("\x1b[2J")
        sys.stdout.flush()

    def cleanup(self):
        try:
            sys.stdout.write(MOUSE_OFF + WRAP_ON + CURSOR_ON + ALT_OFF)
            sys.stdout.flush()
        finally:
            if self.old_term is not None:
                termios.tcsetattr(0, termios.TCSADRAIN, self.old_term)

    def inside(self, x, y, scale, ox, oy):
        return ox <= x < ox + SPRITE_W * 2 * scale and oy <= y < oy + SPRITE_H * scale

    def on_mouse(self, b, x, y, final, now):
        self.bot.monitor.touch()
        scale, w, h, ox, oy = self.screen.layout(self.bot)
        mx, my = x - 1, y - 1
        hover = self.inside(mx, my, scale, ox, oy)
        self.bot.hover = hover

        # eyes follow the pointer anywhere in the terminal, not only on hover
        center_px = ox + w / 2
        dx = mx - center_px
        if abs(dx) > 2.5 * scale:
            self.bot.gaze = -1 if dx < 0 else 1
        else:
            self.bot.gaze = 0

        # wheel: 64 up, 65 down
        if b & 64:
            self.bot.scale_override = max(1, min(6, scale + (1 if b == 64 else -1)))
            self.bot.origin = None
            return

        motion = bool(b & 32)
        left = (b & 3) == 0

        # motion is handled before press: a press+motion event is a drag,
        # not a fresh press, otherwise the bot can never be moved
        if motion:
            if self.bot.pressed:
                if self.bot.press_at:
                    px, py = self.bot.press_at
                    if abs(x - px) + abs(y - py) > 1:
                        self.bot.dragging = True
                gx, gy = self.bot.grab
                nx = max(0, min(x - 1 - gx, max(0, self.screen.cols - w)))
                ny = max(3, min(y - 1 - gy, max(3, self.screen.rows - 4 - h)))
                self.bot.origin = (nx, ny)
            return

        if left and final == "M":
            if hover:
                self.bot.pressed = True
                self.bot.press_at = (x, y)
                self.bot.grab = (mx - ox, my - oy)
                self.bot.dragging = False
            return

        if left and final == "m":
            if self.bot.pressed:
                if not self.bot.dragging and hover:
                    self.bot.wave(now)
                self.bot.pressed = False
                self.bot.dragging = False

    def on_key(self, ch, now):
        self.bot.monitor.touch()
        if self.bot.ask_mode:
            if ch == "\x03":
                self.running = False
            elif ch in ("\r", "\n"):
                self.bot.submit_ask()
            elif ch == "\x1b":
                self.bot.cancel_ask()
            elif ch in ("\x7f", "\b"):
                self.bot.ask_buf = self.bot.ask_buf[:-1]
            elif ch.isprintable() and len(self.bot.ask_buf) < 400:
                self.bot.ask_buf += ch
            return
        if ch in ("q", "\x03"):
            self.running = False
        elif ch == "i":
            self.bot.begin_ask()
        elif ch == " ":
            self.bot.wave(now)
        elif ch == "m":
            self.bot.cycle_forced()
        elif ch == "a":
            self.bot.forced = ""
            self.bot.failed = False
            self.bot.last_mood = ""
            self.bot.monitor.touch()
        elif ch == "e":
            self.bot.forced = ""
            self.bot.failed = not self.bot.failed
            self.bot.last_mood = ""
            self.bot.monitor.touch()
        elif ch == "s":
            self.bot.sound_on = not self.bot.sound_on
            if self.bot.sound_on:
                self.bot.play(self.bot.mood)
        elif ch == "r":
            self.bot.origin = None
            self.bot.monitor.touch()
        elif ch in ("+", "="):
            self.bot.scale_override = min(6, self.screen.scale(self.bot) + 1)
            self.bot.origin = None
        elif ch == "-":
            self.bot.scale_override = max(1, self.screen.scale(self.bot) - 1)
            self.bot.origin = None

    def loop(self):
        try:
            self.setup()
            while self.running:
                started = time.monotonic()
                now = started
                self.palette.refresh()
                self.bot.update(now)

                if self.need_resize:
                    self.screen.refresh()
                    if self.bot.origin is not None:
                        _s, _w, _h, ox, oy = self.screen.layout(self.bot)
                        self.bot.origin = (ox, oy)
                    self.need_resize = False

                write_all(self.screen.render(self.bot))

                ready, _, _ = select.select([0], [], [], 0.14)
                if ready:
                    try:
                        data = os.read(0, 4096).decode("utf-8", "ignore")
                    except OSError:
                        break
                    for ev in self.reader.feed(data):
                        if ev[0] == "key":
                            self.on_key(ev[1], now)
                        else:
                            self.on_mouse(ev[1], ev[2], ev[3], ev[4], now)
                    self.bot.update(time.monotonic())

                self.bot.frame += 1
                elapsed = time.monotonic() - started
                if elapsed < 0.14:
                    time.sleep(0.14 - elapsed)
        finally:
            self.cleanup()


def write_all(text):
    data = text.encode("utf-8", "replace")
    while data:
        try:
            written = os.write(1, data)
        except InterruptedError:
            continue
        if written <= 0:
            break
        data = data[written:]


def sigwinch(_sig, _frame):
    if APP is not None:
        APP.need_resize = True


def sigterm(_sig, _frame):
    if APP is not None:
        APP.running = False


APP = None


def ask_command(args):
    question = " ".join(args).strip()
    if not question:
        if sys.stdin.isatty():
            print("pixelbot: usage: pixelbot ask \"question\"")
            return 2
        question = sys.stdin.read().strip()
    if not question:
        print("pixelbot: empty question", file=sys.stderr)
        return 2
    bot = Bot(Palette())
    now = time.monotonic()
    bot.monitor.poll(now)
    bot.mood = bot.current_mood(now)
    answer, error = bot.ai.ask_sync(question, bot.ai_context())
    if error:
        print("pixelbot: " + error, file=sys.stderr)
        return 1
    print(answer)
    return 0


def main():
    global APP
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        print(__doc__.strip())
        return 0
    if args and args[0].lower() == "ask":
        return ask_command(args[1:])
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("pixelbot: run this in a terminal (it needs mouse + raw mode)")
        return 1

    sound = "--no-sound" not in args
    scale = None
    unknown = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--no-sound":
            pass
        elif arg == "--scale" and i + 1 < len(args):
            try:
                scale = int(args[i + 1])
            except ValueError:
                unknown.append(args[i + 1])
            i += 1
        elif arg.startswith("--scale="):
            try:
                scale = int(arg.split("=", 1)[1])
            except ValueError:
                unknown.append(arg)
        elif arg not in ("-h", "--help"):
            unknown.append(arg)
        i += 1
    if unknown:
        print(f"pixelbot: unknown option: {unknown[0]} (try --help)")
        return 2

    APP = App(sound=sound, scale=scale)
    signal.signal(signal.SIGWINCH, sigwinch)
    signal.signal(signal.SIGTERM, sigterm)
    try:
        APP.loop()
    except KeyboardInterrupt:
        pass
    except RuntimeError as exc:
        print(f"pixelbot: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
