#!/usr/bin/env python3
"""failwatch-daemon.py — silent-failure watcher for FailWatch.

Watches what resource/process monitors miss:
  1. systemd failed units (system + user) — `systemctl --failed`
  2. journalctl errors — OOM killer, segfaults, kernel oops/BUG, failed starts

Sends notify-send alerts (caught by quickshell NotificationCenter) and writes
live.json for the FailWatch QML panel.

State: ~/.local/share/failwatch/{events.db,live.json,cursor}
Install: failwatch.service (systemd --user, in dotfiles/.config/systemd/user/)

Package integrity (pacman -Qkk) is intentionally NOT run here — slow and
mostly security-paranoia. The panel has an on-demand "verify packages" button.
"""
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
DATA = os.path.join(HOME, ".local/share/failwatch")
DB = os.path.join(DATA, "events.db")
LIVE = os.path.join(DATA, "live.json")
CURSOR_FILE = os.path.join(DATA, "cursor")
NOTIFY = "/usr/bin/notify-send"

POLL_FAILED = 30   # seconds between systemctl --failed checks
POLL_JOURNAL = 15  # seconds between journalctl checks
KEEP_DAYS = 7

# --- high-signal patterns only (everything else is ignored) ---
WATCH = [
    ("oom", re.compile(r"out of memory|oom-killer|killed process.*total-vm|invoked oom-killer", re.I)),
    ("segfault", re.compile(r"segfault at|general protection fault|trap .* error.*ip:|core dumped|aborted", re.I)),
    ("oops", re.compile(r"\boops\b|\bBUG\b|kernel panic|WARNING: CPU|I/O error|EXT4-fs error|nvme.*error|amdgpu.*(error|ring timeout)|drm.*flip.*timeout|hardware error|mce:|\bNMI\b", re.I)),
    ("unit-fail", re.compile(r"failed with result|failed to start|dependency failed|start request repeated too quickly|service hold-off time over", re.I)),
]

# Noise that matches WATCH textually but is never actionable — skip silently.
IGNORE = re.compile(
    r"Ignoring duplicate name|org\.freedesktop\.Notifications|FileManager1|"
    r"dunst\.service|swaync\.service|RTKit|RTTimeUSecMax|"
    r"xdg-desktop-portal.*Realtime|pam_unix.*session (opened|closed)",
    re.I,
)


def notify(urg, title, body):
    try:
        subprocess.Popen([NOTIFY, "-a", "FailWatch", "-u", urg, title, body])
    except OSError:
        pass


def connect():
    os.makedirs(DATA, exist_ok=True)
    c = sqlite3.connect(DB)
    c.execute(
        "CREATE TABLE IF NOT EXISTS events(id INTEGER PRIMARY KEY AUTOINCREMENT,"
        " ts TEXT, kind TEXT, unit TEXT, summary TEXT, detail TEXT, cursor TEXT)"
    )
    c.execute("CREATE TABLE IF NOT EXISTS sent(hash TEXT PRIMARY KEY, ts TEXT)")
    return c


def prune(c):
    cutoff = (datetime.now(timezone.utc) - timedelta(days=KEEP_DAYS)).isoformat()
    c.execute("DELETE FROM events WHERE ts < ?", (cutoff,))
    c.execute("DELETE FROM sent WHERE ts < ?", (cutoff,))


def seen(c, h):
    return c.execute("SELECT 1 FROM sent WHERE hash=?", (h,)).fetchone() is not None


def mark(c, h):
    c.execute(
        "INSERT OR IGNORE INTO sent(hash, ts) VALUES(?,?)",
        (h, datetime.now(timezone.utc).isoformat()),
    )


def failed_units(scope):
    """Return [{name, load, active, sub}] for failed units in scope."""
    cmd = ["systemctl", "--failed", "--no-legend", "--no-pager", "--plain"]
    if scope == "user":
        cmd = ["systemctl", "--user", "--failed", "--no-legend", "--no-pager", "--plain"]
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("0 loaded units"):
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        rows.append({"name": parts[0], "scope": scope, "load": parts[1],
                     "active": parts[2], "sub": parts[3]})
    return rows


def log_event(c, kind, unit, summary, detail, cursor):
    now = datetime.now(timezone.utc).isoformat()
    cur = c.execute(
        "INSERT INTO events(ts, kind, unit, summary, detail, cursor)"
        " VALUES(?,?,?,?,?,?)",
        (now, kind, unit or "", summary[:300], detail[:2000], cursor or ""),
    )
    return cur.lastrowid


def read_cursor():
    try:
        with open(CURSOR_FILE) as f:
            return f.read().strip()
    except OSError:
        return ""


def write_cursor(cur):
    tmp = CURSOR_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write(cur)
    os.replace(tmp, CURSOR_FILE)


