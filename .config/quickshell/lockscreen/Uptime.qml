import Quickshell
import Quickshell.Io
import QtQuick

// Uptime — the machine's real uptime as the page's second loud number.
// One read a minute while the lock exists; no helper process, no cache.
Item {
    id: root

    property var theme

    property bool loaded: false
    property real uptimeSeconds: 0

    readonly property int days: Math.floor(root.uptimeSeconds / 86400)
    readonly property int hours: Math.floor((root.uptimeSeconds % 86400) / 3600)
    readonly property int minutes: Math.floor((root.uptimeSeconds % 3600) / 60)

    readonly property string value: {
        if (!root.loaded) return "—"
        if (root.days > 0) return root.days + "d " + root.hours + "h"
        if (root.hours > 0) return root.hours + "h " + ("0" + root.minutes).slice(-2) + "m"
        return root.minutes + "m"
    }

    readonly property string booted: {
        if (!root.loaded || root.uptimeSeconds <= 0) return ""
        var when = new Date(Date.now() - root.uptimeSeconds * 1000)
        return "booted " + Qt.formatDateTime(when, "ddd HH:mm")
    }

    Row {
        id: heading
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 7

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: ""
            size: 12
            tint: root.theme
                ? root.theme.alpha(root.theme.tertiary, 0.75) : "#8c8c8c"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Uptime"
            color: root.theme ? root.theme.muted : "#8c8c8c"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.headingSize : 10
            font.letterSpacing: root.theme ? root.theme.headingTracking : 1.4
            font.weight: Font.DemiBold
        }
    }

    Text {
        id: value
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.topMargin: 34
        text: root.value
        color: root.theme ? root.theme.tertiary : "#72d2fa"
        font.family: root.theme ? root.theme.clockFamily : "Iceberg"
        font.pixelSize: root.days >= 10
            ? (root.theme ? root.theme.uptimeValueSize * 0.82 : 75)
            : (root.theme ? root.theme.uptimeValueSize : 92)
        font.weight: Font.Light
        font.letterSpacing: -1
        elide: Text.ElideRight
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: value.bottom
        anchors.topMargin: 10
        spacing: 7

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: ""
            size: 11
            tint: root.theme ? root.theme.quiet : "#565656"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.booted
            color: root.theme ? root.theme.muted : "#8c8c8c"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.smallSize : 10
            font.letterSpacing: 0.3
        }
    }

    FileView {
        id: uptimeView
        path: "/proc/uptime"
        printErrors: false
        onLoaded: {
            var n = parseFloat(text())
            if (!isNaN(n)) {
                root.uptimeSeconds = n
                root.loaded = true
            }
        }
    }

    // Same-path FileView reads are no-ops; reset to empty first.
    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            uptimeView.path = ""
            uptimeView.path = "/proc/uptime"
        }
    }
}