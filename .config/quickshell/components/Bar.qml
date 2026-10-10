import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../modules"

// Center trapezoid island tab (\_____/) hanging flush from the screen
// top — 8px rounded bottom corners, no border.
PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Auto
    implicitHeight: 54
    color: "transparent"
    WlrLayershell.namespace: "qs-bar"
    margins { top: 0; left: 8; right: 8 }

    property alias colors: palette
    property alias leftItems: leftRow.children
    property alias centerItems: islandRow.children
    property alias rightItems: rightRow.children

    Colors { id: palette }

    NotificationCenter { id: ntfy; colors: palette }

    // ---- resident panels: every popup stays loaded, zero RAM saved but
    // zero first-paint white flash (the battery lesson — lazy Loaders
    // stall the first frames while the tree builds). Panels self-gate
    // their timers/watchers on open, so idle cost is RAM only.
    // Bar owns each IPC target directly on the instance (panels must NOT
    // register the same target — see MonitorSettings lesson). Bar pills
    // call toggleX()/showX(); Hyprland binds call `ipc call <target> toggle`.

    // WifiPanel (1183 lines, heaviest) — Network pill + `wifi` bind
    WifiPanel { id: wifiPanel; colors: palette }
    IpcHandler { target: "wifi"; function toggle(): void { wifiPanel.open = !wifiPanel.open } }
    function toggleWifi() { wifiPanel.open = !wifiPanel.open }

    // SystemMonitor (544 lines) — Memory/Cpu pills + `sysmon` bind
    SystemMonitor { id: sysPanel; colors: palette }
    IpcHandler { target: "sysmon"; function toggle(): void { sysPanel.open = !sysPanel.open } }
    function showSysMon() { sysPanel.open = true }

    // BatteryPanel stays resident: opened constantly, and lazy-loading it
    // caused a first-paint white flash on open (surface maps before the
    // card finishes its entrance). ~10MB to never see that again.
    BatteryPanel { id: batPanel; colors: palette }

    // ClipboardPanel (577 lines) — `clipboard` bind. `sticky` too: the shelf
    // binds (SUPER ALT 1-4) fire snippets with no window — always loaded
    // now, so the actions run directly, never opening the panel.
    ClipboardPanel { id: clipPanel; colors: palette }
    IpcHandler { target: "clipboard"; function toggle(): void { clipPanel.open = !clipPanel.open } function close(): void { clipPanel.open = false } }
    IpcHandler {
        target: "sticky"
        function copy(slot: string): void { clipPanel.copyStickyBySlot(slot) }
        function pin(): void { clipPanel.addStickyFromClipboard() }
        function clearAll(): void { clipPanel.clearStickies() }
    }

    // ThemePanel (361 lines) — `theme` bind
    ThemePanel { id: themePanel; colors: palette }
    IpcHandler { target: "theme"; function toggle(): void { themePanel.open = !themePanel.open } }

    // FastFetchWindow (191 lines) — `fastfetch` bind
    FastFetchWindow { id: fetchPanel; colors: palette }
    IpcHandler { target: "fastfetch"; function toggle(): void { fetchPanel.open = !fetchPanel.open } }

    // ClockWindow (308 lines) — Clock pin + `clockwin` bind
    ClockWindow { id: clockPanel; colors: palette }
    IpcHandler { target: "clockwin"; function toggle(): void { clockPanel.open = !clockPanel.open } }
    function toggleClockWin() { clockPanel.open = !clockPanel.open }

    // ScreenTime (211 lines) — `screentime` bind
    ScreenTime { id: stPanel; colors: palette }
    IpcHandler { target: "screentime"; function toggle(): void { stPanel.open = !stPanel.open } }
    // PhoneBridge (1216 lines, 18 Process) — IPC-only, never pill-wired.
    // Panel owns target "phonebridge" itself, so NO Bar proxy here.
    // NOTE: inbox/notif watchers start on first open, not bar startup.
    PhoneBridge { id: phonePanel; colors: palette }
    // WhatsApp PARKED (ban caution, 2026-09-17): kept on disk, unwired so no daemon spawns.
    // WhatsApp { id: waPanel; colors: palette }
    // Launcher lives here (not shell.qml) so Bar pills/IPC can reach it —
    // and `plugins` (PluginMenu scrapped, all ten ride the launcher now).
    AppLauncher { id: launcherPanel; colors: palette }
    IpcHandler { target: "plugins"; function toggle(): void { launcherPanel.open = !launcherPanel.open } }

    // KeybindsPanel resident (battery treatment): lazy first-paint flashed
    // white — the list build stalls the first frames. Opened constantly,
    // so ~3MB resident to never see it again.
    KeybindsPanel { id: keysPanel; colors: palette }
    IpcHandler { target: "keybinds"; function toggle(): void { keysPanel.open = !keysPanel.open } }

    // DriveHealth (739 lines) — `drives` bind (+ `dbg` stays in panel)
    DriveHealth { id: drivesPanel; colors: palette }
    IpcHandler { target: "drives"; function toggle(): void { drivesPanel.open = !drivesPanel.open } }

    // WatchCatPanel (333 lines) — WatchCat pill + `watchcat` bind
    WatchCatPanel { id: wcPanel; colors: palette }
    IpcHandler { target: "watchcat"; function toggle(): void { wcPanel.open = !wcPanel.open } }
    function toggleWatchCat() { wcPanel.open = !wcPanel.open }

    // FailWatchPanel (320 lines) — `failwatch` bind
    FailWatchPanel { id: fwPanel; colors: palette }
    IpcHandler { target: "failwatch"; function toggle(): void { fwPanel.open = !fwPanel.open } }
    MediaOsd { id: mediaOsd; colors: palette }

    // bar sides toggle — SUPER SHIFT SPACE leaves middle island
    property bool barsVisible: true
    // center style — SUPER ALT SPACE flips trapezoid tab against the Dynamic Island
    property bool dynamicIsland: false
    // island hover swells the NowPlaying glass card; the linger timer keeps it from
    // flickering when the cursor cuts the corner between island and card
    property bool musicHover: false
    Timer {
        id: musicLinger
        interval: 250
        onTriggered: bar.musicHover = false
    }
    // SUPER ALT SPACE cinches the island down to a 44px dot and springs it
    // back open, so swapping trapezoid <-> capsule reads as one continuous
    // move instead of a hard swap. Notifications are the toast's job, not
    // the bar's.
    function pulseIsland() { growAnim.restart() }

    IpcHandler {
        target: "bar"
        function toggle(): void { bar.barsVisible = !bar.barsVisible }
        function toggleIsland(): void { bar.dynamicIsland = !bar.dynamicIsland; bar.pulseIsland() }
    }

    Item {
        id: content
        anchors.fill: parent

        RowLayout {
            id: leftRow
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 8 }
            spacing: 6
            opacity: bar.barsVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            transform: Translate { x: bar.barsVisible ? 0 : -40; Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
            ArchLogo { colors: bar.colors }
            Workspaces { colors: bar.colors }
        }

        // Trapezoid tab (\_____/) — soft 8px bottom corners, no border.
        // Top edge stays flush to the screen.
        Item {
            id: island
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            anchors.topMargin: 0
            property real naturalWidth: islandRow.implicitWidth + 40
            // growT 0 = cinched to a dot, 1 = natural. The grow animation
            // overshoots past 1 and settles, same as the reference easing.
            property real growT: 1
            width: 44 + (naturalWidth - 44) * growT
            height: 54
            // content-driven resizes stay smooth; the pulse owns growT
            Behavior on naturalWidth { NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
            // trapezoid geometry — rounded bottom corners
            readonly property real inset: 18         // horizontal inset of bottom edge
            readonly property real r: 14
            readonly property real len: Math.sqrt(inset*inset + height*height)
            readonly property real sx: inset / len
            readonly property real sy: height / len
            NumberAnimation {
                id: growAnim
                target: island; property: "growT"
                from: 0; to: 1; duration: 420
                easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.9, 0.3, 1.2]
            }
            // glow follows the music: album-art dominant hue while playing,
            // theme primary when idle — the line reads as a play indicator.
            // Near-black art is unreadable on the dark bar, so it blends
            // halfway toward primary (keeps the hue, guarantees light).
            function satFor(c, b) {
                var avg = (c.r + c.g + c.b) / 3
                return Qt.rgba(
                    Math.min(1, Math.max(0, avg + (c.r - avg) * b)),
                    Math.min(1, Math.max(0, avg + (c.g - avg) * b)),
                    Math.min(1, Math.max(0, avg + (c.b - avg) * b)), 1)
            }
            function glowFor(t) {
                var lum = 0.2126 * t.r + 0.7152 * t.g + 0.0722 * t.b
                var c = satFor(t, 1.6)
                if (lum < 0.10) {
                    var p = colors.primary
                    c = satFor(Qt.rgba((c.r + p.r) / 2, (c.g + p.g) / 2, (c.b + p.b) / 2, 1), 1.6)
                }
                // vivid enforcement: stretch dull browns/greys to a 0.35
                // channel spread; true grey has no hue — use primary instead
                var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b)
                var spread = mx - mn
                if (spread <= 0.02) return satFor(colors.primary, 1.6)
                if (spread < 0.35) {
                    var avg = (c.r + c.g + c.b) / 3, k = 0.35 / spread
                    return Qt.rgba(
                        Math.min(1, Math.max(0, avg + (c.r - avg) * k)),
                        Math.min(1, Math.max(0, avg + (c.g - avg) * k)),
                        Math.min(1, Math.max(0, avg + (c.b - avg) * k)), 1)
                }
                return c
            }
            readonly property color glowBase: nowPlaying.isPlaying ? glowFor(nowPlaying.trackColor) : colors.primary

            // Dynamic-Island capsule overlay (SUPER ALT SPACE minimal mode)
            Rectangle {
                opacity: bar.dynamicIsland ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                anchors.centerIn: parent
                width: island.width
                height: 40
                radius: height / 2
                color: colors.alpha(colors.background, 0.85)
                border.color: colors.alpha(colors.surfaceVariant, 0.8)
                border.width: 2
            }

            Shape {
                id: shp
                readonly property real f: 14   // flare size

                x: -f
                y: 0
                width: island.width + 2 * f
                height: island.height
                opacity: bar.dynamicIsland ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                antialiasing: true
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    // 0.6: frosted, not flat — Hyprland's `blur on, match:namespace qs-bar`
                    // layerrule blurs the wallpaper behind; this alpha lets it bite
                    fillColor: colors.alpha(colors.background, 0.6)
                    strokeColor: "transparent"
                    strokeWidth: 0

                    // every x below is offset by shp.f because the Shape starts at x = -f
                    startX: 0; startY: 0
                    PathLine { x: shp.width; y: 0 }

                    // top-right flare
                    PathQuad { controlX: shp.f + island.width; controlY: 0
                               x: shp.f + island.width - island.sx * shp.f; y: island.sy * shp.f }

                    // right slant, then rounded bottom corner
                    PathLine { x: shp.f + island.width - island.inset + island.sx * island.r
                               y: island.height - island.sy * island.r }
                    PathQuad { controlX: shp.f + island.width - island.inset; controlY: island.height
                               x: shp.f + island.width - island.inset - island.r; y: island.height }

                    // bottom edge
                    PathLine { x: shp.f + island.inset + island.r; y: island.height }

                    // left rounded corner, then slant up
                    PathQuad { controlX: shp.f + island.inset; controlY: island.height
                               x: shp.f + island.inset - island.sx * island.r; y: island.height - island.sy * island.r }
                    PathLine { x: shp.f + island.sx * shp.f; y: island.sy * shp.f }

                    // top-left flare
                    PathQuad { controlX: shp.f; controlY: 0; x: 0; y: 0 }
                }
            }

            RowLayout {
                id: islandRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                spacing: 10
                // clock small left
                Clock {
                    id: clockItem
                    colors: bar.colors
                    // smaller clock when NowPlaying is focus — keep time but de-emphasized
                    onPinRequested: toggleClockWin()
                }
                // hairline dividers — siblings, never children (§4);
                // 1x14 outline @ 0.28 per the island spec
                Rectangle {
                    width: 1; height: 14
                    color: colors.alpha(colors.outline, 0.28)
                    Layout.alignment: Qt.AlignVCenter
                }
                // NowPlaying focus — big centered, fills available width
                NowPlaying {
                    id: nowPlaying
                    colors: bar.colors
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 340
                    onHoverChanged: function(h) {
                        if (h) { musicLinger.stop(); bar.musicHover = true }
                        else musicLinger.restart()
                    }
                }
                Rectangle {
                    width: 1; height: 14
                    color: colors.alpha(colors.outline, 0.28)
                    Layout.alignment: Qt.AlignVCenter
                }
                // bell small right
                BellButton {
                    colors: bar.colors
                    historyCount: ntfy.historyCount
                    panelOpen: ntfy.panelOpen
                    onToggleRequested: ntfy.togglePanel()
                }
            }

            // island line (comet sweep): quiet dim hairline, one comet crosses
            // every 4s. No MouseArea: clicks pass through.
            Item {
                id: islandLine
                property real wavePhase: 0
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.leftMargin: island.inset + 8
                anchors.rightMargin: island.inset + 8
                anchors.topMargin: 0
                height: 11
                clip: true

                Rectangle {
                    y: 5
                    width: parent.width
                    height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.18; color: colors.alpha(island.glowBase, 0.35) }
                        GradientStop { position: 0.82; color: colors.alpha(island.glowBase, 0.35) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // smooth-scrolling intertwined sines: solid curves, traveling phase
                Timer {
                    interval: 66
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        islandLine.wavePhase += 0.28
                        waveCanvas.requestPaint()
                    }
                }
                Canvas {
                    id: waveCanvas
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 11
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var t = islandLine.wavePhase
                        var midY = 5.5
                        function wave(col, amp, waves, speed, lw) {
                            ctx.strokeStyle = col
                            ctx.lineWidth = lw
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            for (var x = 0; x <= width; x += 3) {
                                var y = midY + amp * Math.sin((x / width) * Math.PI * 2 * waves + t * speed)
                                if (x === 0) ctx.moveTo(x, y)
                                else ctx.lineTo(x, y)
                            }
                            ctx.stroke()
                        }
                        wave(colors.alpha(colors.primary, 0.8), 2.4, 2.5, 1.0, 1.2)
                        wave(colors.alpha(colors.secondary, 0.65), 1.8, 3.5, -1.3, 1.0)
                        wave(colors.alpha(colors.tertiary, 0.65), 1.3, 5.0, 0.7, 1.0)
                    }
                }
            }
        }

        RowLayout {
            id: rightRow
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 8; rightMargin: 6 }
            spacing: 6
            opacity: bar.barsVisible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            transform: Translate { x: bar.barsVisible ? 0 : 40; Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }

            // unified transient pill: idle · DND · recording · tray (LocalSend/OBS/etc.)
            // was 4 separate popping pills — now one glass pill, hidden when empty
            StatusPill {
                colors: bar.colors
                dnd: ntfy.dnd
                onToggleDndRequested: ntfy.toggleDnd()
            }
            Memory { colors: bar.colors; onOpenRequested: showSysMon() }
            Cpu { colors: bar.colors; onOpenRequested: showSysMon() }
            Network {
                colors: bar.colors
                onOpenRequested: toggleWifi()
            }
            WatchCat {
                colors: bar.colors
                onOpenRequested: toggleWatchCat()
            }
            Battery { colors: bar.colors; onOpenRequested: batPanel.open = !batPanel.open }
        }

    }
}
