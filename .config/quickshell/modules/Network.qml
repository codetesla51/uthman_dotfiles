import Quickshell
import Quickshell.Networking
import QtQuick

// Network pill — glass island, primary accent; disconnected → error (waybar parity).
Item {
    id: root

    property var colors
    property bool hovered: netMouse.containsMouse
    signal openRequested()

    readonly property var devices: Networking.devices.values
    readonly property var wifiDev: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDev: devices.find(d => d.type === DeviceType.Wired) ?? null
    readonly property bool ethUp: wiredDev ? wiredDev.hasLink && wiredDev.connected : false
    readonly property var wifiNet: {
        if (!wifiDev || !wifiDev.connected) return null
        var nets = wifiDev.networks ? wifiDev.networks.values : []
        return nets.find(n => n.connected) ?? null
    }
    readonly property string essid: wifiNet ? (wifiNet.name ?? "").trim() : ""
    readonly property bool disconnected: !ethUp && essid === ""

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.8) : colors.alpha(colors.surface, 0.6)
        border.width: 1
        border.color: root.disconnected ? colors.alpha(colors.error, 0.3)
                    : root.hovered ? colors.alpha(colors.primary, 0.45)
                    : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.ethUp ? "󰈀 Ethernet"
                : root.essid !== "" ? "󰖩 " + root.essid
                : "󰖪 Off"
            color: root.disconnected ? colors.error
                 : root.hovered ? colors.foreground
                 : colors.primary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: netMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openRequested()
        }
    }
}
