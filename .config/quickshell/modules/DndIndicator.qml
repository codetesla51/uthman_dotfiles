import Quickshell
import QtQuick

// DND indicator — moon glyph when do-not-disturb is on, hidden otherwise.
// Click toggles. Deliberately NOT tied to historyCount — the center bell
// already shows that (redundant badges annoyed user).
Item {
    id: root

    property var colors
    property bool dnd: false
    signal toggleRequested()

    readonly property bool hovered: dndMouse.containsMouse

    implicitWidth: label.implicitWidth + 20
    implicitHeight: 30
    visible: dnd

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.dnd ? colors.alpha(colors.error, 0.18)
                        : root.hovered ? colors.alpha(colors.surface, 0.8) : "transparent"
        border.width: 1
        border.color: root.dnd ? colors.alpha(colors.error, 0.4)
                               : root.hovered ? colors.alpha(colors.primary, 0.45)
                               : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.dnd ? "󰂛" : "󰂚"
            color: colors.error
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 13

            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: dndMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.toggleRequested()
        }
    }
}
