#!/usr/bin/env python3
"""watchcat-daemon.py — 24/7 per-process traffic tracking for WatchCat.

systemd --user service. Runs nethogs in chunks (passwordless sudo via
/etc/sudoers.d/watchcat), accumulates per-process + day totals into
daemon.db (sqlite3, ~/.local/share/watchcat/), sends hot/day alerts via
notify-send, and writes live.json for the panel to display.

Single writer: the panel and dashboard only READ daemon.db / live.json.

Flow per cycle: resolve default iface -> `sudo -n timeout CHUNK nethogs -t -d 1
<iface>` -> parse -> update DB + alerts -> write live.json -> repeat.
"""
import json
import os
import sqlite3
import subprocess
import sys
import time
from datetime import date

HOME = os.path.expanduser("~")
DATA = os.path.join(HOME, ".local/share/watchcat")
DB = os.path.join(DATA, "daemon.db")
LIVE = os.path.join(DATA, "live.json")
NETHOGS = "/usr/bin/nethogs"
NOTIFY = "/usr/bin/notify-send"

HOT_KBS = 500.0
HOT_SECS = 10
WARN_MB = 500.0
CAP_MB = 1024.0
CHUNK = 12  # seconds per nethogs run


def notify(urg, title, body):
    try:
        subprocess.Popen([NOTIFY, "-a", "WatchCat", "-u", urg, title, body])
    except OSError:
        pass


def default_iface():
    try:
        out = subprocess.check_output(
            ["ip", "route", "show", "default"], text=True, stderr=subprocess.DEVNULL
        )
        return out.splitlines()[0].split()[4]
    except Exception:
        return ""


def connect():
    os.makedirs(DATA, exist_ok=True)
    c = sqlite3.connect(DB)
    c.execute("CREATE TABLE IF NOT EXISTS day_total(day TEXT PRIMARY KEY, rx_mb REAL, tx_mb REAL)")
    c.execute(
        "CREATE TABLE IF NOT EXISTS day_proc(day TEXT, prog TEXT, rx_mb REAL,"
        " tx_mb REAL, peak_mb REAL, PRIMARY KEY(day, prog))"
    )
    c.execute(
        "CREATE TABLE IF NOT EXISTS sent(day TEXT, kind TEXT, prog TEXT,"
        " PRIMARY KEY(day, kind, prog))"
    )
    return c


def prune(c, day):
    c.execute("DELETE FROM day_proc WHERE day < ?", (day,))
    c.execute("DELETE FROM day_total WHERE day < ?", (day,))
    c.execute("DELETE FROM sent WHERE day < ?", (day,))


def sent_today(c, day, kind, prog):
    return c.execute(
        "SELECT 1 FROM sent WHERE day=? AND kind=? AND prog=?", (day, kind, prog)
    ).fetchone() is not None


def parse(lines):
    """nethogs -t lines -> (prog -> {rx_kb, tx_kb, n, pid}, unatt_kb)."""
    agg = {}
    unatt = 0.0
    for raw in lines:
        line = raw.strip()
        if not line or line.endswith(":") or "/" not in line:
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            up = float(parts[-2])
            dn = float(parts[-1])
        except ValueError:
            continue
        segs = parts[0].split("/")
        if len(segs) < 3:
            continue
        segs.pop()  # uid
        pid = segs.pop()
        prog = segs.pop()  # last path segment is the process name
        if pid == "0":
            unatt += up + dn  # kernel / unattributable
            continue
        a = agg.setdefault(prog, {"rx": 0.0, "tx": 0.0, "n": 0, "pid": pid})
        a["rx"] += up
        a["tx"] += dn
        a["n"] += 1
    return agg, unatt


def write_live(state, err, iface_, today_mb, talkers, unatt_kb):
    payload = {
        "state": state,
        "err": err,
        "iface": iface_,
        "today_mb": today_mb,
        "unatt_kb": round(unatt_kb),
        "ts": int(time.time()),
        "talkers": talkers,
    }
    tmp = LIVE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    os.replace(tmp, LIVE)


