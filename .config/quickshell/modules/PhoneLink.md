# PhoneLink — adb phone bridge

`PhoneLink.qml` is a standalone `FloatingWindow` popup that talks to your phone over
`adb` (wifi or USB). Toggle it with:

```bash
quickshell -p ~/.config/quickshell ipc call phonelink toggle
```

No daemon, no background service: the module spawns one-shot child `Process`
objects that run `adb` on demand, and polls phone state on timers.

## What it does

- **Pair / connect** — remembers the last device from
  `~/.config/phone-sender/target`. First-time pairing over USB:
  `adb tcpip 5555`, then reconnect over wifi. No gateway/hotspot guessing:
  the phone is a device on the LAN, not the router.
- **Send to phone** — drag files onto the drop tile; they are pushed via
  `adb push` (paths are shell-quoted). `c` sends the clipboard
  (via the adb-clip java helper).
- **Screenshot** — camera chip on the device strip saves
  `~/Pictures/PhoneLink/phonelink-<timestamp>.png` via `exec-out screencap`.
- **Phone browser** — browse and pull files off the phone (see keys below).
- **Battery + status** — device row shows the paired phone and battery %,
  refreshed on a 15 s timer while the panel is open.
- **WhatsApp forwarder** — every 4 s while a phone is paired it polls
  `adb shell dumpsys notification --noredact`, and when a *new*
  `com.whatsapp.*` notification appears it pings the desktop with
  `notify-send` (title only), which quickshell's own NotificationCenter
  displays. Works with phone DND on or off — DND silences the phone, it does
  not remove entries from the shade. The first scan after connecting absorbs
  whatever is already in the shade, so only genuinely new messages ping.

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
- WhatsApp detection matches any package containing `whatsapp`
  (this phone runs `com.whatsapp.w4b`); other modded clients are covered too.