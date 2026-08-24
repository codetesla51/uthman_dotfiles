import Quickshell.Io
import QtQuick

// CPU pill — glass island, secondary accent (waybar parity).
Item {
    id: root

    property var colors
    property bool hovered: cpuMouse.containsMouse
    signal openRequested()

    property int prevTotal: 0
    property int prevIdle: 0
    readonly property int usage: {
        if (prevTotal === 0) return 0
        var dTotal = curTotal - prevTotal
        var dIdle = curIdle - prevIdle
        if (dTotal <= 0) return lastUsage
        return Math.round(100 * (1 - dIdle / dTotal))
    }
    property int curTotal: 0
    property int curIdle: 0
    property int lastUsage: 0
    onUsageChanged: if (usage >= 0) lastUsage = usage

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 30

    Process {
        id: proc
        command: ["sh", "-c", "grep '^cpu ' /proc/stat"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var f = this.text.trim().split(/\s+/).slice(1).map(Number)
                if (f.length < 5) return
                var idle = f[3] + f[4]
                var total = f.reduce(function(a, b) { return a + b }, 0)
                root.prevIdle = root.curIdle
                root.prevTotal = root.curTotal
                root.curIdle = idle
                root.curTotal = total
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.8) : colors.alpha(colors.surface, 0.6)
        border.width: 1
        border.color: root.hovered ? colors.alpha(colors.secondary, 0.45) : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: "󰻠 " + root.usage + "%"
            color: root.hovered ? colors.foreground : colors.secondary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: cpuMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openRequested()
        }
    }
}
