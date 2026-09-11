#!/usr/bin/env python3
"""watchcat-dash.py — WatchCat HTML dashboard generator. Stdlib only.

Usage: watchcat-dash.py <out.html> <cap_mb>
Reads aggregates from the daemon's DB (~/.local/share/watchcat/daemon.db) and
its live.json, writes a dashboard atomically (tmp + os.replace).

Design: full matugen fidelity palette from the girl-in-red-aesthetic
wallpaper, Geist Sans + Geist Mono via fontsource CDN, Phosphor icons.
Hand-rolled CSS — wide layout, cap shown as a 0->1 number line, week as a
readable per-day number table, today split as a CSS conic donut (no chart
library). Auto-reloads every 30s. All numbers come from the daemon.
"""
import sys
import html
import os
import json
import sqlite3
from datetime import datetime, date, timedelta

DB = os.path.expanduser("~/.local/share/watchcat/daemon.db")
LIVE = os.path.expanduser("~/.local/share/watchcat/live.json")

# Live scheme source: same file quickshell reads (matugen rewrites it on
# every theme change). Fallback: girl-in-red fidelity palette (same values
# matugen fidelity produces for this wallpaper, so fallback looks identical).
SCHEME_FILE = os.path.expanduser("~/.config/quickshell/colors.css")
DEFAULT = {
    "background": "#131311", "foreground": "#e5e2de", "primary": "#c5caa7",
    "secondary": "#c7c8b7", "tertiary": "#d9bfd4", "error": "#ffb4ab",
    "on_surface": "#e9e6e2", "surface_variant": "#47473e", "outline": "#97978c",
    "on_surface_variant": "#c8c7bb", "surface_dim": "#131311",
    "surface_bright": "#3e3e3b",
    "surface_container_low": "#1d1c1a", "surface_container": "#232320",
    "surface_container_high": "#2e2d2b", "surface_container_highest": "#393835",
    "on_primary": "#252a13", "primary_container": "#9ba080",
    "primary_fixed": "#e1e6c2",
    "on_secondary": "#27291e", "secondary_container": "#646558",
    "secondary_fixed": "#e3e4d2",
    "on_tertiary": "#332232", "tertiary_container": "#ae96aa",
    "tertiary_fixed": "#f6dbf0",
    "on_error": "#580003", "error_container": "#c32220",
    "outline_variant": "#64655b",
}


