# AGENTS.md — How to Build Quickshell Modules in This Repo

> Read this before touching `~/dotfiles/.config/quickshell/`. It encodes every painful lesson from the waybar/swaync/walker migration and the WiFi panel build.

## 0. The Big Rule

**Everything lives inside quickshell.** One QML codebase, no separate programs/daemons/helpers.
New features = new `modules/*.qml` + an `IpcHandler` target. Shell launches as:

```bash
quickshell -p ~/.config/quickshell   # CANONICAL PATH — always
quickshell -p ~/.config/quickshell ipc call <target> toggle
```

Never use `-p .` or a realpath — Hyprland binds and the shell must use the **identical string**. Mismatched strings = `Target not found` even though a shell is running. `~/.config/quickshell` is a symlink to `~/dotfiles/.config/quickshell`; keep the string consistent everywhere (autostart, binds, manual `ipc` calls).

---

## 1. Project Layout

```
shell.qml              # ShellRoot — instantiates Bar + PowerMenu (and future panels)
components/
  Bar.qml              # left / center / right rows, wires pills → panels by id
  Colors.qml           # live Matugen palette watcher
modules/
  NetRate.qml          # reusable throughput sampler (/proc/net/dev, shared)
  WifiPanel.qml        # example of a full panel (see §3)
  NotificationCenter.qml / NotificationToast.qml
  PowerMenu.qml
  Battery.qml / Network.qml / etc.  # bar pills — thin, delegate to panels for detail
scripts/
  temperature.sh / update.sh / idle-indicators/idle.sh  # scripts the bar shells out to
colors.css             # Matugen output — FileView watches this
```

`shell.qml` is tiny — it just wires panels to a shared `Colors { id: barPalette }`. **Bar owns panel instances** (`WifiPanel { id: wifiPanel; colors: palette }` inside `Bar.qml`). That lets `Network { onOpenRequested: wifiPanel.open = !wifiPanel.open }` wire without IPC inside the shell. Panels also expose `IpcHandler { target: "wifi" }` so Hyprland binds can toggle them.

---

## 2. Icons — The \uXXXX Trap

**NEVER write `\uF0A28` escapes in any tool call that touches QML/JSON/Python.**
QML and the write/edit tools truncate at 4 hex digits (`\uF0A79` → `\uF0A7` + `9`).

Always write **literal Nerd Font glyphs** via Python:

```bash
python3 -c "open('modules/Foo.qml','w').write(chr(0xF04C4))"
# or in a patch script:
s = s.replace('\\uF04C4', chr(0xF04C4))
```

Verify after: `grep -P '\\\\u[0-9A-Fa-f]{4}' modules/*.qml` must return 0.

Verified glyphs present in `FiraCode Nerd Font` (checked via `fontTools.ttLib.TTFont.getBestCmap()`):
`F091C/F091D/F091E/F091F` (wifi strength), `F023` lock, `F00C` check, `F021` refresh, `F0156` close, `F04C4` speedometer, `F01DA` download, `F0552` upload. Always verify new codepoints against the font before using them.

---

## 3. Panel Pattern (The Only Correct Way)

Two sibling `PanelWindow`s **stack unpredictably** (Hyprland layer-shell sibling z-order is non-deterministic). The first WiFi attempt used a fullscreen click-catcher **above** the drawer — every button hit the catcher and closed the panel.

**Single-window pattern** (copy PowerMenu):

```qml
PanelWindow {
  id: root
  property var colors
  property bool open: false
  anchors { top:true; bottom:true; left:true; right:true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  focusable: true                 // grab keyboard so Esc works
  visible: root.open              // fully gone when closed — no invisible click blocker
  IpcHandler { target: "wifi"; function toggle(): void { root.open = !root.open } }

  // dim backdrop — inside SAME window, always below card
  Rectangle { anchors.fill: parent
    color: colors.alpha(colors.background, root.open ? 0.3 : 0)
    Behavior on color { ColorAnimation { duration: 200 } }
    MouseArea { anchors.fill: parent; onClicked: root.open = false }
  }

  // the card
  Rectangle { id: card
    anchors { top: parent.top; right: parent.right }
    anchors.topMargin: 52; anchors.rightMargin: 8   // hangs under bar
    width: 410; height: 640; radius: 16
    focus: root.open
    Keys.onEscapePressed: root.open = false
    transform: Translate { id: slide }             // slide-in
  }
}
```

