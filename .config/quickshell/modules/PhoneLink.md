# PhoneLink — adb phone bridge

`PhoneLink.qml` is a standalone `FloatingWindow` popup and a thin client over
the `~/phonelink` backend (single-file Python CLI — all adb orchestration
lives there, so other UIs can build on the same commands). Toggle it with:

```bash
quickshell -p ~/.config/quickshell ipc call phonelink toggle
```

No background service of its own: the module shells out to `~/phonelink/phonelink`
one-shot subcommands and polls on timers. Pairing/config: `~/phonelink/init.sh`.

## What it does

- **Pair / connect** — remembers the last device from
  `~/.config/phonelink/config.ini ([phone] target)`. First-time pairing over USB:
  `adb tcpip 5555`, then reconnect over wifi. No gateway/hotspot guessing:
  the phone is a device on the LAN, not the router.
- **Send to phone** — drag files onto the drop tile; they are pushed via
  `adb push` (paths are shell-quoted). `c` sends the PC clipboard text via
  the bundled **PhoneRelay** flash app (`~/phonelink/android-app/`,
  `./init.sh` (builds + installs the APK, writes the config, smoke-tests)). The relay writes the clipboard while its invisible window flashes.
  Caveat: this ROM's clipboard watcher reaps clips the relay sets within
  ~seconds when idle — paste immediately, or use the share sheet for
  anything that isn't paste-now. The old adb-clip jar silently no-oped.
- **Phone → PC** — share from any phone app (WhatsApp, gallery, files): the
  share sheet lists *PhoneRelay*, which stores the item in
  `Download/PhoneLinkInbox/`, and an auto-delivery loop pulls every new
  file into `~/Downloads/` by itself (files already in Downloads with the
  same size are skipped; >250 MB stay in the browser). No clipboard read
  exists: foreground flash reads always return empty on this ROM even
  with the READ_CLIPBOARD appop granted (verified with paste-proof controls).
- **Screenshot** — `screencap` support exists (`shotPhone()`) but has no
  UI button since the snapshot chip was removed; re-add a chip or a `k`-key
  binding if wanted.
- **Ring my phone** — vibrating chip on the device strip: wakes the screen,
  maxes media volume, fires the ringtone-open intent and three hard vibration
  bursts. Volume + vibration are the proven carriers on this device (`media`
  tool, ringtones dir and shell notification posts were probed and ruled out;
  nothing on this build can force a sound).
- **Phone browser** — browse and pull files off the phone (see keys below).
- **Battery + status** — device row shows the paired phone and battery %,
  refreshed on a 15 s timer while the panel is open.
- **Notify forwarder** — every 4 s while a phone is paired it polls the
  notification shade and when a *new* notification appears from an
  allowlisted app it pings the desktop with `notify-send` (title + group-chat author, shown
  by quickshell's own NotificationCenter. The allowlist (`notifyApps` in
  PhoneLink.qml — package substring to app label) ships with WhatsApp,
  Telegram and SMS/messages entries and is trivial to extend. Works with
  phone DND on or off — DND silences the phone, it does not remove entries
  from the shade. The first scan after connecting absorbs whatever is
  already in the shade, so only genuinely new messages ping.

## Bandwidth

The full `dumpsys notification --noredact` dump is ~1 MB (~0.25 MB/s if
polled raw every 4 s, with multi-MB bursts per poll). The poll command
truncates the `Notification(...)` blob and greps on the phone side down to
~19 KB per poll (~5 KB/s sustained). A stale-poll watchdog kills any dump
hung past 10 s so a flaky-wifi hiccup cannot wedge the loop.

## Browser keys

| Key | Action |
|-----|--------|
| `j` / `k` | move down / up (k from no selection goes to the last row) |
| `l` / `Enter` | open folder, or pull a file |
| `p` | pull selected to ~/Downloads |
| `s` | toggle select (multi-select pull is incremental) |
| `y` | copy path to clipboard |
| `c` | send desktop clipboard to phone |
| `g` / `G` | first / last row |
| `h` | up a directory |
| `/` | type-ahead find (letters match prefix, Enter acts, Esc/1.2 s pauses to disarm) |
| `Esc` | clear search first, else close the panel |

Mouse: click a row to follow it; click the selected-count chip to act on the
selection.

## Implementation notes

- All `adb` invocations pass `-s <deviceId>` and shell-quote every path
  (`root.sq()`).
- The control card (media keys, brightness, buzz, DND) was deliberately
  removed; wifi/data toggles are deliberately absent too — toggling the link
  the module rides on severs the connection.
- The module reads `Quickshell.env("HOME")` for paths; failure modes are
  surfaced in the status line (adb missing, RSA prompt, wrong wifi subnet).

## Caveats

- Battery percentage is polled, so it can be stale by up to 15 s.
- Notify-forwarding matches any allowlisted package substring
  (this phone runs `com.whatsapp.w4b`; modded clients are covered too).
- Ringing is vibration-first; the alarm-intent path (`SET_ALARM` with
  `SKIP_UI`) is the upgrade if you want an actual siren — it leaves an armed
  alarm behind, so it is not wired in by default.