def _darken(hex_color, factor=0.58):
    """Darken a #hex color (simulate surface_dim -> bg-deep)."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    return "#%02x%02x%02x" % (int(r*factor), int(g*factor), int(b*factor))


def _alpha_bg(hex_color, alpha, bg_hex):
    """Composite hex_color over bg_hex at given alpha (0..1)."""
    fg = hex_color.lstrip("#"); bg = bg_hex.lstrip("#")
    fgc = [int(fg[i:i+2], 16) for i in (0, 2, 4)]
    bgc = [int(bg[i:i+2], 16) for i in (0, 2, 4)]
    c = [int(fgc[i]*alpha + bgc[i]*(1-alpha)) for i in range(3)]
    return "#%02x%02x%02x" % tuple(c)


def read_scheme():
    """Parse matugen's colors.css into {name: #hex}. Live system scheme."""
    pal = dict(DEFAULT)
    try:
        with open(SCHEME_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("@define-color"):
                    parts = line.split()
                    if len(parts) >= 3 and parts[2].startswith("#"):
                        pal[parts[1]] = parts[2].rstrip(";")
    except Exception:
        pass
    # Derived: bg-deep (darker than surface_dim for hero footers / deep bg)
    # and border values that CSS can't composite from a single hex var.
    bg = pal.get("background", pal["background"])
    pal["bg_deep"] = _darken(bg, 0.58)
    ol = pal.get("outline", "#97978c")
    pal["border"] = _alpha_bg(ol, 0.18, bg)
    pal["border_soft"] = _alpha_bg(ol, 0.06, bg)
    return pal


def today():
    return date.today().isoformat()


def read_live():
    """Current daemon state + aggregate down/up rate from live.json talkers."""
    d = {"state": "?", "err": "", "iface": "", "down": 0.0, "up": 0.0}
    try:
        with open(LIVE, encoding="utf-8") as f:
            l = json.load(f)
        d["state"] = l.get("state", "?")
        d["err"] = l.get("err", "")
        d["iface"] = l.get("iface", "")
        for t in l.get("talkers") or []:  # per-proc KB/s, sum = current rate
            d["down"] += float(t.get("down", 0))
            d["up"] += float(t.get("up", 0))
    except Exception:
        pass
    return d


def read_db():
    """Return (day, rx_mb, tx_mb, week, procs) from daemon.db."""
    day = today()
    if not os.path.exists(DB):
        return day, 0.0, 0.0, [], []
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    rx = tx = 0.0
    total_row = conn.execute("SELECT rx_mb, tx_mb FROM day_total WHERE day=?", (day,)).fetchone()
    if total_row:
        rx, tx = total_row["rx_mb"] or 0, total_row["tx_mb"] or 0
    # last 7 days, zero-filled only where the daemon has no data at all
    week = [{"day": (date.fromisoformat(day) - timedelta(days=i)).isoformat(),
             "rx": 0.0, "tx": 0.0} for i in range(6, -1, -1)]
    for r in conn.execute("SELECT day, rx_mb, tx_mb FROM day_total ORDER BY day DESC LIMIT 7"):
        for w in week:
            if w["day"] == r["day"]:
                w["rx"], w["tx"] = r["rx_mb"] or 0, r["tx_mb"] or 0
    procs = [dict(r) for r in conn.execute(
        "SELECT prog, rx_mb AS rx, tx_mb AS tx, peak_mb AS peak FROM day_proc WHERE day=? "
        "ORDER BY rx_mb + tx_mb DESC", (day,))]
    conn.close()
    return day, rx, tx, week, procs


def fmt_mb(mb):
    if mb >= 1024:
        return "%.2f GB" % (mb / 1024)
    if mb >= 10:
        return "%.0f MB" % mb
    return "%.1f MB" % mb


def fmt_kbs(k):
    if k >= 1024:
        return "%.2f MB/s" % (k / 1024)
    return "%.0f KB/s" % k


def fmt_peak(mb_s):
    if mb_s >= 1:
        return "%.1f MB/s" % mb_s
    return "%.0f KB/s" % (mb_s * 1024)


def main():
    out = sys.argv[1]
    cap = float(sys.argv[2] or 1024)
    PAL = read_scheme()
    day, rx, tx, week, procs = read_db()
    live = read_live()
    total = rx + tx
    frac = total / cap if cap > 0 else 0          # 0..1, can exceed 1
    pct = min(100, frac * 100)
    stamp = datetime.now().strftime("%H:%M")
    day_label = date.fromisoformat(day).strftime("%a, %d %b")
    bar_color = PAL["error"] if frac >= 1 else PAL["primary"]
    peak_max = max([float(p["peak"] or 0) for p in procs] + [0])

    # week as readable number rows (oldest -> today), bar scaled to week max
    wmax = max([w["rx"] + w["tx"] for w in week] + [1])
    week_rows = []
    for w in week:
        d = date.fromisoformat(w["day"])
        wt = w["rx"] + w["tx"]
        is_today = w["day"] == day
        wbar = min(100, wt / wmax * 100)
        week_rows.append(
            '<tr class="%s">'
            '<td class="wday">%s</td>'
            '<td class="wdate num">%s</td>'
            '<td class="num r wdown">%s</td>'
            '<td class="num r wup">%s</td>'
            '<td class="num r wtotal">%s</td>'
            '<td class="share"><div class="track"><div class="fill" style="width:%.0f%%"></div></div></td>'
            '</tr>' % (
                "today" if is_today else "",
                d.strftime("%A"), d.strftime("%d %b"),
                fmt_mb(w["rx"]), fmt_mb(w["tx"]), fmt_mb(wt), wbar))
    week_rows = "\n".join(week_rows)

    # today split donut (pure CSS conic gradient)
    if total > 0:
        down_deg = rx / total * 360
        down_pct = rx / total * 100
    else:
        down_deg, down_pct = 0, 0
    up_pct = 100 - down_pct
    donut_bg = 'conic-gradient(%s 0deg %sdeg, %s %sdeg 360deg)' % (
        PAL["tertiary"], "%.1f" % down_deg, PAL["primary"], "%.1f" % down_deg)
    donut = (
        '<div class="donut" style="background:' + donut_bg + '">'
        '<div class="donut-hole"></div>'
        '<div class="donut-text"><span class="num">' + ("%.0f%%" % down_pct) + '</span>'
        '<span class="dlabel">down</span></div>'
        '</div>'
    )
    donut_legend = (
        '<span class="lg"><span class="sw" style="background:%s"></span>down %s</span>'
        '<span class="lg"><span class="sw" style="background:%s"></span>up %s</span>'
    ) % (PAL["tertiary"], fmt_mb(rx), PAL["primary"], fmt_mb(tx))

    # top talkers table (top 25)
    maxp = max([p["rx"] + p["tx"] for p in procs] + [1])
    rows = []
    for i, p in enumerate(procs[:25]):
        name = html.escape(str(p["prog"]))
        pr, pt = float(p["rx"]), float(p["tx"])
        ptot = pr + pt
        share = ptot / maxp * 100
        hot = bool(p["peak"]) and float(p["peak"]) > 0.5
        flame = '<span class="i ph-bold ph-fire" aria-hidden="true"></span>' if hot else ""
        rows.append(
            '<tr class="row">'
            '<td class="rank">%d</td>'
            '<td class="proc">%s%s</td>'
            '<td class="num r">%s</td>'
            '<td class="num r">%s</td>'
            '<td class="num r strong">%s</td>'
            '<td class="share"><div class="track"><div class="fill" style="width:%.0f%%"></div></div></td>'
            '<td class="num r dim">%s</td></tr>'
            % (i + 1, flame, name, fmt_mb(pr), fmt_mb(pt), fmt_mb(ptot),
               share, fmt_peak(float(p["peak"] or 0)))
        )
    table_rows = "\n".join(rows) if rows else (
        '<tr class="row"><td colspan="7" class="empty">'
        "the daemon is listening &mdash; per-process numbers appear once there is traffic"
        "</td></tr>")

    # daemon status line
    if live["state"] == "on":
        status = ('<span class="dot ok"></span> watching 24/7'
                  + (" &middot; " + html.escape(live["iface"]) if live["iface"] else ""))
    elif live["state"] == "error":
        status = '<span class="dot bad"></span> ' + html.escape(live["err"] or "daemon error")
    else:
        status = '<span class="dot idle"></span> starting'

    rate_line = (
        '<span class="rate"><span class="i ph ph-arrow-down"></span><b class="num">%s</b></span>'
        '<span class="rate"><span class="i ph ph-arrow-up"></span><b class="num">%s</b></span>'
    ) % (fmt_kbs(live["down"]), fmt_kbs(live["up"]))

    chips = (
        '<div class="stat"><span class="slabel"><span class="i ph ph-arrow-down"></span>down today</span>'
        '<span class="sval num">%s</span></div>'
        '<div class="stat"><span class="slabel"><span class="i ph ph-arrow-up"></span>up today</span>'
        '<span class="sval num">%s</span></div>'
        '<div class="stat"><span class="slabel"><span class="i ph ph-rocket"></span>peak rate</span>'
        '<span class="sval num">%s</span></div>'
        '<div class="stat"><span class="slabel"><span class="i ph ph-cube"></span>processes</span>'
        '<span class="sval num">%d</span></div>'
    ) % (fmt_mb(rx), fmt_mb(tx), fmt_peak(peak_max), len(procs))

    # 0 -> 1 number line marker position (clamped to line, text shows real frac)
    mark_px = min(100, frac * 100)

    page = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="30">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WatchCat — @day_label@</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://cdn.jsdelivr.net/npm/@fontsource/geist-sans@5/index.css" rel="stylesheet">
<link href="https://cdn.jsdelivr.net/npm/@fontsource/geist-mono@5/index.css" rel="stylesheet">
<link href="https://cdn.jsdelivr.net/npm/@phosphor-icons/web@2.1.1/src/regular/style.css" rel="stylesheet">
<link href="https://cdn.jsdelivr.net/npm/@phosphor-icons/web@2.1.1/src/bold/style.css" rel="stylesheet">
<style>
:root {
  /* live matugen scheme — every tone a @define-color from colors.css */
  --bg:            @background@;
  --bg-deep:       @bg_deep@;
  --card:          @surface_container@;
  --card-low:      @surface_container_low@;
  --card-high:     @surface_container_high@;
  --card-highest:  @surface_container_highest@;
  --bright:        @surface_bright@;
  --text:          @foreground@;
  --text-bright:   @on_surface@;
  --text-muted:    @on_surface_variant@;
  --primary:       @primary@;
  --on-primary:    @on_primary@;
  --pri-container: @primary_container@;
  --pri-fixed:     @primary_fixed@;
  --secondary:     @secondary@;
  --on-secondary:  @on_secondary@;
  --sec-container: @secondary_container@;
  --sec-fixed:     @secondary_fixed@;
  --tertiary:      @tertiary@;
  --on-tertiary:   @on_tertiary@;
  --tri-container: @tertiary_container@;
  --tri-fixed:     @tertiary_fixed@;
  --error:         @error@;
  --on-error:      @on_error@;
  --err-container: @error_container@;
  --outline:       @outline@;
  --outline-var:   @outline_variant@;
  --surface-var:   @surface_variant@;
  --border:        @border@;
  --border-soft:   @border_soft@;
  --radius: 14px;
}
* { box-sizing: border-box; }
html { scrollbar-color: var(--outline-var) var(--bg); }
body {
  margin: 0; background: var(--bg); color: var(--text);
  font-family: "Geist Sans", ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}
main { max-width: 1560px; margin: 0 auto; padding: 34px 28px 56px; }
.num { font-family: "Geist Mono", ui-monospace, monospace; font-variant-numeric: tabular-nums; }
.i { line-height: 1; }

/* header */
header { display: flex; align-items: flex-end; justify-content: space-between; gap: 16px; margin-bottom: 26px; }
.brand { display: flex; align-items: center; gap: 10px; }
.brand .i { font-size: 24px; color: var(--primary); }
h1 { font-size: 18px; font-weight: 600; letter-spacing: .24em; text-transform: uppercase; margin: 0; color: var(--text-bright); }
.status { display: flex; align-items: center; gap: 8px; margin: 10px 0 0; font-size: 12px; color: var(--text-muted); }
.dot { width: 8px; height: 8px; border-radius: 50%; flex: none; }
.dot.ok { background: var(--primary); box-shadow: 0 0 8px var(--primary); }
.dot.bad { background: var(--error); }
.dot.idle { background: var(--outline); }
.meta { text-align: right; }
.meta .day { font-size: 13px; color: var(--text-bright); }
.meta .stamp { font-size: 11px; color: var(--outline); margin-top: 4px; }

/* cards */
.card { background: var(--card); border: 1px solid var(--border); border-radius: var(--radius); }
.card-label { display: flex; align-items: center; gap: 8px; font-size: 10px; letter-spacing: .2em; text-transform: uppercase; color: var(--text-muted); }

/* hero — cap as a 0 -> 1 number line */
.hero { padding: 24px 28px 20px; margin-bottom: 16px;
        background: linear-gradient(180deg, var(--card-high), var(--card) 70%); }
.hero-top { display: flex; align-items: center; justify-content: space-between; gap: 20px; margin-bottom: 18px; }
.budget { font-size: 64px; font-weight: 600; line-height: .95; color: var(--text-bright); }
.budget-sub { margin-top: 8px; font-size: 13px; color: var(--text-muted); }
.live { display: flex; gap: 24px; font-size: 13px; color: var(--text-muted); padding-bottom: 4px; }
.live .rate { display: inline-flex; align-items: center; gap: 7px; }
.live .rate b { font-size: 17px; color: var(--text-bright); font-weight: 500; }
.live .i.ph-arrow-down { color: var(--tertiary); }
.live .i.ph-arrow-up { color: var(--primary); }

/* the number line: ticks + marker */
.numline { position: relative; margin: 26px 0 8px; }
.numline .track {
  position: relative; height: 2px; background: var(--outline-var);
  border-radius: 1px;
}
.numline .track::before, .numline .track::after {
  content: ''; position: absolute; top: -4px; width: 2px; height: 10px; background: var(--outline-var);
}
.numline .track::before { left: 0; } .numline .track::after { right: 0; }
.numline .fill {
  position: absolute; top: -2px; left: 0; height: 6px; border-radius: 3px;
  background: @bar_color@; width: @pct@%; transition: width .7s ease;
}
.numline .ticks { display: flex; justify-content: space-between; margin-top: 10px; }
.numline .ticks span { font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: var(--outline); position: relative; }
.numline .ticks span::before {
  content: ''; position: absolute; top: -13px; left: 50%; width: 1px; height: 5px; background: var(--outline-var);
}
.numline .marker {
  position: absolute; top: -9px; left: calc(@pct@% - 9px); width: 18px; height: 18px;
  border-radius: 50%; background: var(--card-highest);
  border: 3px solid @bar_color@; box-shadow: 0 0 10px rgba(0,0,0,.5); transition: left .7s ease; z-index: 2;
}
.numline .marker::after {
  content: '@frac_lbl@'; position: absolute; top: 25px; left: 50%; transform: translateX(-50%);
  font-family: "Geist Mono", monospace; font-size: 11px; font-weight: 600;
  color: @bar_color@; white-space: nowrap;
}
.used-left { display: flex; justify-content: space-between; margin: 20px 0 0; font-size: 11px; color: var(--outline); }
.used-left b { color: var(--text-muted); font-weight: 500; }

/* stat strip */
.statstrip {
  display: grid; grid-template-columns: repeat(4, 1fr);
  margin-top: 22px; background: var(--card-low);
  border: 1px solid var(--border); border-radius: 10px; overflow: hidden;
}
@media (max-width: 700px) { .statstrip { grid-template-columns: 1fr 1fr; } }
.stat { padding: 13px 18px; display: flex; flex-direction: column; gap: 5px; }
.stat + .stat { border-left: 1px solid var(--border); }
@media (max-width: 700px) {
  .stat:nth-child(3) { border-left: none; }
  .stat:nth-child(n+3) { border-top: 1px solid var(--border); }
}
.stat .slabel { font-size: 10px; letter-spacing: .16em; text-transform: uppercase; color: var(--outline); display: flex; align-items: center; gap: 7px; }
.stat .slabel .i { font-size: 14px; }
.stat:nth-child(1) .slabel .i { color: var(--tertiary); }
.stat:nth-child(2) .slabel .i { color: var(--primary); }
.stat:nth-child(3) .slabel .i { color: var(--tri-fixed); }
.stat:nth-child(4) .slabel .i { color: var(--sec-fixed); }
.stat .sval { font-size: 22px; font-weight: 600; color: var(--text-bright); line-height: 1.1; }

/* week + today split: side by side */
.mid { display: grid; grid-template-columns: minmax(0,3fr) minmax(0,2fr); gap: 16px; margin-bottom: 16px; }
@media (max-width: 900px) { .mid { grid-template-columns: 1fr; } .hero-top { flex-direction: column; align-items: flex-start; } }
.panel { padding: 18px 22px; }
.panel .card-label { margin-bottom: 14px; }
.panel .card-label .i { font-size: 14px; }

/* week: readable numbers table */
table { width: 100%; border-collapse: collapse; font-size: 13px; }
.week thead th {
  text-align: left; font-size: 10px; font-weight: 500; letter-spacing: .18em;
  text-transform: uppercase; color: var(--outline); padding: 4px 6px; border-bottom: 1px solid var(--border);
}
.week thead th.r, .week td.r { text-align: right; }
.week tbody td { padding: 7px 6px; border-bottom: 1px solid rgba(151,151,140,.06); }
.week tbody tr:last-child td { border-bottom: none; }
.week .wday { font-weight: 600; color: var(--text-bright); width: 90px; }
.week .wdate { color: var(--outline); font-size: 11px; width: 60px; }
.week .wdown { color: var(--tri-fixed); }
.week .wup { color: var(--pri-fixed); }
.week .wtotal { font-weight: 600; color: var(--text-bright); }
.week tr.today .wday { color: var(--tertiary); }
.week tr.today { background: rgba(217,191,212,.05); }
.week tbody .track { height: 5px; }
.week tbody .fill { background: linear-gradient(90deg, var(--tri-container), var(--tertiary)); }

/* today split: css donut */
.donut-wrap { display: flex; flex-direction: column; align-items: center; gap: 12px; padding: 8px 0 4px; }
.donut { position: relative; width: 170px; height: 170px; border-radius: 50%; }
.donut-hole { position: absolute; inset: 14%; border-radius: 50%; background: var(--bg); }
.donut-text { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; }
.donut-text .num { font-size: 26px; font-weight: 600; color: var(--text-bright); }
.donut-text .dlabel { font-size: 10px; letter-spacing: .18em; text-transform: uppercase; color: var(--outline); }
.dlegend { display: flex; gap: 18px; font-size: 12px; color: var(--text-muted); }
.lg { display: inline-flex; align-items: center; gap: 6px; }
.sw { width: 10px; height: 10px; border-radius: 3px; }
.sw.down { background: var(--tertiary); } .sw.up { background: var(--primary); }

/* talkers table — full width */
.talkers { overflow: hidden; margin-top: 16px; }
.talkers .head { display: flex; align-items: center; justify-content: space-between; padding: 16px 22px 10px; }
.talkers .head .note { font-size: 11px; color: var(--outline); }
.talkers thead th {
  text-align: left; font-size: 10px; font-weight: 500; letter-spacing: .18em;
  text-transform: uppercase; color: var(--outline); padding: 6px 22px;
  border-top: 1px solid var(--border); border-bottom: 1px solid var(--border);
  background: var(--card-low);
}
.talkers thead th.r, .talkers td.r { text-align: right; }
.talkers tbody tr { border-bottom: 1px solid rgba(151,151,140,.07); }
.talkers tbody tr:last-child { border-bottom: none; }
.talkers tbody tr.row { transition: background .15s; }
.talkers tbody tr.row:hover { background: var(--card-high); }
.talkers td { padding: 8px 22px; vertical-align: middle; }
.talkers td.rank { width: 34px; color: var(--outline); font-size: 12px; }
.talkers td.proc { font-weight: 500; color: var(--text-bright); }
.talkers td.proc .i { color: var(--error); margin-right: 7px; font-size: 12px; }
.talkers td.num { font-size: 12px; }
.talkers td.strong { font-weight: 600; color: var(--tertiary); }
.talkers td.dim { color: var(--outline); }
.talkers td.share { width: 140px; }
.talkers td.empty { text-align: center; color: var(--text-muted); padding: 36px 22px; }
.track { height: 6px; border-radius: 3px; background: var(--surface-var); overflow: hidden; }
.fill { height: 100%; border-radius: 3px; background: linear-gradient(90deg, var(--tri-container), var(--tertiary)); }

footer { margin-top: 22px; font-size: 11px; color: var(--outline); display: flex; flex-wrap: wrap; gap: 8px 22px; justify-content: space-between; }
footer span { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
</style>
</head>
<body>
<main>

  <header>
    <div>
      <div class="brand"><span class="i ph ph-activity"></span><h1>WatchCat</h1></div>
      <p class="status">@status@</p>
    </div>
    <div class="meta">
      <div class="day num">@day_label@</div>
      <div class="stamp">refreshed @stamp@ &middot; auto-reloads 30s</div>
    </div>
  </header>

  <section class="card hero">
    <div class="hero-top">
      <div class="card-label"><span class="i ph ph-gauge"></span> day budget</div>
      <div class="live">@rate_line@</div>
    </div>
    <div class="budget num">@total@</div>
    <div class="budget-sub">of @cap@ cap &middot; @frac_lbl@ of 1.0 used</div>

    <div class="numline">
      <div class="track"><div class="fill"></div></div>
      <div class="marker"></div>
      <div class="ticks"><span>0</span><span>0.25</span><span>0.5</span><span>0.75</span><span>1.0</span></div>
    </div>
    <div class="used-left">
      <span>used <b class="num">@total@</b></span>
      <span>left <b class="num">@left@</b></span>
      <span>warn at <b class="num">@warn@</b></span>
    </div>

    <div class="statstrip">@chips@</div>
  </section>

  <div class="mid">
    <section class="card panel">
      <div class="card-label"><span class="i ph ph-calendar-blank"></span> this week &mdash; by day</div>
      <table class="week">
        <thead><tr><th>day</th><th>date</th><th class="r">down</th><th class="r">up</th><th class="r">total</th><th></th></tr></thead>
        <tbody>@week_rows@</tbody>
      </table>
    </section>
    <section class="card panel">
      <div class="card-label"><span class="i ph ph-pie-chart"></span> today split</div>
      <div class="donut-wrap">
        @donut@
        <div class="dlegend">@donut_legend@</div>
      </div>
    </section>
  </div>

  <section class="card talkers">
    <div class="head">
      <div class="card-label"><span class="i ph ph-hard-drives"></span> top talkers &mdash; all of today</div>
      <span class="note"><span class="i ph-bold ph-fire"></span> peaked &gt; 500 KB/s</span>
    </div>
    <table>
      <thead><tr><th>#</th><th>process</th><th class="r">down</th><th class="r">up</th><th class="r">total</th><th>share</th><th class="r">peak</th></tr></thead>
      <tbody>@table_rows@</tbody>
    </table>
  </section>

  <footer>
    <span><span class="i ph ph-bell"></span> alert &gt; 500 KB/s &times; 10s &middot; warn @warn@ &middot; cap @cap@</span>
    <span><span class="i ph ph-warning"></span> notify-only &middot; 7 days kept &middot; all numbers from the daemon</span>
  </footer>

</main>
</body>
</html>"""

    frac_lbl = ("%.2f" % frac) if frac < 100 else "%.0f" % frac
    for name, value in (
        ("day_label", day_label), ("stamp", stamp), ("status", status),
        ("pct", "%.1f" % pct), ("bar_color", bar_color),
        ("frac_lbl", frac_lbl), ("total", fmt_mb(total)), ("cap", fmt_mb(cap)),
        ("left", fmt_mb(max(0, cap - total))), ("warn", fmt_mb(cap / 2)),
        ("rate_line", rate_line), ("chips", chips),
        ("week_rows", week_rows), ("donut", donut), ("donut_legend", donut_legend),
        ("table_rows", table_rows),
    ):
        page = page.replace("@%s@" % name, str(value))
    for name, hexv in PAL.items():  # full live scheme incl. derived
        page = page.replace("@%s@" % name, hexv)

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(page)
    os.replace(tmp, out)
    print("ok " + out)


if __name__ == "__main__":
    main()