**Convention:** every panel closes on `Esc` and on click-outside. Never use `anchors.fill` inside a `Layout`-managed item — use `Layout.alignment` instead (QML warns).

---

## 4. Spacing & Alignment — How This Repo Stays Crisp

Lessons from "upload/download not centered" + "address not aligned" + "hairline crossing":

* **Equal cells must be equal `Item`s** — to center download/upload, wrap each in `Item { Layout.fillWidth:true; Layout.fillHeight:true }` + inner `ColumnLayout { anchors.centerIn: parent }`. Never use `ColumnLayout { Layout.fillWidth }` directly for centered content — the two columns drift.
* **Indentation via shared rail** — IP address under SSID is `Layout.leftMargin: glyph.width + 8` where `glyph` is the `id` of the signal-strength Text in the row above. Guarantees pixel-perfect alignment.
* **Dividers are siblings, not children** — a `RowLayout { anchors.fill: parent }` with `Rectangle { width:1; height: parent.height - 20 }` between cells. Never nest the divider inside a cell.
* **No `anchors.*` inside a `Layout` child** — `Text { Layout.alignment: Qt.AlignHCenter }`, not `anchors.centerIn`. Verified by QML warning at `WifiPanel.qml:716`.
* **72 vs 0 brace drift** — incremental `sed` surgery once nested half the panel inside the 64px throughput strip. After any non-trivial edit, `python -c "d=sum(l.count('{')-l.count('}')...); print(d)"` must be `0`. Prefer wholesale rewrites over tail-brace patching.

---

## 5. Theming & Live Reload

* Matugen writes `~/.config/quickshell/colors.css` (configured in `~/dotfiles/.config/matugen/config.toml`).
* `Colors.qml` does **not** use `FileView.watchChanges` — matugen **replaces** the file (new inode) which silently breaks the watcher. Instead it **polls every 1s** and forces a fresh read:
  ```qml
  Timer { interval:1000; running:true; repeat:true; triggeredOnStart:true
    onTriggered: { devFile.path=""; devFile.path="/proc/net/dev" } }
  FileView { id: devFile; path:"/proc/net/dev"; onLoaded: /* parse */ }
  ```
  Same trick for `/proc/net/dev` (NetRate) and `colors.css`. Same assignment (`path = "/proc/net/dev"`) is a no-op — must reset to `""` first.

---

## 6. Networking API (Quickshell.Networking, iwd backend)

* `Networking.devices.values` → `WifiDevice`/`WiredDevice`. Filter by `d.type === DeviceType.Wifi`.
* `wifiDev.networks.values` → `WifiNetwork[]` with `name` (ssid), `signalStrength` (0-100), `security` (`WifiSecurityType.None` vs secured), `connected`, `known`, `address`.
* Sorting for the list: connected first, then known, then `signalStrength` descending.
* Connect: `net.connect()` (open or known) vs `net.connectWithPsk("password")` (secured+unknown). No `rescan()` method exists — toggle `wifiDev.scannerEnabled = false; ... = true`.
* Rescan spinner: `scannerEnabled` is always-on background flag, useless as signal. Drive a local `scanSpinning: bool` on click + `Timer { interval:4000 }` + `onNetsChanged` early-stop.

---

## 7. Throughput & Charts

