#!/usr/bin/env python3
"""
kitty custom tab bar — powerline style, numeric labels, scrolling titles.

  - Numbers 1 2 3 … so alt+1..9 jump matches what you read.
  - Long titles don't ellipsize — they scroll like a text ticker.
  - Written against the kitty >= 0.48 custom tab bar API (8-argument
    draw_tab). as_rgb/draw_title/powerline_symbols live in kitty.tab_bar,
    NOT in fast_data_types. Scrolling uses kitty's add_timer +
    boss.refresh_active_tab_bar() so it animates even while idle.

Set USE_KANJI = True to switch 1 2 3 → 一 二 三.
"""

import time

from kitty.fast_data_types import (
    Screen,
    add_timer,
    get_boss,
    monotonic,
)
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabBarData,
    as_rgb,
    draw_title,
    powerline_symbols,
)

# ── numerals ─────────────────────────────────────────────────────
USE_KANJI = True  # numbers by default; True for 一二三…

# One-based → Japanese numeral. Handles 1..99; beyond that falls back to
# Western digits so the bar never breaks no matter how many tabs exist.
_KANJI = '〇一二三四五六七八九'


def japanese_numeral(n: int) -> str:
    if n < 10:
        return _KANJI[n]
    if n < 20:
        return '十' + (_KANJI[n % 10] if n % 10 else '')
    if n < 100:
        tens = _KANJI[n // 10] + '十'
        return tens + (_KANJI[n % 10] if n % 10 else '')
    return str(n)


def numeral(n: int) -> str:
    return japanese_numeral(n) if USE_KANJI else str(n)


# ── ticker (marquee for long titles) ─────────────────────────────
TICK_STEP = 0.12        # seconds between repaints while a title scrolls
TICK_CELLS_PER_SEC = 8  # scroll speed in cells per second

_ticker_timer = None


def _repaint(_timer_id=None) -> None:
    global _ticker_timer
    _ticker_timer = None
    try:
        boss = get_boss()
        if boss is not None:
            boss.refresh_active_tab_bar()
    except Exception:
        pass


def _schedule_next_frame() -> None:
    global _ticker_timer
    if _ticker_timer is None:
        try:
            _ticker_timer = add_timer(_repaint, TICK_STEP, False)
        except Exception:
            _ticker_timer = None


def _now() -> float:
    try:
        return monotonic()
    except Exception:
        return time.monotonic()


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    # kitty pre-sets the cursor colours for this tab (active/inactive).
    tab_bg = screen.cursor.bg
    tab_fg = screen.cursor.fg
    default_bg = as_rgb(int(draw_data.default_bg))
    if extra_data.next_tab:
        next_tab_bg = as_rgb(draw_data.tab_bg(extra_data.next_tab))
        needs_soft_separator = next_tab_bg == tab_bg
    else:
        next_tab_bg = default_bg
        needs_soft_separator = False

    separator_symbol, soft_separator_symbol = powerline_symbols.get(
        draw_data.powerline_style, ('\ue0b0', '\ue0b1'))

    if screen.cursor.x == 0:
        screen.cursor.bg = tab_bg
        screen.draw(' ')

    # Leading numeral, then a gap, then the title.
    # kitty hands us index already 1-based (i + 1), so use it as-is.
    screen.cursor.bg = tab_bg
    screen.cursor.fg = tab_fg
    screen.draw(numeral(index))
    screen.draw(' ')

    title = tab.title or ''
    ticker_on = False
    if extra_data.for_layout or len(title) <= max_tab_length:
        # Short enough (or just measuring): normal truncating title.
        draw_title(draw_data, screen, tab, index, max_tab_length)
    else:
        # Long title → scroll a window over it, wrapping seamlessly.
        ticker_on = True
        avail = max_tab_length
        pos = int(_now() * TICK_CELLS_PER_SEC) % len(title)
        shown = (title * 2)[pos:pos + avail]
        x0 = screen.cursor.x
        for ch in shown:
            screen.draw(ch)
        # Pad to the reserved width so other tabs stay put (wide chars may
        # overflow by a cell or two — acceptable).
        while screen.cursor.x < x0 + avail:
            screen.draw(' ')

    if ticker_on and not extra_data.for_layout:
        _schedule_next_frame()

    # Powerline separator into the next tab.
    if not needs_soft_separator:
        screen.draw(' ')
        screen.cursor.fg = tab_bg
        screen.cursor.bg = next_tab_bg
        screen.draw(separator_symbol)
    else:
        prev_fg = screen.cursor.fg
        if tab_bg == tab_fg:
            screen.cursor.fg = default_bg
        elif tab_bg != default_bg:
            c1 = draw_data.inactive_bg.contrast(draw_data.default_bg)
            c2 = draw_data.inactive_bg.contrast(draw_data.inactive_fg)
            if c1 < c2:
                screen.cursor.fg = default_bg
        screen.draw(f' {soft_separator_symbol}')
        screen.cursor.fg = prev_fg

    end = screen.cursor.x
    if end < screen.columns:
        screen.draw(' ')
    return end