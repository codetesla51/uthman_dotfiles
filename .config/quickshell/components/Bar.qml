import Quickshell
import Quickshell.Io
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
    KeybindsPanel { id: keybindsPanel; colors: palette }

    CalendarPanel {
        id: calendarPanel
        colors: palette
        onCloseRequested: { bar.calendarPinned = false; calendarPanel.open = false }
    }

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
            Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            Shape {
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    fillColor: colors.alpha(colors.surface, 0.88)
                    strokeColor: "transparent"
                    strokeWidth: 0
                    startX: 0; startY: 0
                    PathLine { x: island.width; y: 0 }
                    PathLine { x: island.width - 18; y: island.height }
                    PathLine { x: 18; y: island.height }
                }
                // hairline border — three visible edges only, never across the screen top
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: colors.alpha(colors.primary, 0.28)
                    strokeWidth: 1
                    startX: 0.5; startY: 0
                    PathLine { x: 18.5; y: island.height - 0.5 }
                    PathLine { x: island.width - 18.5; y: island.height - 0.5 }
                    PathLine { x: island.width - 0.5; y: 0 }
                }
            }

            RowLayout {
                id: islandRow
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1     // center on the pill line (y=26), not the tab body
                spacing: 8
                Clock {
                    id: clockItem
                    colors: bar.colors
                    onPinRequested: bar.calendarPinned = !bar.calendarPinned
                }
                // | separators — flat content, no inner pills
                Rectangle { width: 1; height: 14; color: colors.alpha(colors.outline, 0.28) }
                NowPlaying {
                    id: nowPlaying
                    colors: bar.colors
                }
                Rectangle { width: 1; height: 14; color: colors.alpha(colors.outline, 0.28) }
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

            // waybar order: idle | dnd | update | tray | memory | temperature | cpu | network | battery
            ScriptIndicator {
                colors: bar.colors
                script: "$HOME/.config/quickshell/scripts/idle-indicators/idle.sh"
                intervalMs: 5000
                activeColor: colors.tertiary
                clickCommand: "omarchy-toggle-idle"
            }
            DndIndicator {
                colors: bar.colors
                dnd: ntfy.dnd
                onToggleRequested: ntfy.toggleDnd()
            }
            ScriptIndicator {
                colors: bar.colors
                script: "~/.config/quickshell/scripts/update.sh"
                intervalMs: 3600000
                activeClass: "pending"
                activeColor: colors.error
                blink: true
                clickCommand: "omarchy-update"
            }
            Tray { colors: bar.colors }
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
