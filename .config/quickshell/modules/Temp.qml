import Quickshell
import Quickshell.Io
import QtQuick

// Temperature pill — glass island, foreground text; warning→tertiary,
// critical→error + blink (waybar parity). Reuses the same script.
Item {
    id: root

    property var colors
    property bool hovered: tempMouse.containsMouse

    property string text: ""
    property string cls: ""
    readonly property bool warning: cls === "warning"
    readonly property bool critical: cls === "critical"

    implicitWidth: visible ? label.implicitWidth + 32 : 0
    implicitHeight: 30
    visible: text !== ""

    Process {
        id: proc
        command: ["sh", Quickshell.env("HOME") + "/.config/quickshell/scripts/temperature.sh"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    root.text = j.text ?? ""
                    root.cls = j.class ?? ""
                } catch (e) {
                    root.text = ""
                    root.cls = ""
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

    // critical blink (waybar @keyframes blink)
    SequentialAnimation on opacity {
        running: root.critical
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.75) : colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: root.critical ? colors.alpha(colors.error, 0.5)
                    : root.warning ? colors.alpha(colors.tertiary, 0.4)
                    : root.hovered ? colors.alpha(colors.primary, 0.45)
                    : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: root.critical ? colors.error
                 : root.warning ? colors.tertiary
                 : root.hovered ? colors.foreground
                 : colors.foreground
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: tempMouse
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
