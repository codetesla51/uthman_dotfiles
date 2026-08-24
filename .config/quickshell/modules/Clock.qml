import Quickshell
import QtQuick

// Clock — center island (waybar parity): surface .7, radius 16, primary color,
// weight 800, letter-spacing 1.2 → 2 on hover. Click toggles extended format.
Item {
    id: root

    property var colors
    property bool altFormat: false
    property bool hovered: clockMouse.containsMouse

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string time: clock.hours.toString().padStart(2, "0") + ":" + clock.minutes.toString().padStart(2, "0")
    readonly property var now: new Date()
    readonly property string extended: time + "  ·  " + Qt.formatDateTime(now, "dddd dd MMMM yyyy")

    implicitWidth: label.implicitWidth + 40
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.hovered ? colors.alpha(colors.surface, 0.85)
                            : colors.alpha(colors.surface, 0.7)
        border.width: 1
        border.color: root.hovered ? colors.alpha(colors.primary, 0.4)
                                   : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.altFormat ? root.extended : root.time
            color: colors.primary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 13
            font.weight: Font.ExtraBold
            font.letterSpacing: root.hovered ? 2 : 1.2
        }

        MouseArea {
            id: clockMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.altFormat = !root.altFormat
        }
    }
}
