import Quickshell
import Quickshell.Io
import QtQuick

// AudioVisualizer — small draggable desktop cava window with rounded pill bars.
// cava raw/ascii mode streams "v;v;v;..." frames on stdout (headless-safe,
// no terminal needed); we render them as frosted-glass pill bars with a
// matugen gradient. Toggle: ipc call visualizer.
FloatingWindow {
    id: root

    property var colors
    property bool open: true
    readonly property int bars: 32
    property var levels: []

    title: "Cava"
    implicitWidth: 360
    implicitHeight: 120
    color: "transparent"
    visible: root.open

    IpcHandler { target: "visualizer"; function toggle(): void { root.open = !root.open } }

    function apply(line) {
        var parts = line.trim().split(";")
        if (parts.length < bars) return
        var arr = new Array(bars)
        for (var i = 0; i < bars; i++)
            arr[i] = Math.max(0, Math.min(100, parseInt(parts[i]) || 0))
        levels = arr
    }

    Process {
        id: cavaProc
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/scripts/cava-qs.conf"]
        running: root.visible
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.apply(line)
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        color: colors.alpha(colors.surface, 0.50)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.20)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            id: barRow
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 16
            anchors.top: parent.top
            anchors.topMargin: 16
            spacing: 4

            Repeater {
                model: root.bars

                delegate: Rectangle {
                    id: bar
                    required property int index
                    readonly property real v: (root.levels[index] || 0) / 100
                    width: (barRow.width - (root.bars - 1) * barRow.spacing) / root.bars
                    height: Math.max(4, barRow.height * v)
                    radius: width / 2
                    anchors.bottom: barRow.bottom
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: colors.primary }
                        GradientStop { position: 1; color: colors.tertiary }
                    }
                    Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                }
            }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
