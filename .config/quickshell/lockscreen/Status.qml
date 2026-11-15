import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import QtQuick

// Status — battery and wifi as icon + value pairs. Icons carry the
// meaning; the copy stays short. Caps Lock is left to the footer hint.
// The 900ms LED read exists only while the lock surface is alive.
Item {
    id: root

    property var theme
    property bool active: true
    property bool capsLock: false
    property string capsPath: ""
    property bool capsProbed: false

    readonly property var batteryDev: UPower.displayDevice
    readonly property int batteryPercent: batteryDev
        ? Math.round(batteryDev.percentage * 100) : -1
    readonly property bool charging: batteryDev
        ? (batteryDev.state === UPowerDeviceState.Charging
            || batteryDev.state === UPowerDeviceState.PendingCharge) : false

    readonly property var wifiDev: Networking.devices.values.find(
        function (d) { return d.type === DeviceType.Wifi }) || null
    readonly property bool wifiUp: wifiDev ? wifiDev.connected : false
    readonly property var wifiNet: {
        if (!wifiDev || !wifiDev.connected) return null
        var nets = wifiDev.networks ? wifiDev.networks.values : []
        return nets.find(function (n) { return n.connected }) || null
    }
    readonly property string wifiName: wifiNet ? (wifiNet.name || "").trim() : ""

    readonly property string batteryGlyph: root.charging
        ? "󰂄"
        : (root.batteryPercent >= 90 ? ""
            : root.batteryPercent >= 60 ? ""
            : root.batteryPercent >= 40 ? ""
            : root.batteryPercent >= 15 ? ""
            : "")

    implicitWidth: row.implicitWidth
    implicitHeight: 16

    Row {
        id: row
        spacing: 20

        Row {
            spacing: 6
            visible: root.batteryPercent >= 0

            Icon {
                theme: root.theme
                glyph: root.batteryGlyph
                size: 14
                tint: root.batteryPercent <= 15
                    ? (root.theme ? root.theme.error : "#ffb4ab")
                    : (root.charging
                        ? (root.theme ? root.theme.primary : "#ffffff")
                        : (root.theme ? root.theme.muted : "#8c8c8c"))
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.batteryPercent + "%"
                color: root.batteryPercent <= 15
                    ? (root.theme ? root.theme.error : "#ffb4ab")
                    : (root.theme ? root.theme.muted : "#8c8c8c")
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize : 10
                font.letterSpacing: 0.3
            }
        }

        Row {
            spacing: 6

            Icon {
                theme: root.theme
                glyph: root.wifiUp ? "" : "󰖪"
                size: 13
                tint: root.wifiUp
                    ? (root.theme ? root.theme.muted : "#8c8c8c")
                    : (root.theme ? root.theme.quiet : "#565656")
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.wifiUp
                    ? (root.wifiName !== "" ? root.wifiName : "wifi")
                    : "off"
                color: root.wifiUp
                    ? (root.theme ? root.theme.muted : "#8c8c8c")
                    : (root.theme ? root.theme.quiet : "#565656")
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize : 10
                font.letterSpacing: 0.3
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 170)
            }
        }

    }

    Process {
        id: findProc
        command: ["sh", "-c", "for f in /sys/class/leds/*capslock*/brightness; do [ -e \"$f\" ] && printf '%s' \"$f\" && exit 0; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.capsPath = text.trim()
        }
    }

    FileView {
        id: capsView
        path: root.capsPath
        printErrors: false
        onLoaded: root.capsLock = text().trim() === "1"
    }

    // Read the LED through FileView, not a shell process every second. The
    // path is discovered once; a path reset forces the cheap re-read.
    Timer {
        interval: 900
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (root.capsPath !== "") {
                capsView.path = ""
                capsView.path = root.capsPath
                return
            }
            if (!root.capsProbed) {
                root.capsProbed = true
                findProc.running = true
            }
        }
    }
}