* `modules/NetRate.qml` — parses `/proc/net/dev` every second (skip `lo`, sum rx_bytes field 0 + tx_bytes field 8). Exposes `rxKbs`, `txKbs`, `totalRxMb/totalTxMb`, `rxHistory: real[]` (40 samples), `fmt(kbs)` + `fmtTotal(mb)`.
* Sparkline: was a `Row { Repeater { delegate: Rectangle } }` — illegal `anchors.bottom` inside `Row` made it collapse. Correct as a `Canvas` line chart with fill:
  ```qml
  Canvas { anchors.fill: parent
    Connections { target: rate; function onRxHistoryChanged(){ canvas.requestPaint() } }
    onPaint: { /* maxV loop, px/py helpers, fill + stroke path */ }
  }
  ```
* Bar width overflow ("crossing") happened because 40 bars × (3+spacing) > 110px slot. Cap at 20 bars or normalize to available width.

---

## 8. Speed Test

Pure-QML download, no external programs:

```qml
var xhr = new XMLHttpRequest()
xhr.open("GET", "https://speed.cloudflare.com/__down?bytes=25000000", true)
var poll = Qt.createQmlObject("import QtQuick; Timer {}", root)
poll.interval = 200; poll.repeat = true
// poll: stProgress = got/25_000_000, push instantaneous inst = (got-prev)*8/dt/1e6 into stSamples[]
// onDone: speedMbps = bytes*8/secs/1e6, shownMbps = speedMbps, stProgress = 1
```

* Aesthetics that mattered to the user: eased big counter (`shownMbps += (raw-shown)*0.35` every poll tick), live self-drawing zig-zag of instantaneous samples (not cumulative avg), spinning loader **docked** (never scrolls), progress hairline width bound to `stProgress`. Earlier attempts put the chart below the scroll — it vanished. Fix: dock it in `stDock: Rectangle { anchors { left:right; bottom: parent.bottom } }` and give the main `ColumnLayout` a `anchors.bottom: stDock.top` reservation so the `ListView { Layout.fillHeight:true }` scrolls above it.

* Loader: first tried Canvas arc + `RotationAnimation on rotation` — Canvas never repainted, so no visible spin. Replaced with a plain `Text { text:""; RotationAnimation on rotation { running: root.speedTesting } }` — always spins.

---

## 9. Git & Dotfiles Hygiene

* Repo root is `~/dotfiles` (stow-style). `~/.config/hypr/*.conf` etc. are symlinks to `~/dotfiles/.config/hypr/*` — **except** `bindings.conf` was a real file diverged from dotfiles (two-brain problem caught via `diff`). Always keep `~/.config/hypr/bindings.conf -> ../../dotfiles/.config/hypr/bindings.conf`.
* `~/dotfiles/.config/quickshell/memory.md` is the session log — **never commit it**. `.gitignore` has `.config/quickshell/memory.md`.
* `colors.css`, `*Qt6QMLForBeginners*` etc. are generated / learning material — gitignored.

---

## 10. System UI Taste (What the User Actually Likes)

* **Rectangular, not square** — center menus are wide and short (520×200), not boxes. Pills are horizontal, evenly spaced, with the icon stacked *above* the label.
* **Glassmorphic, not flat** — `colors.alpha(surface, 0.5)` idle, `primary @ 0.14–0.16` on hover, `outline @ 0.12` border that lifts to `primary @ 0.4–0.5`. Backdrop dims to `background @ 0.3–0.55`.
* **Hover must move** — every interactive tile lifts (`y: -3`) and scales (`scale: 1.06`) with `Easing.OutCubic` 180ms, not just a color change. If it doesn't move, the user calls it dead.
* **8–14px spacing is religion** — 10px between siblings, 14px card padding, `height: 1` hairlines at `outline @ 0.12–0.15`. "Crossing" or cramped = instant reject.
* **8–18px radii** — pill 14, card 16–18, list row 10–12, divider never has a radius.
* **8–12px micro-type** — section labels are `9px @ outline 0.6 letterSpacing 1.5 Bold`, row bodies `11px Medium`, never larger.
* **8–12px vertical rhythm** — nothing ever touches an edge; even the backdrop has 8px right/top margins under the bar.
* When the user says "go all in" they mean: richer motion, more polish, more detail density — not "keep it minimal."
* **Center trapezium (current design)** — Bar window is `y=0, h=54` (`margins.top: 0`); QML can't paint above its own window, so flush-to-screen-top shapes need the window itself at y=0. Pill line stays at internal y 6..46 via row margins 6/8. The island is a `Shape` polygon (`\_____/`, 18px slant inset) with a hairline stroke ShapePath on the 3 lower edges only — never stroke the top edge. Island contents are FLAT (Clock/BellButton/NowPlaying have transparent bg, no inner pills), separated by 1×14 `outline@0.28` dividers. Spotify is filtered out of Tray via `hiddenApps` — NowPlaying covers media.

