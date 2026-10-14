import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Meetcap recorder — Orb design port. Recording only: start/stop/status,
// live mic+sys levels (cava feeds), last session row. Transcripts live
// in the separate web dashboard, never here.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    title: "Meetcap"
    implicitWidth: 380
    implicitHeight: 470
    minimumSize: Qt.size(340, 430)
    maximumSize: Qt.size(420, 520)
    color: "transparent"
    visible: root.open || closeAnim.running

    IpcHandler { target: "meetcap"; function toggle(): void { root.open = !root.open } }

    // ---------- verified Nerd Font glyphs (name-checked via fontTools) ----------
    readonly property string gMic: ""
    readonly property string gSpk: ""
    readonly property string gStop: ""
    readonly property string gRec: "󰑋"
    readonly property string gRetry: ""
    readonly property string gFolder: ""
    readonly property string gAlert: "󰀧"

    // ---------- state ----------
    // idle | recording | saving | error
    property string recState: "idle"
    property string elapsed: "--:--"
    property string errMsg: ""
    property real micLvl: 0
    property real sysLvl: 0
    property string lastName: ""
    property string lastMeta: ""
    property bool confReady: false

    onOpenChanged: {
        if (open) { setupProc.running = true; statusProc.running = true; lastProc.running = true; openAnim.restart() }
        else { closeAnim.restart(); confReady = false }
    }

    Timer { id: statusTimer; interval: 1000; running: root.open; repeat: true; onTriggered: statusProc.running = true }

    // ---------- backend: meetcap CLI ----------
    Process {
        id: statusProc
        command: ["meetcap", "status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                if (t.indexOf("recording ") === 0) {
                    root.recState = "recording"
                    root.errMsg = ""
                    var m = t.match(/\(([^)]+)\)/)
                    root.elapsed = m ? m[1] : "--:--"
                } else if (root.recState === "saving" || t === "idle") {
                    if (root.recState === "saving") lastProc.running = true
                    if (root.recState !== "error") root.recState = "idle"
                    root.elapsed = "--:--"
                }
            }
        }
    }

    Process {
        id: startProc
        command: ["meetcap", "start"]
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                if (t !== "") { root.errMsg = t; root.recState = "error" }
            }
        }
        onExited: { statusProc.running = true }
    }

    Process {
        id: stopProc
        command: ["meetcap", "stop"]
        onExited: { statusProc.running = true }
    }

    Process {
        id: lastProc
        command: ["sh", "-c", "d=$(ls -td ~/.local/state/meetcap/20* 2>/dev/null | head -n1); [ -n \"$d\" ] && echo \"$(basename $d)|$(du -sh $d 2>/dev/null | cut -f1)\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                var p = t.split("|")
                if (p.length === 2) { root.lastName = p[0]; root.lastMeta = p[1] + " on disk" }
            }
        }
    }

    // ---------- levels: two cava feeds (mic + monitor), built from live defaults ----------
    Process {
        id: setupProc
        command: ["sh", "-c", "m=$(pactl get-default-source); s=$(pactl get-default-sink).monitor; for t in \"mic:$m\" \"sys:$s\"; do n=${t%%:*}; src=${t#*:}; printf '[general]\\nbars = 8\\nframerate = 15\\n[output]\\nmethod = raw\\ndata_format = ascii\\nascii_max_range = 100\\nbar_delimiter = 59\\nframe_delimiter = 10\\n[input]\\nmethod = pulse\\nsource = %s\\n' \"$src\" > /tmp/cava-meetcap-$n.conf; done"]
        onExited: { root.confReady = true }
    }

    function cavaLevel(line) {
        var parts = line.trim().split(";")
        var sum = 0
        var n = 0
        for (var i = 0; i < parts.length; i++) {
            var v = parseInt(parts[i], 10)
            if (!isNaN(v)) { sum += v; n++ }
        }
        return n > 0 ? Math.min(1, (sum / n) / 100) : 0
    }

    Process {
        id: cavaMic
        command: ["cava", "-p", "/tmp/cava-meetcap-mic.conf"]
        running: root.open && root.confReady
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { root.micLvl = cavaLevel(line); orbCanvas.requestPaint() } }
    }
    Process {
        id: cavaSys
        command: ["cava", "-p", "/tmp/cava-meetcap-sys.conf"]
        running: root.open && root.confReady
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) { root.sysLvl = cavaLevel(line); orbCanvas.requestPaint() } }
    }

    function doMain() {
        if (root.recState === "recording") { root.recState = "saving"; stopProc.running = true }
        else if (root.recState !== "saving") { root.errMsg = ""; startProc.running = true }
    }

    // ---------- UI ----------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.34, 1.35, 0.64, 1, 1, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // -- header: caps + status chip --
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "MEETCAP RECORDER"
                    color: colors.alpha(colors.outline, 0.55)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: root.recState !== "recording"
                    radius: 11
                    height: 22
                    width: chipRow.implicitWidth + 18
                    color: root.recState === "error" ? colors.alpha(colors.error, 0.15) : colors.alpha(colors.surfaceVariant, 0.30)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 5
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.recState === "recording" ? colors.error : root.recState === "saving" ? colors.tertiary : root.recState === "error" ? colors.error : colors.outline
                        }
                        Text {
                            text: root.recState === "recording" ? "Recording" : root.recState === "saving" ? "Saving" : root.recState === "error" ? "Stopped" : "Idle"
                            color: colors.alpha(colors.foreground, 0.8)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // -- orb: timer center, mic arc left (tertiary), sys arc right (secondary) --
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                Canvas {
                    id: orbCanvas
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var cx = width / 2
                        var cy = height / 2
                        var r0 = 62
                        var N = 36
                        ctx.lineCap = "round"
                        ctx.lineWidth = 4
                        for (var side = 0; side < 2; side++) {
                            var v = side === 0 ? root.micLvl : root.sysLvl
                            ctx.strokeStyle = side === 0 ? colors.tertiary : colors.secondary
                            for (var i = 0; i < N; i++) {
                                var th = (i + 0.5) / N * Math.PI + (side === 0 ? Math.PI : 0)
                                var amp = v * (0.3 + 0.7 * Math.abs(Math.sin(i * 0.55 + Date.now() * 0.004 + side * 2)))
                                var l = 3 + amp * 34
                                var sn = Math.sin(th)
                                var co = -Math.cos(th)
                                ctx.globalAlpha = v > 0.01 ? 0.5 + amp : 0.3
                                ctx.beginPath()
                                ctx.moveTo(cx + sn * r0, cy + co * r0)
                                ctx.lineTo(cx + sn * (r0 + l), cy + co * (r0 + l))
                                ctx.stroke()
                            }
                        }
                        ctx.globalAlpha = 0.5
                        ctx.strokeStyle = colors.primary
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        ctx.arc(cx, cy, r0 - 8, 0, 7)
                        ctx.stroke()
                        ctx.globalAlpha = 1
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        text: root.elapsed
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 30
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: root.recState === "recording" ? "RECORDING" : root.recState === "saving" ? "SAVING" : root.recState === "error" ? "STOPPED" : "READY"
                        color: root.recState === "error" ? colors.error : colors.alpha(colors.outline, 0.65)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // -- meters --
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: root.gMic; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 7
                        radius: 4
                        color: colors.alpha(colors.surfaceVariant, 0.55)
                        Rectangle { width: parent.width * root.micLvl; height: 7; radius: 4; color: colors.tertiary }
                    }
                    Text { text: "mic"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 9; Layout.preferredWidth: 30 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: root.gSpk; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 7
                        radius: 4
                        color: colors.alpha(colors.surfaceVariant, 0.55)
                        Rectangle { width: parent.width * root.sysLvl; height: 7; radius: 4; color: colors.secondary }
                    }
                    Text { text: "sys"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 9; Layout.preferredWidth: 30 }
                }
            }

            // -- error line (only on error) --
            RowLayout {
                visible: root.recState === "error"
                Layout.fillWidth: true
                spacing: 8
                Text { text: root.gAlert; color: colors.error; font.family: colors.fontSans; font.pixelSize: 14 }
                Text {
                    text: root.errMsg !== "" ? root.errMsg : "Recorder stopped."
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // -- last recording --
            RowLayout {
                visible: root.lastName !== ""
                Layout.fillWidth: true
                spacing: 8
                Text { text: root.gFolder; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 13 }
                Text {
                    text: root.lastName
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text { text: root.lastMeta; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 11 }
            }

            // -- primary action (exactly one) --
            Rectangle {
                id: mainBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 12
                color: colors.primary
                property bool hovered: btnHover.containsMouse
                transform: Translate { y: mainBtn.hovered ? -2 : 0; Behavior on y { NumberAnimation { duration: 140 } } }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: root.recState === "recording" ? root.gStop : root.recState === "error" ? root.gRetry : root.gRec
                        color: "#441d00"
                        font.family: colors.fontSans
                        font.pixelSize: 14
                    }
                    Text {
                        text: root.recState === "recording" ? "Stop & save  (s)" : root.recState === "error" ? "Try again  (r)" : "Record  (r)"
                        color: "#441d00"
                        font.family: colors.fontSans
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
                MouseArea { id: btnHover; anchors.fill: parent; hoverEnabled: true; onClicked: root.doMain() }
            }

            Text {
                text: "r record · s stop · esc close"
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans
                font.pixelSize: 10
                Layout.alignment: Qt.AlignHCenter
            }
        }

        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_R) root.doMain()
            else if (e.key === Qt.Key_S && root.recState === "recording") root.doMain()
        }
        focus: root.open
    }
}
