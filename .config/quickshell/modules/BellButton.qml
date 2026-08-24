import Quickshell
import QtQuick

// Bell button — far-right of bar. Shows unread history count badge,
// click toggles the notification center drawer.
Item {
    id: root

    property var colors
    property int historyCount: 0
    property bool panelOpen: false
    signal toggleRequested()

    readonly property bool hovered: bellMouse.containsMouse
    scale: hovered ? 1.12 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    implicitWidth: label.implicitWidth + (historyCount > 0 ? 26 : 24)
    implicitHeight: 30

    // flat inside the trapezium — state lives in icon color only
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        Text {
            id: label
            anchors.centerIn: parent
            text: "󰂚"
            color: root.panelOpen ? colors.primary
                 : root.historyCount > 0 ? colors.foreground
                 : colors.alpha(colors.outline, 0.9)
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 13
        }

        // count badge
        Rectangle {
            visible: root.historyCount > 0
            anchors { right: parent.right; top: parent.top; margins: 3 }
            width: countText.implicitWidth + 6
            height: 12
            radius: 6
            color: colors.error

            Text {
                id: countText
                anchors.centerIn: parent
                text: root.historyCount > 99 ? "99" : root.historyCount
                color: colors.background
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 8
                font.weight: Font.Bold
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
