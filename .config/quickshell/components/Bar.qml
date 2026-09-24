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

    WifiPanel { id: wifiPanel; colors: palette }
    SystemMonitor { id: sysMon; colors: palette }
    BatteryPanel { id: batPanel; colors: palette }
    ClipboardPanel { id: clipPanel; colors: palette }
    ThemePanel { id: themePanel; colors: palette }
    FastFetchWindow { id: fastFetch; colors: palette }
    ClockWindow { id: clockWin; colors: palette }
    ScreenTime { id: screenTime; colors: palette }
    PhoneBridge { id: phoneLink; colors: palette }
    // WhatsApp PARKED (ban caution, 2026-09-17): kept on disk, unwired so no daemon spawns.
    // WhatsApp { id: waPanel; colors: palette }
    PluginMenu { id: pluginMenu; colors: palette }
    KeybindsPanel { id: keybindsPanel; colors: palette }
    DriveHealth { id: driveHealth; colors: palette }
    WatchCatPanel { id: watchCat; colors: palette }
    FailWatchPanel { id: failWatch; colors: palette }
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
                    onPinRequested: clockWin.open = !clockWin.open
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

            // island number line — short ruled segment under the row, two glow
            // dots travelling within the island. No MouseArea: clicks pass through.
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
                    color: colors.alpha(colors.primary, 0.30)
                }

                Repeater {
                    model: Math.max(0, Math.floor(parent.width / 28))
                    Rectangle {
                        x: index * 28
                        y: 4
                        width: 1
                        height: 3
                        color: colors.alpha(colors.primary, 0.30)
                    }
                }

                Repeater {
                    model: 2
                    Item {
                        width: 11
                        height: 11

                        Rectangle {
                            anchors.centerIn: parent
                            width: 11
                            height: 11
                            radius: 5.5
                            color: colors.alpha(colors.primary, 0.10)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 7
                            height: 7
                            radius: 3.5
                            color: colors.alpha(colors.primary, 0.25)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 4
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.primary, 0.95)
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
            Memory { colors: bar.colors; onOpenRequested: sysMon.open = true }
            Temp { colors: bar.colors }
            Cpu { colors: bar.colors; onOpenRequested: sysMon.open = true }
            Network {
                colors: bar.colors
                onOpenRequested: wifiPanel.open = !wifiPanel.open
            }
            WatchCat {
                colors: bar.colors
                onOpenRequested: watchCat.open = !watchCat.open
            }
            Battery { colors: bar.colors; onOpenRequested: batPanel.open = !batPanel.open }
        }

    }
}