---

## 11. Copy-Paste Checklist for a New Panel

1. Copy `WifiPanel.qml`'s outer `PanelWindow` shell (backdrop + card).
2. Swap `target: "wifi"` → your name, update `Bar.qml`'s `WifiPanel { id: … }` and the pill's `signal openRequested()` → `panel.open = !panel.open`.
3. Add a Hyprland bind: `bindd = SUPER ALT, <key>, ..., exec, quickshell -p ~/.config/quickshell ipc call <target> toggle` then `hyprctl reload`.
4. Never add inline `anchors.*` inside a `Layout` child.
5. Never add inline `width: 2` twice on the same delegate (duplicate-property error at `[267:37]` style).
6. Verify via `pkill -x quickshell; setsid quickshell -p ~/.config/quickshell > /tmp/qs-bar.log 2>&1 &` → wait 4s → `grep -E 'ERROR|WARN' /tmp/qs-bar.log` must be empty (ignore accumulated session lines — hard-restart before judging).
7. `quickshell -p ~/.config/quickshell ipc show` must list the new target.

---

## 11. Scroll Done Right (ListView vs ScrollView)

**The failure:** Launcher showed 50 results but wheel did nothing. Two causes stacked:
1. `ListView { interactive: false }` — kills wheel/drag. The earlier drawer had the same.
2. `ScrollView { contentHeight: resultCol.implicitHeight }` with a manual `contentHeight` inside a `ColumnLayout` wrapper — the wrapper's `Layout.preferredHeight: min(7*56, count*56)` gave the view a fixed 392px viewport, but `contentHeight` was set to the column's `implicitHeight` (2800px) *after* the column had already been squeezed to 392px by the layout. Result: column never grew, nothing to scroll. Plus `ScrollBar.vertical.policy: ...` is invalid syntax — Controls2 wants `ScrollBar.vertical: ScrollBar { policy: ... }`.

**The working pattern — use ListView directly for lists:**

```qml
ListView {
  id: resultList
  Layout.fillWidth: true
  Layout.preferredHeight: Math.min(7*56, count*56) // 7 visible, rest scrolls
  clip: true
  model: filtered               // filtered is a var array, cap at 50: scored.slice(0,50)
  currentIndex: selected
  spacing: 4
  interactive: true             // NEVER false if you want wheel
  boundsBehavior: Flickable.StopAtBounds
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
  delegate: Rectangle { width: resultList.width; height: 52; ... }
}
```

* Verify before claiming fixed: add a temporary `IpcHandler` that logs `contentHeight`, `height`, `count`, `interactive`, then programmatically sets `contentY = 80` and checks it stuck. Example log that proves it:
  `filtered: 50 contentHeight: 2796 height: 392 count: 50 interactive: true → scroll test before: 0 after: 80 success: true`

**When to use ScrollView:** only for freeform content (like the notification drawer's `ColumnLayout + Repeater` where delegates aren't uniform). Then the recipe is:
```qml
ScrollView {
  Layout.fillWidth: true; Layout.preferredHeight: 392
  clip: true
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
  contentWidth: availableWidth
  contentHeight: col.implicitHeight
  ColumnLayout { id: col; width: parent.width; Repeater { ... } }
}
```
Never nest a `ListView` inside a `ScrollView`, and never put `anchors.*` inside a `Layout` child — use `Layout.alignment`.

