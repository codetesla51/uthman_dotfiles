import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// WatchCat — hotspot data watchdog panel. SUPER ALT Y or `ipc call watchcat toggle`.
// The heavy lifting lives in the systemd user service `watchcat.service`
// (scripts/watchcat-daemon.py): it runs nethogs 24/7 via passwordless sudo
// (sudoers.d/watchcat), accumulates into ~/.local/share/watchcat/daemon.db,
// sends alerts, and writes live.json. This panel only READS live.json (plus
// the pill's NetRate deltas for live interface speed) — no nethogs, no sudo,
// no LocalStorage here. Dashboard is a static HTML file from the DB.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    // live state (from daemon live.json)
    property var talkers: []          // [{prog, pid, down, up}]
    property string liveState: "loading" // loading | on | idle | error
    property string liveErr: ""
    property string iface: ""
    property real todayMb: 0
    property real unattKb: 0

    title: "WatchCat"
    implicitWidth: 700
    implicitHeight: 380
    minimumSize: Qt.size(560, 320)
    maximumSize: Qt.size(900, 500)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "watchcat"; function toggle(): void { root.open = !root.open } }

    // ---- poll daemon live.json while open ----
    property bool liveBusy: false
    function pollLive() {
        if (root.liveBusy) return
        root.liveBusy = true
        var home = Quickshell.env("HOME")
        liveProc.command = ["cat", home + "/.local/share/watchcat/live.json"]
        liveProc.running = true
    }
    Process {
        id: liveProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.liveBusy = false
                if (text.indexOf("{") === 0) {
                    try {
                        var d = JSON.parse(text)
                        root.liveState = d.state || "loading"
                        root.liveErr = d.err || ""
                        root.iface = d.iface || ""
                        root.todayMb = d.today_mb || 0
                        root.unattKb = d.unatt_kb || 0
                        root.talkers = d.talkers || []
                    } catch (e) { root.liveState = "error"; root.liveErr = "live.json parse failed" }
                } else {
                    root.liveState = "error"
                    root.liveErr = "daemon not running — systemctl --user start watchcat"
                }
            }
        }
    }
    Timer {
        interval: 4000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollLive()
    }

    // ---- dashboard: static HTML from daemon.db ----
    property bool dashBusy: false
    function openDashboard() {
        if (root.dashBusy) return
        root.dashBusy = true
        var home = Quickshell.env("HOME")
        dashProc.command = ["python3", home + "/dotfiles/.config/quickshell/scripts/watchcat-dash.py",
            home + "/.local/share/watchcat/today.html", String(root.capMb)]
        dashProc.running = true
    }
    readonly property real capMb: 1024
    Process {
        id: dashProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.dashBusy = false
                if (text.indexOf("ok ") === 0) {
                    var home = Quickshell.env("HOME")
                    Quickshell.execDetached(["xdg-open", home + "/.local/share/watchcat/today.html"])
                }
            }
        }
    }

    NetRate { id: rate }

    // ================= visual layer (Amber Bento) =================
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // ── hero: three stat cards side by side ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // DOWN
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    radius: 14
                    color: colors.alpha(colors.surface, 0.55)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        Text { text: "DOWN"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Text { text: rate.rxKbs >= 1024 ? (rate.rxKbs / 1024).toFixed(1) : Math.round(rate.rxKbs); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 24; font.weight: Font.ExtraBold }
                        Text { text: rate.rxKbs >= 1024 ? "MB/s" : "KB/s"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                        Canvas {
                            antialiasing: true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            property var h: rate.rxHistory
                            onHChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset()
                                var arr = h; if (arr.length < 2) return
                                var max = 10; for (var i = 0; i < arr.length; i++) max = Math.max(max, arr[i])
                                var n = arr.length
                                function px(i) { return (i / (n - 1)) * width }
                                function py(v) { return height - 1 - (v / max) * (height - 4) }
                                ctx.beginPath(); ctx.moveTo(0, height)
                                for (var j = 0; j < n; j++) ctx.lineTo(px(j), py(arr[j]))
                                ctx.lineTo(px(n - 1), height); ctx.closePath()
                                ctx.fillStyle = colors.alpha(colors.tertiary, 0.20); ctx.fill()
                                ctx.beginPath()
                                for (var k = 0; k < n; k++) { if (k === 0) ctx.moveTo(px(k), py(arr[k])); else ctx.lineTo(px(k), py(arr[k])) }
                                ctx.strokeStyle = colors.tertiary; ctx.lineWidth = 1.6; ctx.lineJoin = "round"; ctx.stroke()
                            }
                        }
                    }
                }

                // UP
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    radius: 14
                    color: colors.alpha(colors.surface, 0.55)
                    border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        Text { text: "UP"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Text { text: rate.txKbs >= 1024 ? (rate.txKbs / 1024).toFixed(1) : Math.round(rate.txKbs); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 24; font.weight: Font.ExtraBold }
                        Text { text: rate.txKbs >= 1024 ? "MB/s" : "KB/s"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                        Canvas {
                            antialiasing: true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            property var h: rate.txHistory
                            onHChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d"); ctx.reset()
                                var arr = h; if (arr.length < 2) return
                                var max = 10; for (var i = 0; i < arr.length; i++) max = Math.max(max, arr[i])
                                var n = arr.length
                                function px(i) { return (i / (n - 1)) * width }
                                function py(v) { return height - 1 - (v / max) * (height - 4) }
                                ctx.beginPath(); ctx.moveTo(0, height)
                                for (var j = 0; j < n; j++) ctx.lineTo(px(j), py(arr[j]))
                                ctx.lineTo(px(n - 1), height); ctx.closePath()
                                ctx.fillStyle = colors.alpha(colors.secondary, 0.20); ctx.fill()
                                ctx.beginPath()
                                for (var k = 0; k < n; k++) { if (k === 0) ctx.moveTo(px(k), py(arr[k])); else ctx.lineTo(px(k), py(arr[k])) }
                                ctx.strokeStyle = colors.secondary; ctx.lineWidth = 1.6; ctx.lineJoin = "round"; ctx.stroke()
                            }
                        }
                    }
                }

                // TODAY
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    radius: 14
                    color: colors.alpha(colors.surface, 0.55)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2
                        Text { text: "TODAY"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Text { text: root.todayMb >= 1024 ? (root.todayMb / 1024).toFixed(2) : Math.round(root.todayMb); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 24; font.weight: Font.ExtraBold }
                        Text { text: root.todayMb >= 1024 ? "GB / 1 GB" : "MB / 1 GB"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 7
                            radius: 3
                            color: colors.alpha(colors.surfaceVariant, 0.55)
                            Rectangle {
                                width: parent.width * Math.min(1, root.todayMb / root.capMb)
                                height: parent.height
                                radius: 3
                                color: root.todayMb >= root.capMb ? colors.error : colors.primary
                            }
                        }
                    }
                }
            }

            // ── daemon status bar ──
            Rectangle {
                Layout.fillWidth: true
                height: 38
                radius: 10
                color: colors.alpha(colors.surface, 0.45)
                border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 8
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: root.liveState === "on" ? "#8fce8f"
                            : root.liveState === "error" ? colors.error
                            : colors.tertiary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: root.liveState === "on" ? "weighing 24/7 · " + root.iface
                            : root.liveState === "error" ? root.liveErr
                            : root.liveState === "idle" ? "offline — waiting for a network"
                            : "contacting daemon…"
                        color: root.liveState === "error" ? colors.error : colors.alpha(colors.outline, 0.65)
                        font.family: colors.fontSans; font.pixelSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }

            // ── section label ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "HEAVIEST PROCESSES"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.fillWidth: true }
                Text { text: root.unattKb >= 1 ? Math.round(root.unattKb) + " KB/s kernel traffic" : root.talkers.length > 0 ? root.talkers.length + " processes" : "listening…"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8 }
            }

            // ── talkers list ──
            ListView {
                id: talkList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 8
                clip: true
                model: root.talkers
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: talkList.width
                    height: 44
                    radius: 10
                    color: rowMa.containsMouse ? colors.alpha(colors.primary, 0.08) : index % 2 === 0 ? colors.alpha(colors.surface, 0.35) : "transparent"
                    border.width: 1; border.color: rowMa.containsMouse ? colors.alpha(colors.primary, 0.3) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    // share bar behind text
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: parent.width * ((modelData.down + modelData.up) / Math.max(1, root.talkers[0].down + root.talkers[0].up))
                        radius: 10
                        color: colors.alpha(colors.tertiary, 0.08)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 8
                        Text { text: (index + 1) + "."; color: colors.alpha(colors.outline, 0.4); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; Layout.preferredWidth: 24 }
                        Text { text: modelData.prog; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: "pid " + modelData.pid; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 8 }
                        Text { text: "↓" + modelData.down.toFixed(0) + "  ↑" + modelData.up.toFixed(0); color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                    }
                    MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true }
                }
            }

            // ── footer ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "500 KB/s × 10s · 500 MB / 1 GB · notify only"; color: colors.alpha(colors.outline, 0.45); font.family: colors.fontSans; font.pixelSize: 8; Layout.fillWidth: true }
                Rectangle {
                    width: dashLabel.implicitWidth + 22; height: 28; radius: 8
                    color: dashMa.containsMouse ? colors.alpha(colors.tertiary, 0.28) : colors.alpha(colors.tertiary, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.4)
                    scale: dashMa.containsMouse ? 1.06 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text { id: dashLabel; anchors.centerIn: parent; text: root.dashBusy ? "…" : "dashboard"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                    MouseArea { id: dashMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openDashboard() }
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }
}