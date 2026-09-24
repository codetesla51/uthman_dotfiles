import Quickshell
import QtQuick

// Bell button — right edge of the center island. A quiet dot marks unread
// notifications; the fixed footprint keeps the bar from shifting with counts.
Item {
    id: root

    property var colors
    property int historyCount: 0
    property bool panelOpen: false
    signal toggleRequested()

    readonly property bool hovered: bellMouse.containsMouse
    scale: hovered ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 30

    // flat inside the trapezium — state lives in icon color only
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Text {
            id: label
            anchors.centerIn: parent
            text: ""
            color: root.panelOpen ? colors.primary
                 : root.historyCount > 0 ? colors.foreground
                 : colors.alpha(colors.outline, 0.9)
            font.family: "Phosphor"
            font.pixelSize: 13
        }

        // quiet unread marker — solid dot with an outer cut ring, punched
        // out of the bell's top-right corner (ring sits outside the dot)
        Item {
            visible: root.historyCount > 0
            anchors { right: label.right; top: label.top; rightMargin: -4; topMargin: -4 }
            width: 10
            height: 10

            Rectangle {
                anchors.fill: parent
                radius: 5
                color: colors.background
            }
            Rectangle {
                anchors.centerIn: parent
                width: 6
                height: 6
                radius: 3
                color: colors.error
            }
        }

        MouseArea {
            id: bellMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.toggleRequested()
        }
    }
}
