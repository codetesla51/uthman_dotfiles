import Quickshell
import Quickshell.Io
import QtQuick

// FailWatch pill — silent-failure watchdog. Shows failed-unit + journal-error
// counts from the failwatch.service daemon (scripts/failwatch-daemon.py).
// Green check when clean, red when units failed, amber on journal errors.
// Click opens the FailWatch panel — it doesn't log, the daemon does.
Item {
    id: root

    property var colors
    property bool hovered: fwMouse.containsMouse
    signal openRequested()

    property int failedCount: 0
    property int errors24h: 0
    property string daemonState: "loading" // loading | on | error
    property string daemonErr: ""

    readonly property int total: root.failedCount + root.errors24h
    readonly property bool bad: root.failedCount > 0
    readonly property bool warn: !root.bad && root.errors24h > 0

    function poll() {
        if (pollBusy) return
        pollBusy = true
        var home = Quickshell.env("HOME")
        pollProc.command = ["cat", home + "/.local/share/failwatch/live.json"]
        pollProc.running = true
    }
    property bool pollBusy: false
    Process {
        id: pollProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.pollBusy = false
                if (text.indexOf("{") === 0) {
                    try {
                        var d = JSON.parse(text)
                        root.failedCount = d.failed_count || 0
                        root.errors24h = d.errors_24h || 0
                        root.daemonState = "on"
                        root.daemonErr = ""
                    } catch (e) {
                        root.daemonState = "error"
                        root.daemonErr = "live.json parse failed"
                    }
                } else {
                    root.daemonState = "error"
                    root.daemonErr = "daemon off — systemctl --user start failwatch"
                }
            }
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    implicitWidth: label.implicitWidth + 32
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.hovered ? colors.alpha(colors.surface, 0.75) : colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: root.daemonState === "error" ? colors.alpha(colors.outline, 0.3)
                    : root.bad ? colors.alpha(colors.error, 0.55)
                    : root.warn ? colors.alpha(colors.primary, 0.5)
                    : root.hovered ? colors.alpha(colors.secondary, 0.45)
                    : colors.alpha(colors.outline, 0.15)

        Behavior on color { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Text {
            id: label
            anchors.centerIn: parent
            text: root.daemonState === "error" ? "FW ?"
                : root.total === 0 ? "FW ok"
                : "FW " + root.total
            color: root.bad ? colors.error
                : root.warn ? colors.primary
                : root.hovered ? colors.foreground : colors.secondary
            font.family: colors.fontSans
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        MouseArea {
            id: fwMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.openRequested()
        }
    }
}
