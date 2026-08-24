import Quickshell
import QtQuick

// Clock — center island (waybar parity): surface .7, radius 16, primary color,
// weight 800, letter-spacing 1.2 → 2 on hover. Click toggles extended format.
Item {
    id: root

    property var colors
    property bool altFormat: false
    property bool hovered: clockMouse.containsMouse
    signal pinRequested()

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string time: clock.hours.toString().padStart(2, "0") + ":" + clock.minutes.toString().padStart(2, "0")
    readonly property var now: new Date()
    readonly property string extended: time + "  ·  " + Qt.formatDateTime(now, "dddd dd MMMM yyyy")

    implicitWidth: label.implicitWidth + 40
    implicitHeight: 30

    // flat inside the trapezium — hover lives in the letter-spacing only
    Rectangle {
        anchors.fill: parent
        color: "transparent"

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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse){
                if (mouse.button === Qt.RightButton) root.altFormat = !root.altFormat
                else root.pinRequested()
            }
        }
    }
}
