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
    PhoneLink { id: phoneLink; colors: palette }
    PluginMenu { id: pluginMenu; colors: palette }
    KeybindsPanel { id: keybindsPanel; colors: palette }
    MediaOsd { id: mediaOsd; colors: palette }

    CalendarPanel {
        id: calendarPanel
        colors: palette
        onCloseRequested: { bar.calendarPinned = false; calendarPanel.open = false }
    }

    // bar sides toggle — SUPER SHIFT SPACE leaves middle island
    property bool barsVisible: true
    IpcHandler { target: "bar"; function toggle(): void { bar.barsVisible = !bar.barsVisible } }

    // calendar — manual only, you control open/close (click clock or Super+C, Esc/backdrop to close)
    property bool calendarPinned: false
    onCalendarPinnedChanged: calendarPanel.open = calendarPinned
    IpcHandler { target: "calendar"; function toggle(): void { bar.calendarPinned = !bar.calendarPinned } }

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

        // middle cluster — true trapezoid tab (\_____/), flush with physical screen top.
        // No border: the fill alone defines the shape, slanted sides carved by Shape.
        Item {
            id: island
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            width: islandRow.implicitWidth + 40      // 20px padding per side (slant eats into it)
            height: 54                               // 46px pill line + 8px hang below
            // trapezoid geometry shared by fill + border — fixed rounding
            readonly property real inset: 18         // horizontal inset of bottom edge
            readonly property real cr: 12            // corner radius — reverted from 16, 16 was too bulbous with inset 20
            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    fillColor: colors.alpha(colors.surface, 0.60)
                    strokeColor: "transparent"
                    strokeWidth: 0
                    startX: 0; startY: 0
                    PathLine { x: island.width; y: 0 }
                    PathLine { x: island.width - island.inset; y: island.height - island.cr }
                    PathQuad { controlX: island.width - island.inset; controlY: island.height; x: island.width - island.inset - island.cr; y: island.height }
                    PathLine { x: island.inset + island.cr; y: island.height }
                    PathQuad { controlX: island.inset; controlY: island.height; x: island.inset; y: island.height - island.cr }
                }
                // hairline border — three visible edges only, never across the screen top;
                // protruding bottom angles get the same rounded corners as the fill
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: colors.alpha(colors.primary, 0.28)
                    strokeWidth: 1
                    startX: 0.5; startY: 0
                    PathLine { x: island.inset; y: island.height - island.cr }
                    PathQuad { controlX: island.inset; controlY: island.height - 0.5; x: island.inset + island.cr; y: island.height - 0.5 }
                    PathLine { x: island.width - island.inset - island.cr; y: island.height - 0.5 }
                    PathQuad { controlX: island.width - island.inset; controlY: island.height - 0.5; x: island.width - island.inset; y: island.height - island.cr }
                    PathLine { x: island.width - 0.5; y: 0 }
                }
            }

            RowLayout {
                id: islandRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                spacing: 14
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
                }
                // bell small right
                BellButton {
                    colors: bar.colors
                    historyCount: ntfy.historyCount
                    panelOpen: ntfy.panelOpen
                    onToggleRequested: ntfy.togglePanel()
                }
            }
        }

        RowLayout {
            id: rightRow
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 8 }
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
            Battery { colors: bar.colors; onOpenRequested: batPanel.open = !batPanel.open }
        }
    }
}
