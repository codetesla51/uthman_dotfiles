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

    implicitWidth: label.implicitWidth + (historyCount > 0 ? 26 : 24)
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.panelOpen || root.hovered ? colors.alpha(colors.surface, 0.8)
                                              : colors.alpha(colors.surface, 0.6)
        border.width: 1
        border.color: root.panelOpen ? colors.alpha(colors.primary, 0.45)
                    : root.hovered ? colors.alpha(colors.primary, 0.45)
                    : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

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
