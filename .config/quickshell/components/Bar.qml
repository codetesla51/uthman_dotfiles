import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "../modules"

// Glassmorphic floating island bar — mirrors waybar style.css:
// transparent canvas, side margins 8, individual glass pills.
// Window starts at y=0 and is 54 tall so the center island tab can hang
// flush from the physical screen top; the pill line itself sits at y 6..46.
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

    // ---- lazy popups: Loader + IPC proxy, zero RAM while closed ----
    // Pattern: bool owns visibility, proxy IpcHandler owns the IPC target
    // (panel files must NOT register the same target — see MonitorSettings
    // lesson), Loader instantiates on open, Connections unloads on close.
    // Bar pills call toggleX()/showX(); Hyprland binds call `ipc call <target> toggle`.

    // WifiPanel (1183 lines, heaviest) — Network pill + `wifi` bind
    property bool wifiOpen: false
    IpcHandler { target: "wifi"; function toggle(): void { wifiOpen = !wifiOpen } }
    function toggleWifi() { if (wifiLoader.item) wifiLoader.item.open = !wifiLoader.item.open; else wifiOpen = true }
    Loader {
        id: wifiLoader
        active: wifiOpen
        asynchronous: true
        source: "../modules/WifiPanel.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: wifiLoader.item
        function onOpenChanged() { if (wifiLoader.item && !wifiLoader.item.open) wifiOpen = false }
    }

    // SystemMonitor (544 lines) — Memory/Cpu pills + `sysmon` bind
    property bool sysOpen: false
    IpcHandler { target: "sysmon"; function toggle(): void { sysOpen = !sysOpen } }
    function showSysMon() { if (sysLoader.item) sysLoader.item.open = true; else sysOpen = true }
    Loader {
        id: sysLoader
        active: sysOpen
        asynchronous: true
        source: "../modules/SystemMonitor.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: sysLoader.item
        function onOpenChanged() { if (sysLoader.item && !sysLoader.item.open) sysOpen = false }
    }

    // BatteryPanel stays resident: opened constantly, and lazy-loading it
    // caused a first-paint white flash on open (surface maps before the
    // card finishes its entrance). ~10MB to never see that again.
    BatteryPanel { id: batPanel; colors: palette }

    // ClipboardPanel (577 lines) — `clipboard` bind. `sticky` too: the shelf
    // binds (SUPER ALT 1-4) must fire snippets with no window, so the proxy
    // runs the action headless — load, act, unload, never setting open.
    property bool clipOpen: false
    property string stickyAction: ""  // "copy:N" | "pin" | "clear" | ""
    IpcHandler { target: "clipboard"; function toggle(): void { clipOpen = !clipOpen } function close(): void { clipOpen = false } }
    IpcHandler {
        target: "sticky"
        function copy(slot: string): void { stickyCopy(slot) }
        function pin(): void { stickyPin() }
        function clearAll(): void { stickyClear() }
    }
    function stickyCopy(slot) {
        if (clipLoader.item) clipLoader.item.copyStickyBySlot(slot)
        else { stickyAction = "copy:" + slot; clipOpen = true }
    }
    function stickyPin() {
        if (clipLoader.item) clipLoader.item.addStickyFromClipboard()
        else { stickyAction = "pin"; clipOpen = true }
    }
    function stickyClear() {
        if (clipLoader.item) clipLoader.item.clearStickies()
        else { stickyAction = "clear"; clipOpen = true }
    }
    Loader {
        id: clipLoader
        active: clipOpen
        asynchronous: true
        source: "../modules/ClipboardPanel.qml"
        onLoaded: {
            item.colors = palette
            if (stickyAction !== "") {
                var a = stickyAction; stickyAction = ""
                if (a === "pin") item.addStickyFromClipboard()
                else if (a === "clear") item.clearStickies()
                else if (a.indexOf("copy:") === 0) item.copyStickyBySlot(a.slice(5))
                clipOpen = false
            } else {
                item.open = true
            }
        }
    }
    Connections {
        target: clipLoader.item
        function onOpenChanged() { if (clipLoader.item && !clipLoader.item.open) clipOpen = false }
    }

    // ThemePanel (361 lines) — `theme` bind
    property bool themeOpen: false
    IpcHandler { target: "theme"; function toggle(): void { themeOpen = !themeOpen } }
    Loader {
        id: themeLoader
        active: themeOpen
        asynchronous: true
        source: "../modules/ThemePanel.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: themeLoader.item
        function onOpenChanged() { if (themeLoader.item && !themeLoader.item.open) themeOpen = false }
    }

    // FastFetchWindow (191 lines) — `fastfetch` bind
    property bool fetchOpen: false
    IpcHandler { target: "fastfetch"; function toggle(): void { fetchOpen = !fetchOpen } }
    Loader {
        id: fetchLoader
        active: fetchOpen
        asynchronous: true
        source: "../modules/FastFetchWindow.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: fetchLoader.item
        function onOpenChanged() { if (fetchLoader.item && !fetchLoader.item.open) fetchOpen = false }
    }

    // ClockWindow (308 lines) — Clock pin + `clockwin` bind
    property bool clockOpen: false
    IpcHandler { target: "clockwin"; function toggle(): void { clockOpen = !clockOpen } }
    function toggleClockWin() { if (clockLoader.item) clockLoader.item.open = !clockLoader.item.open; else clockOpen = true }
    Loader {
        id: clockLoader
        active: clockOpen
        asynchronous: true
        source: "../modules/ClockWindow.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: clockLoader.item
        function onOpenChanged() { if (clockLoader.item && !clockLoader.item.open) clockOpen = false }
    }

    // ScreenTime (211 lines) — `screentime` bind
    property bool stOpen: false
    IpcHandler { target: "screentime"; function toggle(): void { stOpen = !stOpen } }
    Loader {
        id: stLoader
        active: stOpen
        asynchronous: true
        source: "../modules/ScreenTime.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: stLoader.item
        function onOpenChanged() { if (stLoader.item && !stLoader.item.open) stOpen = false }
    }
    // PhoneBridge (1216 lines, 18 Process) lazy: IPC-only, never pill-wired.
    // NOTE: inbox/notif watchers now start on first open, not bar startup.
    property bool phoneOpen: false
    IpcHandler { target: "phonebridge"; function toggle(): void { phoneOpen = !phoneOpen } }
    Loader {
        id: phoneLoader
        active: phoneOpen
        asynchronous: true
        source: "../modules/PhoneBridge.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: phoneLoader.item
        function onOpenChanged() { if (phoneLoader.item && !phoneLoader.item.open) phoneOpen = false }
    }
    // WhatsApp PARKED (ban caution, 2026-09-17): kept on disk, unwired so no daemon spawns.
    // WhatsApp { id: waPanel; colors: palette }
    // PluginMenu (324 lines) — `plugins` bind
    property bool pluginsOpen: false
    IpcHandler { target: "plugins"; function toggle(): void { pluginsOpen = !pluginsOpen } }
    Loader {
        id: pluginsLoader
        active: pluginsOpen
        asynchronous: true
        source: "../modules/PluginMenu.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: pluginsLoader.item
        function onOpenChanged() { if (pluginsLoader.item && !pluginsLoader.item.open) pluginsOpen = false }
    }

    // KeybindsPanel (260 lines) — `keybinds` bind
    property bool keysOpen: false
    IpcHandler { target: "keybinds"; function toggle(): void { keysOpen = !keysOpen } }
    Loader {
        id: keysLoader
        active: keysOpen
        asynchronous: true
        source: "../modules/KeybindsPanel.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: keysLoader.item
        function onOpenChanged() { if (keysLoader.item && !keysLoader.item.open) keysOpen = false }
    }

    // DriveHealth (739 lines) — `drives` bind (+ `dbg` stays in panel)
    property bool drivesOpen: false
    IpcHandler { target: "drives"; function toggle(): void { drivesOpen = !drivesOpen } }
    Loader {
        id: drivesLoader
        active: drivesOpen
        asynchronous: true
        source: "../modules/DriveHealth.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: drivesLoader.item
        function onOpenChanged() { if (drivesLoader.item && !drivesLoader.item.open) drivesOpen = false }
    }

    // WatchCatPanel (333 lines) — WatchCat pill + `watchcat` bind
    property bool wcOpen: false
    IpcHandler { target: "watchcat"; function toggle(): void { wcOpen = !wcOpen } }
    function toggleWatchCat() { if (wcLoader.item) wcLoader.item.open = !wcLoader.item.open; else wcOpen = true }
    Loader {
        id: wcLoader
        active: wcOpen
        asynchronous: true
        source: "../modules/WatchCatPanel.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: wcLoader.item
        function onOpenChanged() { if (wcLoader.item && !wcLoader.item.open) wcOpen = false }
    }

    // FailWatchPanel (320 lines) — `failwatch` bind
    property bool fwOpen: false
    IpcHandler { target: "failwatch"; function toggle(): void { fwOpen = !fwOpen } }
    Loader {
        id: fwLoader
        active: fwOpen
        asynchronous: true
        source: "../modules/FailWatchPanel.qml"
        onLoaded: { item.colors = palette; item.open = true }
    }
    Connections {
        target: fwLoader.item
        function onOpenChanged() { if (fwLoader.item && !fwLoader.item.open) fwOpen = false }
    }
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

        Item {
            id: island
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            anchors.topMargin: bar.dynamicIsland ? 7 : 0
            width: islandRow.implicitWidth + (bar.dynamicIsland ? 36 : 40)
            height: bar.dynamicIsland ? 40 : 54
            Behavior on anchors.topMargin { NumberAnimation { duration: 320; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
            Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
            // trapezoid geometry shared by fill + border — fixed rounding
            readonly property real inset: 18         // horizontal inset of bottom edge
            readonly property real cr: 8             // bottom corners (showing) — soft radius
            readonly property real tc: 0             // top corners (screen edge) — sharp, no curve
            readonly property real slantLen: Math.sqrt(inset*inset + (height-cr)*(height-cr))
            readonly property real ux: inset / slantLen
            readonly property real uy: (height-cr) / slantLen
            Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

            // Dynamic-Island capsule: floating black glass, no border
            Rectangle {
                opacity: bar.dynamicIsland ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                anchors.fill: parent
                radius: height / 2
                color: colors.alpha(colors.background, 0.82)
            }

            // trapezoid tab (\_____/) for the classic look
            Shape {
                opacity: bar.dynamicIsland ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                anchors.fill: parent
                antialiasing: true
                layer.enabled: true
                layer.samples: 4
                ShapePath {
                    fillColor: colors.alpha(colors.surface, 0.60)
                    strokeColor: "transparent"
                    strokeWidth: 0
                    startX: island.tc; startY: 0
                    PathLine { x: island.width - island.tc; y: 0 }
                    PathQuad { controlX: island.width; controlY: 0; x: island.width - island.ux*island.tc; y: island.uy*island.tc }
                    PathLine { x: island.width - island.inset; y: island.height - island.cr }
                    PathQuad { controlX: island.width - island.inset; controlY: island.height; x: island.width - island.inset - island.cr; y: island.height }
                    PathLine { x: island.inset + island.cr; y: island.height }
                    PathQuad { controlX: island.inset; controlY: island.height; x: island.inset; y: island.height - island.cr }
                    PathLine { x: island.ux*island.tc; y: island.uy*island.tc }
                    PathQuad { controlX: 0; controlY: 0; x: island.tc; y: 0 }
                }
            }

            RowLayout {
                id: islandRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: bar.dynamicIsland ? 0 : -1
                Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                spacing: 12
                // clock small left
                Clock {
                    id: clockItem
                    colors: bar.colors
                    // smaller clock when NowPlaying is focus — keep time but de-emphasized
                    onPinRequested: toggleClockWin()
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
