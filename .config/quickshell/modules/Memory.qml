import Quickshell.Io
import QtQuick

// Memory pill — glass island, tertiary accent (waybar parity).
Item {
    id: root

    property var colors
    property bool hovered: memMouse.containsMouse
    signal openRequested()

    property real totalGB: 0
    property real usedGB: 0
    readonly property int pct: totalGB > 0 ? Math.round(100 * usedGB / totalGB) : 0

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 30

    Process {
        id: proc
        command: ["sh", "-c", "grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                var vals = {}
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split(":")
                    if (p.length === 2) vals[p[0]] = parseInt(p[1].trim())
                }
                if (vals["MemTotal"] > 0 && vals["MemAvailable"] >= 0) {
                    root.totalGB = vals["MemTotal"] / 1048576
                    root.usedGB = (vals["MemTotal"] - vals["MemAvailable"]) / 1048576
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.75) : colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: root.hovered ? colors.alpha(colors.tertiary, 0.45) : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: "󰍛 " + root.pct + "%"
            color: root.hovered ? colors.foreground : colors.tertiary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: memMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openRequested()
        }
    }
}
