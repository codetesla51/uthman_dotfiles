import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Battery pill — glass island, foreground text; charging→secondary,
// warning→tertiary, critical→error (waybar parity).
Item {
    id: root

    property var colors
    property bool hovered: batMouse.containsMouse
    signal openRequested()

    readonly property var dev: UPower.displayDevice
    readonly property int capacity: dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.PendingCharge) : false
    readonly property bool full: dev ? dev.state === UPowerDeviceState.FullyCharged : false
    readonly property bool warning: capacity <= 30 && capacity > 15
    readonly property bool critical: capacity <= 15

    readonly property string icon: {
        var idx = Math.min(10, Math.max(0, Math.floor(capacity / 10)))
        return ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][idx]
    }

    implicitWidth: visible ? label.implicitWidth + 32 : 0
    implicitHeight: 30
    visible: dev !== null && dev !== undefined

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.75) : colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: root.critical ? colors.alpha(colors.error, 0.5)
                    : root.warning ? colors.alpha(colors.tertiary, 0.35)
                    : root.charging ? colors.alpha(colors.secondary, 0.35)
                    : root.hovered ? colors.alpha(colors.primary, 0.35)
                    : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.charging ? "󱐋 " + root.capacity + "%" : root.icon + " " + root.capacity + "%"
            color: root.critical ? colors.error
                 : root.warning ? colors.tertiary
                 : root.charging ? colors.secondary
                 : root.hovered ? colors.foreground
                 : colors.foreground
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: batMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openRequested()
        }
    }
}
