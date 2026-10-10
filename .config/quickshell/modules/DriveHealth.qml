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

    // Fallback palette
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
    property bool scanBusy: false
    property string scanMsg: ""
    readonly property string noteText: root.failing ? root.note : (root.scanMsg !== "" ? root.scanMsg : root.note)
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
    property real liveWriteMBs: 0
    property real liveReadMBs: 0
    property real vortexPhase: 0   // UI-only twist phase for the vortex (visual layer)
    property string speedFile: ""
    // --- self-test ---
    property bool selfBusy: false
    property string selfMsg: ""
    property string note: ""

    title: "HW " + Math.round(liveWriteMBs) + "/" + Math.round(liveReadMBs)
    IpcHandler { target: "dbg"; function go(): void { root.runSpeed() } }
    implicitWidth: 640
    implicitHeight: 540
    minimumSize: Qt.size(580, 480)
    maximumSize: Qt.size(760, 700)
    color: "transparent"
    visible: root.open || closeAnim.running
    // NOTE: no IpcHandler here — Bar.qml owns target "drives" and lazy-loads this.

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
                if (root.selfBusy && root.selftest !== "" && root.selftest !== "inprogress") {
                    root.selfBusy = false
                    root.selfMsg = "self-test: " + root.selftest
                }
                root.note = root.failing ? "DRIVE REPORTS FAILURE — back up now" : ""
            }
        }
    }

    // ===== SMART self-test (short, ~2min, read-only) =====
    function runSelftest() {
        if (root.selfBusy) return
        root.selfBusy = true
        root.selfMsg = "self-test running…"
        selfProc.command = ["sh", "-c",
            "P=$(busctl --system call org.freedesktop.UDisks2 /org/freedesktop/UDisks2 org.freedesktop.DBus.ObjectManager GetManagedObjects 2>/dev/null | grep -oE '/org/freedesktop/UDisks2/drives/[A-Za-z0-9_]+' | head -1); " +
            "if [ -z \"$P\" ]; then echo SELF_NONE; exit 0; fi; " +
            "busctl --system call org.freedesktop.UDisks2 \"$P\" org.freedesktop.UDisks2.Drive.Ata SmartSelftestStart sa{sv} short 0 >/dev/null 2>&1 && echo SELF_STARTED || echo SELF_DENIED"]
        selfProc.running = true
    }
    Process {
        id: selfProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text
                if (t.indexOf("SELF_STARTED") === -1) {
                    root.selfBusy = false
                    root.selfMsg = t.indexOf("SELF_NONE") !== -1 ? "no drive found" : "couldn't start self-test"
                }
            }
        }
    }
    Timer {
        interval: 10000
        running: root.open && root.selfBusy
        repeat: true
        onTriggered: root.refreshSmart()
    }

    // ===== full SMART via sudo =====
    function runFullScan() {
        if (root.scanBusy || root.devName === "") return
        root.scanBusy = true
        root.scanMsg = "scanning…"
        var home = Quickshell.env("HOME")
        var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
        fullProc.command = ["sh", "-c",
            "SUDO_ASKPASS=" + q(home + "/.local/bin/askpass") + " sudo -A smartctl -a -j " + q("/dev/" + root.devName) + " 2>&1"]
        fullProc.running = true
    }
    Process {
        id: fullProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.scanBusy = false
                var t = text
                if (t.trim() === "") { root.scanMsg = "cancelled"; return }
                try {
                    var d = JSON.parse(t.slice(t.indexOf("{")))
                    var attrs = (((d.ata_smart_attributes || {}).table) || [])
                    var wear = -1
                    for (var i = 0; i < attrs.length; i++) {
                        var aid = attrs[i].id
                        if (aid === 177 || aid === 231 || aid === 232 || aid === 233 || aid === 202) {
                            var av = parseFloat(attrs[i].value)
                            if (av >= 0 && (wear < 0 || av < wear)) wear = av
                        }
                    }
                    var errs = 0
                    for (var j = 0; j < attrs.length; j++) {
                        var jid = attrs[j].id
                        if (jid === 5 || jid === 196 || jid === 197 || jid === 198) errs += parseFloat((attrs[j].raw || {}).value || 0)
                    }
                    var tp = (d.temperature || {}).current
                    var bits = []
                    bits.push(wear >= 0 ? ("life left " + wear + "%") : "no wear data")
                    bits.push("errors " + errs)
                    if (tp > 0) bits.push(Math.round(tp) + "°")
                    root.scanMsg = bits.join(" · ")
                } catch (e) {
                    root.scanMsg = t.indexOf("sudo:") !== -1 ? "sudo failed" : "scan failed"
                }
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
                if (rh.length > 50) rh.shift()
                root.rHist = rh
                var wh = root.wHist.slice()
                wh.push(root.writeKBs)
                if (wh.length > 50) wh.shift()
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
            openAnim.restart()
        } else closeAnim.restart()
    }

    // ===== speed test: 1GB direct-IO write + read in $HOME =====
    function runSpeed() {
        if (root.speedBusy) return
        root.speedBusy = true
        root.speedMsg = "testing…"
        root.writeMBs = 0
        root.readMBs = 0
        root.liveWriteMBs = 0
        root.liveReadMBs = 0
        var f = Quickshell.env("HOME") + "/.cache/drive-speed-test.tmp"
        var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
        root.speedFile = f
        writeProc.command = ["sh", "-c", "dd if=/dev/zero of=" + q(f) + " bs=1M count=1024 oflag=direct status=progress"]
        writeProc.running = true
    }
    Process {
        id: writeProc
        stderr: StdioCollector {
            id: speedErr
            waitForEnd: false
            onTextChanged: {
                var hits = text.match(/([0-9.]+)\s+([GM])B\/s/g)
                if (hits && hits.length > 0) {
                    var last = hits[hits.length - 1].split(" ")[0]
                    root.liveWriteMBs = parseFloat(last) * (hits[hits.length - 1].indexOf("GB/s") !== -1 ? 1024 : 1)
                }
            }
        }
        onExited: function (code) {
            if (code === 0) {
                var q2 = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
                readProc.command = ["sh", "-c", "dd if=" + q2(root.speedFile) + " of=/dev/null bs=1M iflag=direct status=progress; rm -f " + q2(root.speedFile)]
                readProc.running = true
            } else {
                root.speedBusy = false
                root.speedMsg = "write test failed (disk full?)"
            }
        }
    }
    Process {
        id: readProc
        stderr: StdioCollector {
            id: readErr
            waitForEnd: false
            onTextChanged: {
                var hits = text.match(/([0-9.]+)\s+([GM])B\/s/g)
                if (hits && hits.length > 0) {
                    var last = hits[hits.length - 1].split(" ")[0]
                    root.liveReadMBs = parseFloat(last) * (hits[hits.length - 1].indexOf("GB/s") !== -1 ? 1024 : 1)
                }
            }
        }
        onExited: function (rcode) {
            root.speedBusy = false
            if (rcode === 0 && root.liveReadMBs > 0) {
                root.writeMBs = root.liveWriteMBs
                root.readMBs = root.liveReadMBs
                root.speedMsg = "write " + Math.round(root.writeMBs) + " MB/s · read " + Math.round(root.readMBs) + " MB/s"
            } else {
                root.speedMsg = "test failed"
            }
        }
    }

    // ================= UI =================
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        clip: true
        // bezier pair — open pops with overshoot bounce, close hurries out
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }

        // subtle top glow
        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: 1
            color: colors.alpha(colors.primary, 0.12)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 10

            // header — chip + label + drive + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: "󰍛"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "DRIVE HEALTH"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Rectangle {
                    visible: root.devName !== ""
                    Layout.preferredWidth: devTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.secondary, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                    Text { id: devTxt; anchors.centerIn: parent; text: "/dev/" + root.devName; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: drvCloseMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: drvCloseMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            // warning / scan result
            Text {
                visible: root.noteText !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.noteText
                color: root.failing ? colors.error : colors.secondary
                font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                elide: Text.ElideRight
            }

            // ── Health Banner ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                radius: 14
                color: colors.alpha(colors.surface, 0.45)
                border.width: 1
                border.color: root.failing ? colors.alpha(colors.error, 0.35) : colors.alpha(colors.outline, 0.1)
                Rectangle {
                    visible: root.failing
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: colors.alpha(colors.error, 0.2)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 16
                    ColumnLayout {
                        spacing: 3
                        Layout.fillWidth: true
                        RowLayout { spacing: 6
                            Text {
                                text: !root.smartOk ? "NO DATA" : root.failing ? "FAILING" : "HEALTHY"
                                color: !root.smartOk ? colors.alpha(colors.outline, 0.6) : root.failing ? colors.error : colors.secondary
                                font.family: colors.fontSans; font.pixelSize: 16; font.weight: Font.ExtraBold
                            }
                        }
                        Text {
                            text: root.model !== "" ? root.model + "  ·  " + root.sizeStr : "detecting drive…"
                            color: colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans; font.pixelSize: 9
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                    }
                    Row { spacing: 16; Layout.alignment: Qt.AlignVCenter
                        Column { spacing: 2
                            Text { text: "TEMP"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.1; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: root.hasTemp ? Math.round(root.tempC) + "°C" : "—"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        Column { spacing: 2
                            Text { text: "UPTIME"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.1; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: root.hasHours ? root.fmtHours(root.powerHours) : "—"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        Column { spacing: 2
                            Text { text: "SELF-TEST"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.1; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: root.selftest !== "" ? root.selftest : "—"; color: root.selftest === "success" ? colors.secondary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                    }
                }
            }

            // ── Disk Space ──
            RowLayout {
                Layout.fillWidth: true
                Text { text: "STORAGE"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 2; Layout.fillWidth: true }
            }
            Repeater {
                model: root.parts
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 10
                    Text { text: modelData.mp; color: colors.alpha(colors.foreground, 0.7); font.family: colors.fontSans; font.pixelSize: 9; Layout.preferredWidth: 50; elide: Text.ElideRight }
                    Rectangle {
                        Layout.fillWidth: true; height: 8; radius: 4
                        color: colors.alpha(colors.surfaceVariant, 0.4)
                        Rectangle {
                            width: parent.width * Math.min(100, modelData.pct) / 100
                            height: parent.height; radius: 4
                            color: modelData.pct > 90 ? colors.error : colors.primary
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text { text: modelData.pct + "%"; color: modelData.pct > 90 ? colors.error : colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
                    Text { text: modelData.usedGb + " / " + modelData.totalGb; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                }
            }

            // ── Throughput Graph ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                radius: 12
                color: colors.alpha(colors.surface, 0.35)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.08)
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "THROUGHPUT"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1; Layout.fillWidth: true }
                        Text { text: "↓ " + root.fmtRate(root.readKBs) + "   ↑ " + root.fmtRate(root.writeKBs); color: colors.alpha(colors.foreground, 0.7); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    }
                    Canvas {
                        id: ioChart
                        Layout.fillWidth: true; Layout.fillHeight: true
                        antialiasing: true
                        Connections { target: root; function onRHistChanged() { ioChart.requestPaint() } }
                        onPaint: {
                            var ctx = getContext("2d")
                            var W = width, H = height
                            ctx.clearRect(0, 0, W, H)
                            var all = root.rHist.concat(root.wHist)
                            var maxV = 1
                            for (var i = 0; i < all.length; i++) { if (all[i] > maxV) maxV = all[i] }
                            maxV = Math.max(maxV * 1.15, 10)
                            // grid
                            ctx.strokeStyle = colors.alpha(colors.outline, 0.06)
                            ctx.lineWidth = 0.5
                            for (var g = 0; g < 4; g++) {
                                var gy = H - (g / 3) * H
                                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(W, gy); ctx.stroke()
                            }
                            var drawSmooth = function (hist, strokeColor, fillColor) {
                                if (hist.length < 2) return
                                var n = hist.length
                                var pts = []
                                for (var j = 0; j < n; j++) {
                                    pts.push({ x: (j / (n - 1)) * W, y: H - (hist[j] / maxV) * (H - 4) })
                                }
                                ctx.beginPath()
                                ctx.moveTo(pts[0].x, H)
                                ctx.lineTo(pts[0].x, pts[0].y)
                                for (var k = 1; k < pts.length; k++) {
                                    var cpx = (pts[k - 1].x + pts[k].x) / 2
                                    ctx.bezierCurveTo(cpx, pts[k - 1].y, cpx, pts[k].y, pts[k].x, pts[k].y)
                                }
                                ctx.lineTo(pts[pts.length - 1].x, H)
                                ctx.closePath()
                                var grad = ctx.createLinearGradient(0, 0, 0, H)
                                grad.addColorStop(0, fillColor)
                                grad.addColorStop(1, "transparent")
                                ctx.fillStyle = grad
                                ctx.fill()
                                ctx.beginPath()
                                ctx.moveTo(pts[0].x, pts[0].y)
                                for (var l = 1; l < pts.length; l++) {
                                    var cpx2 = (pts[l - 1].x + pts[l].x) / 2
                                    ctx.bezierCurveTo(cpx2, pts[l - 1].y, cpx2, pts[l].y, pts[l].x, pts[l].y)
                                }
                                ctx.strokeStyle = strokeColor
                                ctx.lineWidth = 1.8
                                ctx.lineJoin = "round"
                                ctx.stroke()
                            }
                            drawSmooth(root.rHist, colors.secondary, colors.alpha(colors.secondary, 0.12))
                            drawSmooth(root.wHist, colors.primary, colors.alpha(colors.primary, 0.12))
                        }
                    }
                }
            }

            // ── Speed Test Button + Result ──
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle {
                    width: 104; height: 28; radius: 14
                    scale: speedMa.containsMouse ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    color: root.speedBusy ? colors.alpha(colors.surfaceVariant, 0.4) : speedMa.containsMouse ? colors.alpha(colors.primary, 0.2) : colors.alpha(colors.primary, 0.08)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.speedBusy ? "testing…" : "speed test"
                        color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    MouseArea { id: speedMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.runSpeed() }
                }
                Text {
                    text: root.speedBusy ? ("↓ " + root.fmtRate(root.liveReadMBs) + "   ↑ " + root.fmtRate(root.liveWriteMBs)) : root.speedMsg
                    color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 10
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
            }

            // ── Self-Test Button + Result ──
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle {
                    width: 104; height: 28; radius: 14
                    scale: selfMa.containsMouse ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    color: root.selfBusy ? colors.alpha(colors.surfaceVariant, 0.4) : selfMa.containsMouse ? colors.alpha(colors.tertiary, 0.2) : colors.alpha(colors.tertiary, 0.08)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.3)
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.selfBusy ? "testing…" : "self-test"
                        color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    MouseArea { id: selfMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.runSelftest() }
                }
                Text {
                    text: root.selfMsg
                    color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 10
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
            }

            // ── Vortex (stored spiral-C): 72 rays, traveling ripple + slow rotation,
            // peak MB/s in the middle, write/read legend kept from the old gauge ──
            Canvas {
                id: speedo
                Layout.fillWidth: true
                Layout.preferredHeight: 200
                antialiasing: true
                Timer {
                    interval: 50
                    running: root.open            // never burns CPU while the panel is shut
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        root.vortexPhase += root.speedBusy ? 0.3 : 0.07
                        speedo.requestPaint()
                    }
                }
                Connections {
                    target: root
                    function onReadMBsChanged() { speedo.requestPaint() }
                    function onLiveWriteMBsChanged() { speedo.requestPaint() }
                    function onLiveReadMBsChanged() { speedo.requestPaint() }
                }
                onPaint: {
                    var ctx = getContext("2d")
                    var W = width, H = height
                    ctx.clearRect(0, 0, W, H)
                    var cx = W / 2, cy = H / 2
                    var R = Math.min(W, H) / 2 - 6
                    var dw = root.speedBusy ? root.liveWriteMBs : root.writeMBs
                    var dr = root.speedBusy ? root.liveReadMBs : root.readMBs
                    var peak = Math.max(dw, dr)
                    var t = root.vortexPhase
                    // vortex always spins (slow idle, fast testing) — no empty text at all
                    var RAYS = 72
                    var r0 = R * 0.42
                    for (var i = 0; i < RAYS; i++) {
                        var a = (i / RAYS) * Math.PI * 2 + t * 0.4
                        var wave = Math.sin(i * 0.35 - t * 2.2) * 0.5 + 0.5
                        var r1 = R * 0.5 + wave * (R * 0.42)
                        var accent = i % 6 === 0 ? colors.tertiary : (i % 2 ? colors.primary : colors.secondary)
                        ctx.strokeStyle = colors.alpha(accent, i % 6 === 0 ? 0.95 : 0.55)
                        ctx.lineWidth = i % 6 === 0 ? 2.4 : 1.6
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0)
                        ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1)
                        ctx.stroke()
                    }
                    // center value (same content the gauge showed)
                    ctx.textAlign = "center"
                    if (peak > 0) {
                        ctx.fillStyle = colors.foreground
                        ctx.font = "bold 26px 'FiraCode Nerd Font', monospace"
                        ctx.fillText(Math.round(peak), cx, cy + 4)
                        ctx.font = "9px 'FiraCode Nerd Font', monospace"
                        ctx.fillStyle = colors.alpha(colors.outline, 0.5)
                        ctx.fillText("MB/s", cx, cy + 18)
                    }
                    // legend (only with data — zeros are noise)
                    if (peak > 0) {
                    ctx.textAlign = "left"
                    ctx.font = "8px 'FiraCode Nerd Font', monospace"
                    ctx.fillStyle = colors.primary
                    ctx.fillText("— write " + Math.round(dw), 6, H - 4)
                    ctx.fillStyle = colors.secondary
                    var ww = ctx.measureText("— write " + Math.round(dw)).width
                    ctx.fillText("— read " + Math.round(dr), 6 + ww + 16, H - 4)
                    }
                }
            }
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
