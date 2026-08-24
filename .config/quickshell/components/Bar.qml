import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../modules"

// Glassmorphic floating island bar — mirrors waybar style.css:
// transparent canvas, top margin 6, side margins 8, individual glass pills.
PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    exclusionMode: ExclusionMode.Auto
    implicitHeight: 40
    color: "transparent"
    margins { top: 6; left: 8; right: 8 }

    property alias colors: palette
    property alias leftItems: leftRow.children
    property alias centerItems: centerRow.children
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
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            spacing: 6
            ArchLogo { colors: bar.colors }
            Workspaces { colors: bar.colors }
        }

        RowLayout {
            id: centerRow
            anchors.centerIn: parent
            spacing: 10
            Clock {
                id: clockItem
                colors: bar.colors
                onPinRequested: bar.calendarPinned = !bar.calendarPinned
            }
            BellButton {
                colors: bar.colors
                historyCount: ntfy.historyCount
                panelOpen: ntfy.panelOpen
                onToggleRequested: ntfy.togglePanel()
            }
        }

        RowLayout {
            id: rightRow
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
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
