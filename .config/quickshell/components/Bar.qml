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
    IpcHandler {
        target: "bar"
        function toggle(): void { bar.barsVisible = !bar.barsVisible }
        function toggleIsland(): void { bar.dynamicIsland = !bar.dynamicIsland }
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
            width: islandRow.implicitWidth + 40
            height: 54
            // trapezoid geometry — fixed rounding
            readonly property real inset: 18         // horizontal inset of bottom edge
            readonly property real cr: 8             // bottom corners (showing) — soft radius
            readonly property real tc: 0             // top corners sharp at the screen edge
            readonly property real slantLen: Math.sqrt(inset*inset + (height-cr)*(height-cr))
            readonly property real ux: inset / slantLen
            readonly property real uy: (height-cr) / slantLen
            Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

            // Dynamic-Island capsule overlay (SUPER ALT SPACE minimal mode)
            Rectangle {
                opacity: bar.dynamicIsland ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                anchors.centerIn: parent
                width: islandRow.implicitWidth + 36
                height: 40
                radius: height / 2
                color: colors.alpha(colors.background, 0.85)
                border.color: colors.alpha(colors.surfaceVariant, 0.8)
                border.width: 2
            }

            Shape {
                opacity: bar.dynamicIsland ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                anchors.fill: parent
                antialiasing: true
                layer.enabled: true
                layer.samples: 4
                ShapePath {
                    // 0.6: frosted, not flat — Hyprland's `blur on, match:namespace qs-bar`
                    // layerrule blurs the wallpaper behind; this alpha lets it bite
                    fillColor: colors.alpha(colors.background, 0.6)
                    strokeColor: "transparent"
                    strokeWidth: 0
                    startX: island.tc; startY: 0
                    PathLine { x: island.width - island.tc; y: 0 }
                    // top corners scoop inward (cove) — control sits inside
                    // the shape, so the curve bites in instead of bulging out
                    PathQuad { controlX: island.width - island.tc*(1+island.ux)*0.9; controlY: island.uy*island.tc*0.9; x: island.width - island.ux*island.tc; y: island.uy*island.tc }
                    PathLine { x: island.width - island.inset; y: island.height - island.cr }
                    PathQuad { controlX: island.width - island.inset; controlY: island.height; x: island.width - island.inset - island.cr; y: island.height }
                    PathLine { x: island.inset + island.cr; y: island.height }
                    PathQuad { controlX: island.inset; controlY: island.height; x: island.inset; y: island.height - island.cr }
                    PathLine { x: island.ux*island.tc; y: island.uy*island.tc }
                    PathQuad { controlX: island.tc*(1+island.ux)*0.9; controlY: island.uy*island.tc*0.9; x: island.tc; y: 0 }
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

            // island number line — short ruled segment crowning the island, two
            // glow dots travelling within it. No MouseArea: clicks pass through.
            Item {
                id: islandLine
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
                        GradientStop { position: 0.18; color: colors.alpha(colors.primary, 0.30) }
                        GradientStop { position: 0.82; color: colors.alpha(colors.primary, 0.30) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                Repeater {
                    model: Math.max(0, Math.floor(parent.width / 28))
                    Rectangle {
                        x: index * 28
                        y: 4
                        width: 1
                        height: 3
                        color: colors.alpha(colors.primary, 0.16)
                    }
                }

                Repeater {
                    model: 2
                    Item {
                        width: 11
                        height: 11

                        // trailer dot runs dimmer — comet feel, lead dot burns
                        readonly property real glow: index === 0 ? 1.0 : 0.55

                        Rectangle {
                            anchors.centerIn: parent
                            width: 11
                            height: 11
                            radius: 5.5
                            color: colors.alpha(colors.primary, 0.10 * glow)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 7
                            height: 7
                            radius: 3.5
                            color: colors.alpha(colors.primary, 0.25 * glow)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 4
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.primary, 0.95 * glow)

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { from: 0.7; to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1.0; to: 0.7; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }

                        SequentialAnimation on x {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 1500 }
                            NumberAnimation {
                                from: -11
                                to: islandLine.width + 11
                                duration: 3000
                                easing.type: Easing.Linear
                            }
                            PauseAnimation { duration: (1 - index) * 1500 }
                        }
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