def journal_new():
    """Return (entries, new_cursor). entries = list of json dicts since cursor.

    First run: seed cursor at now, return no entries (avoid backlog spam).
    """
    cur = read_cursor()
    if not cur:
        try:
            out = subprocess.check_output(
                ["journalctl", "--show-cursor", "-n", "0", "--no-pager"],
                text=True, stderr=subprocess.DEVNULL)
            m = re.search(r"cursor:\s*(\S+)", out)
            if m:
                write_cursor(m.group(1))
        except Exception:
            pass
        return [], read_cursor()
    try:
        out = subprocess.check_output(
            ["journalctl", "-o", "json", "--after-cursor", cur, "--no-pager",
             "-p", "warning", "-n", "500"],
            text=True, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        # stale cursor (rotated journal) — reseed
        try:
            os.remove(CURSOR_FILE)
        except OSError:
            pass
        return [], ""
    entries = []
    last = cur
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("__CURSOR"):
            last = e["__CURSOR"]
        entries.append(e)
    if last != cur:
        write_cursor(last)
    return entries, last


def classify(msg):
    if not msg or IGNORE.search(msg):
        return None
    for kind, rx in WATCH:
        if rx.search(msg):
            return kind
    return None


def fmt_ts(usec_str):
    try:
        dt = datetime.fromtimestamp(int(usec_str) / 1e6).astimezone()
        return dt.strftime("%m-%d %H:%M:%S")
    except Exception:
        return ""


def write_live(c, failed):
    recent = c.execute(
        "SELECT id, ts, kind, unit, summary, cursor FROM events"
        " ORDER BY id DESC LIMIT 30").fetchall()
    errors = [
        {"id": r[0], "ts": r[1], "kind": r[2], "unit": r[3],
         "summary": r[4], "cursor": r[5]}
        for r in recent
    ]
    day_ago = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()
    n24 = c.execute("SELECT COUNT(*) FROM events WHERE ts > ?",
                    (day_ago,)).fetchone()[0]
    payload = {
        "ts": int(time.time()),
        "failed": failed,
        "failed_count": len(failed),
        "errors": errors,
        "errors_24h": n24,
        "daemon_ok": True,
    }
    tmp = LIVE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    os.replace(tmp, LIVE)


def main():
    c = connect()
    prune(c)
    c.commit()
    last_failed = {}  # name -> row; notify only on NEW failures
    t_failed = 0.0
    Urg = {"oom": "critical", "oops": "critical", "unit-fail": "critical",
           "failed-unit": "critical", "segfault": "normal"}

    while True:
        now = time.monotonic()
        # --- 1. failed units ---
        if now - t_failed >= POLL_FAILED:
            t_failed = now
            failed = failed_units("system") + failed_units("user")
            cur_names = {u["name"] for u in failed}
            for u in failed:
                if u["name"] not in last_failed:
                    h = hashlib.sha256(
                        ("failed-unit:" + u["name"]).encode()).hexdigest()
                    if not seen(c, h):
                        eid = log_event(
                            c, "failed-unit", u["name"],
                            "%s failed (%s/%s)" % (u["name"], u["active"], u["sub"]),
                            "Unit %s [%s] is %s/%s.\nFull log: journalctl -u %s -b\nStatus: systemctl status %s"
                            % (u["name"], u["scope"], u["active"], u["sub"], u["name"], u["name"]),
                            "")
                        mark(c, h)
                        notify("critical", "FailWatch: %s failed" % u["name"],
                               "#%d · journalctl -u %s -b" % (eid, u["name"]))
            # recovered units: forget so a re-failure re-alerts
            for name in list(last_failed):
                if name not in cur_names:
                    last_failed.pop(name, None)
                    h = hashlib.sha256(("failed-unit:" + name).encode()).hexdigest()
                    c.execute("DELETE FROM sent WHERE hash=?", (h,))
            last_failed = {u["name"]: u for u in failed}
            c.commit()
        else:
            failed = list(last_failed.values())

        # --- 2. journal errors ---
        try:
            entries, _ = journal_new()
        except Exception:
            entries = []
        for e in entries:
            msg = e.get("MESSAGE", "")
            kind = classify(msg)
            if not kind:
                continue
            # a failed unit already emits its own failed-unit event with a
            # cleaner summary + `journalctl -u` command — skip the journal
            # echo so one crash = one notification, not two.
            if kind == "unit-fail":
                m = re.search(r"(\S+\.service)", msg)
                if m and m.group(1) in {u["name"] for u in failed}:
                    continue
            unit = e.get("_SYSTEMD_UNIT") or e.get("SYSLOG_IDENTIFIER") or ""
            h = hashlib.sha256(
                (kind + "|" + unit + "|" + msg[:200]).encode()).hexdigest()
            if seen(c, h):
                continue
            ts = fmt_ts(e.get("__REALTIME_TIMESTAMP", "0"))
            cursor = e.get("__CURSOR", "")
            summary = msg.strip().split("\n")[0][:200]
            detail = "%s\nunit: %s\nlog id: %s\nfull: journalctl --after-cursor='%s' --no-pager" % (
                msg.strip()[:1500], unit or "—", cursor[:27] or "—", cursor)
            eid = log_event(c, kind, unit, summary, detail, cursor)
            mark(c, h)
            notify(Urg.get(kind, "normal"),
                   "FailWatch: %s%s" % (kind, (" — " + unit) if unit else ""),
                   "#%d · %s" % (eid, summary[:120]))
        if entries:
            c.commit()

        write_live(c, failed)
        time.sleep(POLL_JOURNAL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
