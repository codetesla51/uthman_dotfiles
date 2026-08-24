import Quickshell
import Quickshell.Io
import QtQuick

// Generic script indicator — waybar parity:
// inactive → fully transparent (hidden while text empty anyway);
// active → glass pill with colored text/border; blink for update-style states.
Item {
    id: root

    property var colors
    property string script: ""
    property int intervalMs: 5000
    property string clickCommand: ""
    property string activeClass: "active"
    property color activeColor: colors ? colors.tertiary : "#fff"
    property bool blink: false

    property string text: ""
    property string cls: ""
    readonly property bool isActive: cls === activeClass && cls !== ""

    implicitWidth: visible && text !== "" ? label.implicitWidth + 20 : 0
    implicitHeight: 30
    visible: text !== ""

    Process {
        id: proc
        command: ["sh", "-c", root.script]
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
        interval: root.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    SequentialAnimation on opacity {
        running: root.blink && root.isActive
        loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 750; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 750; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        visible: root.isActive
        color: colors.alpha(colors.surface, 0.6)
        border.width: 1
        border.color: colors.alpha(root.activeColor, 0.4)

        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: root.activeColor
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 13
        }

        MouseArea {
            id: indMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (root.clickCommand !== "")
                    Quickshell.execDetached(["sh", "-c", root.clickCommand])
                proc.running = true
            }
        }
    }
}