def main():
    c = connect()
    hot = {}          # prog -> consecutive hot seconds
    err_shown = set() # (kind) one-shot errors, e.g. missing sudoers
    today_total = 0.0
    today = ""

    while True:
        day = date.today().isoformat()
        if day != today:
            prune(c, day)
            today = day
            today_total = 0.0

        iface_ = default_iface()
        if not iface_:
            write_live("idle", "no default route (offline?)", "", today_total, [], 0)
            time.sleep(20)
            continue

        t0 = time.monotonic()
        try:
            proc = subprocess.run(
                ["timeout", str(CHUNK), "sudo", "-n", NETHOGS, "-t", "-d", "1", iface_],
                capture_output=True, text=True, timeout=CHUNK + 5,
            )
        except FileNotFoundError:
            write_live("error", "sudo not available — run: sudo pacman -S nethogs", iface_, today_total, [], 0)
            if "sudoers" not in err_shown:
                notify("critical", "WatchCat: cannot start", "sudo -n failed. Check /etc/sudoers.d/watchcat exists.")
                err_shown.add("sudoers")
            time.sleep(30)
            continue

        out = proc.stdout + proc.stderr
        first = (out.strip().splitlines() or [""])[0]
        if "password is required" in out or first.lower().startswith("sudo:"):
            write_live("error", "sudoers missing — add /etc/sudoers.d/watchcat (NOPASSWD nethogs)", iface_, today_total, [], 0)
            if "sudoers" not in err_shown:
                notify("critical", "WatchCat: sudo blocked", "sudo -n nethogs needs password. Install the sudoers.d/watchcat rule.")
                err_shown.add("sudoers")
            time.sleep(60)
            continue

        dt = min(30.0, max(1.0, time.monotonic() - t0))
        agg, unatt = parse(out.splitlines())
        if not agg and not out.strip():
            time.sleep(2)
            continue

        # day totals from this chunk
        rx = sum(a["rx"] / a["n"] for a in agg.values()) * dt / 1024.0
        tx = sum(a["tx"] / a["n"] for a in agg.values()) * dt / 1024.0
        today_total += rx + tx
        c.execute(
            "INSERT INTO day_total(day, rx_mb, tx_mb) VALUES(?,?,?)"
            " ON CONFLICT(day) DO UPDATE SET rx_mb=rx_mb+excluded.rx_mb, tx_mb=tx_mb+excluded.tx_mb",
            (day, rx, tx),
        )

        # per-proc accumulation + hot alerts
        talkers = []
        for prog, a in agg.items():
            r = a["rx"] / a["n"]
            t = a["tx"] / a["n"]
            rate = r + t
            peak = rate / 1024.0
            c.execute(
                "INSERT INTO day_proc(day, prog, rx_mb, tx_mb, peak_mb) VALUES(?,?,?,?,?)"
                " ON CONFLICT(day, prog) DO UPDATE SET"
                " rx_mb=rx_mb+excluded.rx_mb, tx_mb=tx_mb+excluded.tx_mb,"
                " peak_mb=CASE WHEN excluded.peak_mb>day_proc.peak_mb THEN excluded.peak_mb ELSE day_proc.peak_mb END",
                (day, prog, r * dt / 1024.0, t * dt / 1024.0, peak),
            )
            hot[prog] = hot[prog] + dt if rate >= HOT_KBS else 0.0
            if hot[prog] >= HOT_SECS and not sent_today(c, day, "hot", prog):
                c.execute("INSERT INTO sent(day, kind, prog) VALUES(?,?,?)", (day, "hot", prog))
                notify("critical", "WatchCat: %s hogging data" % prog,
                       "%.0f KB/s for %ds+ — on hotspot." % (rate, HOT_SECS))
            talkers.append({"prog": prog, "pid": a["pid"], "down": t, "up": r})
        talkers.sort(key=lambda x: x["down"] + x["up"], reverse=True)
        talkers = talkers[:15]

        # day warn/crit (once per day)
        for mb, kind, urg, title in (
            (WARN_MB, "warn", "normal", "WatchCat: %.0f MB used today" % WARN_MB),
            (CAP_MB, "crit", "critical", "WatchCat: 1 GB cap reached!"),
        ):
            if today_total >= mb and not sent_today(c, day, kind, "*"):
                c.execute("INSERT INTO sent(day, kind, prog) VALUES(?,?,?)", (day, kind, "*"))
                notify(urg, title, "Hotspot data used: %.0f MB." % today_total)

        c.commit()
        write_live("on", "", iface_, today_total, talkers, unatt)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)