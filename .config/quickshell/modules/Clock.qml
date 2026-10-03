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

    readonly property string hh: clock.hours.toString().padStart(2, "0")
    readonly property string mm: clock.minutes.toString().padStart(2, "0")
    readonly property string secs: clock.seconds.toString().padStart(2, "0")
    readonly property var now: new Date()
    readonly property string extended: hh + ":" + mm + "  ·  " + Qt.formatDateTime(now, "dddd dd MMMM yyyy")

    implicitWidth: timeRow.implicitWidth + 40
    implicitHeight: 30

    // flat inside the trapezium — hover lives in the letter-spacing only
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Row {
            id: timeRow
            anchors.centerIn: parent
            spacing: 0

            Text {
                visible: !root.altFormat
                anchors.verticalCenter: parent.verticalCenter
                text: root.hh
                color: colors.primary
                font.family: colors.fontSans
                font.pixelSize: 13
                font.weight: Font.ExtraBold
                font.letterSpacing: root.hovered ? 2 : 1.2
            }

            Text {
                visible: !root.altFormat
                anchors.verticalCenter: parent.verticalCenter
                text: ":"
                color: colors.primary
                font.family: colors.fontSans
                font.pixelSize: 13
                font.weight: Font.ExtraBold
                opacity: clock.seconds % 2 === 0 ? 1 : 0.25
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.altFormat ? root.extended : root.mm
                color: colors.primary
                font.family: colors.fontSans
                font.pixelSize: 13
                font.weight: Font.ExtraBold
                font.letterSpacing: root.hovered ? 2 : 1.2
            }

            Text {
                visible: !root.altFormat
                anchors.verticalCenter: parent.verticalCenter
                text: " " + root.secs
                color: colors.alpha(colors.outline, 0.55)
                font.family: colors.fontSans
                font.pixelSize: 9
                font.weight: Font.Bold
            }
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
