import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// DriveHealth — SMART health + disk space + live throughput + speed test.
// Needs no root: SMART comes from udisks2 over the system bus (readable by
// active users). For full smartctl attributes, add a sudoers line and point
// smartProc at `sudo -n smartctl -a -j`. Toggle: ipc call drives (SUPER ALT D).
FloatingWindow {
    id: root

    // Fallback palette so colors.* reads never throw during startup:
    // the external `colors` assignment can land after our bindings first
    // evaluate, and one throw aborts setup of the whole shell (no bar, no IPC).
    QtObject {
        id: fallback
        property color background: "#17130f"
        property color foreground: "#ebe1da"
        property color primary: "#f3bc87"
        property color secondary: "#dfc1a8"
        property color tertiary: "#9bcee3"
        property color error: "#ffb4ab"
        property color surface: "#17130f"
        property color on_surface: "#efe5df"
        property color surfaceVariant: "#50453b"
        property color outline: "#a39487"
        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    }
    property var colors: fallback
    property bool open: false

    // --- drive identity ---
    property string devName: ""
    property string model: ""
    property string sizeStr: ""
    // --- SMART (udisks, no root) ---
    property bool smartOk: false
    property bool failing: false
    property real tempC: 0
    property bool hasTemp: false
    property real powerHours: 0
    property bool hasHours: false
    property string selftest: ""
    property string note: ""
    // --- space: [{mp, pct, usedGb, totalGb}] ---
    property var parts: []
    // --- throughput ---
    property real readKBs: 0
    property real writeKBs: 0
    property var rHist: []
    property var wHist: []
    property real lastRSectors: -1
    property real lastWSectors: -1
    // --- speed test ---
    property bool speedBusy: false
    property string speedMsg: ""
    property real writeMBs: 0
    property real readMBs: 0

    title: "Drive Health"
    implicitWidth: 600
    implicitHeight: 500
    minimumSize: Qt.size(520, 440)
    maximumSize: Qt.size(700, 600)
    color: "transparent"
    visible: root.open
    IpcHandler { target: "drives"; function toggle(): void { root.open = !root.open } }

    function fmtGb(b) { return (b / 1073741824).toFixed(1) + "G" }
    function fmtHours(h) {
        if (h < 1) return "—"
        if (h < 24) return Math.round(h) + "h"
        if (h < 24 * 365) return Math.round(h / 24) + "d"
        return (h / 24 / 365).toFixed(1) + "y"
    }
    function fmtRate(kbs) {
        if (kbs >= 1024) return (kbs / 1024).toFixed(1) + " MB/s"
        return Math.round(kbs) + " KB/s"
    }

    // ===== static: lsblk + df =====
    function refreshStatic() {
        staticProc.command = ["sh", "-c", "lsblk -J -b -o NAME,MODEL,SIZE,TYPE -e 7,11,254 2>/dev/null; echo '---DF---'; df -B1 --output=target,used,avail / /home 2>/dev/null | tail -n +2"]
        staticProc.running = true
    }
    Process {
        id: staticProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var segs = text.split("---DF---")
                    var blk = JSON.parse(segs[0]).blockdevices || []
                    var disk = null
                    for (var i = 0; i < blk.length; i++) {
                        if (blk[i].type === "disk") { disk = blk[i]; break }
                    }
                    if (!disk && blk.length > 0) disk = blk[0]
                    if (disk) {
                        root.devName = disk.name || ""
                        root.model = String(disk.model || "").trim() || root.devName
                        root.sizeStr = disk.size ? (parseFloat(disk.size) / 1073741824).toFixed(1) + " GB" : ""
                        statView.path = ""
                        statView.path = "/sys/block/" + root.devName + "/stat"
                    }
                    var rows = []
                    if (segs.length > 1) {
                        var lines = segs[1].trim().split("\n")
                        for (var j = 0; j < lines.length; j++) {
                            var f = lines[j].trim().split(/\s+/)
                            if (f.length < 3) continue
                            var used = parseFloat(f[1]), avail = parseFloat(f[2])
                            var tot = used + avail
                            if (!(tot > 0)) continue
                            var dup = false
                            for (var k = 0; k < rows.length; k++) {
                                if (rows[k].mp !== f[0] && rows[k].totalGb === root.fmtGb(tot) && rows[k].usedGb === root.fmtGb(used)) { dup = true; break }
                            }
                            if (!dup) rows.push({ mp: f[0], pct: Math.round(100 * used / tot), usedGb: root.fmtGb(used), totalGb: root.fmtGb(tot) })
                        }
                    }
                    root.parts = rows
                } catch (e) {}
            }
        }
    }

    // ===== SMART via udisks (no root) =====
    function refreshSmart() {
        smartProc.command = ["sh", "-c",
            "P=$(busctl --system call org.freedesktop.UDisks2 /org/freedesktop/UDisks2 org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null | grep -oE '/org/freedesktop/UDisks2/drives/[A-Za-z0-9_]+' | head -1); " +
            "if [ -z \"$P\" ]; then echo SMART_NONE; exit 0; fi; " +
            "F=$(busctl --system get-property org.freedesktop.UDisks2 \"$P\" org.freedesktop.UDisks2.Drive.Ata SmartFailing 2>/dev/null | awk '{print $2}'); " +
            "T=$(busctl --system get-property org.freedesktop.UDisks2 \"$P\" org.freedesktop.UDisks2.Drive.Ata SmartTemperature 2>/dev/null | awk '{print $2}'); " +
            "H=$(busctl --system get-property org.freedesktop.UDisks2 \"$P\" org.freedesktop.UDisks2.Drive.Ata SmartPowerOnSeconds 2>/dev/null | awk '{print $2}'); " +
            "S=$(busctl --system get-property org.freedesktop.UDisks2 \"$P\" org.freedesktop.UDisks2.Drive.Ata SmartSelftestStatus 2>/dev/null | awk '{print $2}' | tr -d '\"'); " +
            "echo \"SMART $F $T $H $S\""]
        smartProc.running = true
    }
    Process {
        id: smartProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var line = text.trim().split("\n").pop() || ""
                if (line.indexOf("SMART ") !== 0) {
                    root.smartOk = false
                    root.note = "SMART unavailable (is udisks running?)"
                    return
                }
                var p = line.split(/\s+/)
                root.smartOk = true
                root.failing = p[1] === "true"
                var k = parseFloat(p[2])
                root.hasTemp = k > 0
                root.tempC = root.hasTemp ? k - 273.15 : 0
                var s = parseFloat(p[3])
                root.hasHours = s > 0
                root.powerHours = root.hasHours ? s / 3600 : 0
                root.selftest = p.length > 4 ? p[4] : ""
                root.note = root.failing ? "DRIVE REPORTS FAILURE — back up now" : ""
            }
        }
    }

    // ===== throughput: /sys/block/<dev>/stat, 1s poll while open =====
    Timer {
        interval: 1000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.devName !== "") {
                statView.path = ""
                statView.path = "/sys/block/" + root.devName + "/stat"
            }
        }
    }
    FileView {
        id: statView
        printErrors: false
        onLoaded: {
            var f = text().trim().split(/\s+/)
            if (f.length < 10) return
            var rs = parseFloat(f[2]), ws = parseFloat(f[6])
            if (root.lastRSectors >= 0 && rs >= root.lastRSectors && ws >= root.lastWSectors) {
                root.readKBs = (rs - root.lastRSectors) * 512 / 1024
                root.writeKBs = (ws - root.lastWSectors) * 512 / 1024
                var rh = root.rHist.slice()
                rh.push(root.readKBs)
                if (rh.length > 40) rh.shift()
                root.rHist = rh
                var wh = root.wHist.slice()
                wh.push(root.writeKBs)
                if (wh.length > 40) wh.shift()
                root.wHist = wh
            }
            root.lastRSectors = rs
            root.lastWSectors = ws
        }
    }
    Timer {
        interval: 5000
        running: root.open
        repeat: true
        onTriggered: root.refreshSmart()
    }
    onOpenChanged: {
        if (open) {
            root.lastRSectors = -1
            root.refreshStatic()
            root.refreshSmart()
        }
    }

    // ===== speed test: 256MB direct-IO write + read in $HOME =====
    function runSpeed() {
        if (root.speedBusy) return
        root.speedBusy = true
        root.speedMsg = "testing…"
        root.writeMBs = 0
        root.readMBs = 0
        var f = Quickshell.env("HOME") + "/.cache/drive-speed-test.tmp"
        var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
        speedProc.command = ["sh", "-c",
            "F=" + q(f) + "; " +
            "W=$(dd if=/dev/zero of=\"$F\" bs=1M count=256 oflag=direct 2>&1 | grep -oE '[0-9.]+ [GM]B/s' | tail -1); " +
            "R=$(dd if=\"$F\" of=/dev/null bs=1M iflag=direct 2>&1 | grep -oE '[0-9.]+ [GM]B/s' | tail -1); " +
            "rm -f \"$F\"; echo \"SPEED $W / $R\""]
        speedProc.running = true
    }
    Process {
        id: speedProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.speedBusy = false
                var m = text.match(/SPEED\s+([0-9.]+)\s+([GM])B\/s\s+\/\s+([0-9.]+)\s+([GM])B\/s/)
                if (m) {
                    root.writeMBs = parseFloat(m[1]) * (m[2] === "G" ? 1024 : 1)
                    root.readMBs = parseFloat(m[3]) * (m[4] === "G" ? 1024 : 1)
                    root.speedMsg = "write " + Math.round(root.writeMBs) + " MB/s · read " + Math.round(root.readMBs) + " MB/s"
                } else {
                    root.speedMsg = "test failed"
                }
            }
        }
    }

    // ================= UI =================
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        color: colors.alpha(colors.background, 0.74)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.18)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "DRIVE HEALTH"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                Text {
                    text: "re-check"
                    color: reMa.containsMouse ? colors.primary : colors.alpha(colors.outline, 0.6)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    MouseArea { id: reMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.refreshStatic(); root.refreshSmart() } }
                }
                Rectangle {
                    width: 24; height: 24; radius: 12
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4) : "transparent"
                    Text { anchors.centerIn: parent; text: "×"; color: closeMa.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7); font.family: "FiraCode Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            Text {
                visible: root.note !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.note
                color: root.failing ? colors.error : colors.secondary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            // health banner
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 12
                color: colors.alpha(colors.surface, 0.4)
                border.width: 1
                border.color: root.failing ? colors.alpha(colors.error, 0.4) : colors.alpha(colors.outline, 0.12)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true
                        Text {
                            text: !root.smartOk ? "…" : root.failing ? "FAILING" : "GOOD"
                            color: !root.smartOk ? colors.alpha(colors.outline, 0.6) : root.failing ? colors.error : colors.secondary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 17
                            font.weight: Font.ExtraBold
                        }
                        Text {
                            text: root.model !== "" ? root.model + " · " + root.sizeStr : "reading…"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "TEMP"; color: colors.alpha(colors.outline, 0.55); font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                        Text { text: root.hasTemp ? Math.round(root.tempC) + "°" : "—"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "ON TIME"; color: colors.alpha(colors.outline, 0.55); font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                        Text { text: root.hasHours ? root.fmtHours(root.powerHours) : "—"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text { text: "SELF-TEST"; color: colors.alpha(colors.outline, 0.55); font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                        Text { text: root.selftest !== "" ? root.selftest : "—"; color: root.selftest === "success" ? colors.secondary : colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }

            // space
            Text { text: "SPACE"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5 }
            Repeater {
                model: root.parts
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: modelData.mp; color: colors.alpha(colors.foreground, 0.8); font.family: "FiraCode Nerd Font"; font.pixelSize: 10; Layout.preferredWidth: 52; elide: Text.ElideRight }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: colors.alpha(colors.surfaceVariant, 0.5)
                        Rectangle {
                            width: parent.width * Math.min(100, modelData.pct) / 100
                            height: parent.height
                            radius: 3
                            color: modelData.pct > 90 ? colors.error : colors.primary
                        }
                    }
                    Text { text: modelData.usedGb + " / " + modelData.totalGb; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9 }
                }
            }

            // throughput
            RowLayout {
                Layout.fillWidth: true
                Text { text: "THROUGHPUT"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                Text { text: "↓ " + root.fmtRate(root.readKBs) + "   ↑ " + root.fmtRate(root.writeKBs); color: colors.alpha(colors.foreground, 0.75); font.family: "FiraCode Nerd Font"; font.pixelSize: 9 }
            }
            Canvas {
                id: ioChart
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                Connections {
                    target: root
                    function onRHistChanged() { ioChart.requestPaint() }
                }
                onPaint: {
                    var ctx = getContext("2d")
                    var W = width, H = height
                    ctx.clearRect(0, 0, W, H)
                    var all = root.rHist.concat(root.wHist)
                    var maxV = 1
                    for (var i = 0; i < all.length; i++) {
                        if (all[i] > maxV) maxV = all[i]
                    }
                    var draw = function (hist, style) {
                        if (hist.length < 2) return
                        ctx.beginPath()
                        for (var j = 0; j < hist.length; j++) {
                            var x = W - (hist.length - 1 - j) * (W / 39)
                            var y = H - 4 - (hist[j] / maxV) * (H - 10)
                            if (j === 0) ctx.moveTo(x, y)
                            else ctx.lineTo(x, y)
                        }
                        ctx.strokeStyle = style
                        ctx.lineWidth = 1.5
                        ctx.stroke()
                    }
                    draw(root.rHist, colors.secondary)
                    draw(root.wHist, colors.primary)
                }
            }

            // speed test
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    height: 26
                    width: speedLabel.implicitWidth + 20
                    radius: 13
                    color: root.speedBusy ? colors.alpha(colors.surfaceVariant, 0.4) : speedMa.containsMouse ? colors.alpha(colors.primary, 0.22) : colors.alpha(colors.primary, 0.10)
                    border.width: 1
                    border.color: colors.alpha(colors.primary, 0.35)
                    Text {
                        id: speedLabel
                        anchors.centerIn: parent
                        text: root.speedBusy ? "testing…" : "run speed test"
                        color: colors.primary
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                    MouseArea { id: speedMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.runSpeed() }
                }
                Text {
                    text: root.speedMsg
                    color: colors.alpha(colors.foreground, 0.8)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }
        }

        Keys.onEscapePressed: root.open = false
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_R) {
                root.refreshStatic()
                root.refreshSmart()
                e.accepted = true
            }
        }
        focus: root.open
    }
}
