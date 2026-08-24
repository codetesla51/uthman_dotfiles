import QtQuick

// Arch logo pill — waybar #custom-arch parity:
// 󰌽 glyph at 16px, primary color, glass island slightly brighter than others.
Item {
    id: root

    property var colors
    property bool hovered: logoMouse.containsMouse

    implicitWidth: label.implicitWidth + 26
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.85) : colors.alpha(colors.surface, 0.65)
        border.width: 1
        border.color: root.hovered ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: ""
            color: colors.primary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            id: logoMouse
            anchors.fill: parent
            hoverEnabled: true
        }
    }
}
