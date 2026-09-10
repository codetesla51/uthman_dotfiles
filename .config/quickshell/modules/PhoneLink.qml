import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PhoneLink — wireless file sender over ADB. No app on the phone, no cable
// after the one-time `tcpip` bootstrap: drop files and they land in Download,
// browse the phone and pull anything back. Toggle: ipc call phonelink (SUPER ALT K).
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

    // --- device state ---
    property string deviceId: ""        // "192.168.58.159:5555"
    property string deviceName: "Phone"
    property bool connected: false
    property string statusMsg: ""
    property bool busy: false           // a scan or connect attempt is running

    // --- send queue: [{path, name, total, sent, active, done, error}] ---
    property var queue: []
    property bool sending: false

    // --- pull browser ---
    property string remoteDir: "/sdcard/Download"
    property var remoteRows: []         // [{name, isDir}]
    property string pullState: ""       // name pulling, "" when idle
    property int pullTotal: 0
    property int pullGot: 0
    property var selected: []
    property var pullQueue: []
    property bool yankAfterPull: false

    // --- history: [{name, dir, time}] ---
    property var recentFiles: []

    title: "PhoneLink"
    implicitWidth: 400
    implicitHeight: 520
    minimumSize: Qt.size(360, 420)
    maximumSize: Qt.size(460, 580)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "phonelink"; function toggle(): void { root.open = !root.open } }

    function say(text) {
        root.statusMsg = text
        statusLife.restart()
    }
    Timer { id: statusLife; interval: 5000; onTriggered: root.statusMsg = "" }

    function notify(title, body) {
        Quickshell.execDetached(["sh", "-c", "notify-send -u normal -i phone '" + String(title).replace(/'/g, "'\\''") + "' '" + String(body).replace(/'/g, "'\\''") + "'"])
    }

    // ================= discovery =================
    // Remembered target, then the hotspot gateway — whichever answers first wins.
    // mDNS is skipped on purpose: classic tcpip mode advertises nothing to discover.

    FileView {
        id: rememberedFile
        path: Quickshell.env("HOME") + "/.config/phone-sender/target"
        printErrors: false
        blockLoading: true
        onLoaded: root.remembered(text())
        onLoadFailed: root.tryGateway()
    }
    function connectTo(addr) {
        connectProc.command = ["adb", "connect", addr]
        connectProc.running = true
    }
    function remembered(text) {
        var addr = String(text || "").trim().split("\n")[0] || ""
        if (addr.length > 0) {
            root.connectTo(addr)
        } else {
            root.tryGateway()
        }
    }

    function refreshDevices() {
        if (root.busy) return
        root.busy = true
        listProc.running = true
    }
    function tryGateway() {
        gatewayProc.running = true
    }

    Process {
        id: listProc
        command: ["adb", "devices", "-l"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.busy = false
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/^(\S+)\s+device\b/)
                    if (m) {
                        var mod = lines[i].match(/\bmodel:(\S+)/)
                        root.deviceId = m[1]
                        root.deviceName = mod ? mod[1].replace(/_/g, " ") : "Phone"
                        if (!root.connected) {
                            root.connected = true
                            root.say("Connected to " + root.deviceName)
                        }
                        if (root.remoteRows.length === 0) root.listRemote()
                        return
                    }
                }
                // nothing attached: fall through to remembered/gateway connect
                if (!root.connected) {
                    rememberedFile.path = ""
                    rememberedFile.path = Quickshell.env("HOME") + "/.config/phone-sender/target"
                } else {
                    root.connected = false
                    root.deviceId = ""
                }
            }
        }
        onExited: {
            if (root.busy) {
                root.busy = false
                if (!root.connected) {
                    rememberedFile.path = ""
                    rememberedFile.path = Quickshell.env("HOME") + "/.config/phone-sender/target"
                }
            }
        }
    }

    Process {
        id: gatewayProc
        command: ["sh", "-c", "ip route show default 2>/dev/null | awk '{print $3; exit}'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var gw = text.trim()
                if (gw.length > 0) {
                    root.connectTo(gw + ":5555")
                } else {
                    root.say("No network route — join the hotspot first")
                }
            }
        }
    }

    Process {
        id: connectProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.indexOf("connected to") !== -1 || text.indexOf("already connected") !== -1) {
                    root.refreshDevices()
                } else {
                    root.say("Phone not answering — cable once for tcpip?")
                }
            }
        }
    }

    Timer { interval: 15000; running: root.open; repeat: true; triggeredOnStart: false; onTriggered: root.refreshDevices() }
    onOpenChanged: { if (open) { root.refreshDevices(); remoteList.focus = true } }

    // ================= send =================
    function queueFiles(paths) {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        var q = root.queue.slice()
        for (var i = 0; i < paths.length; i++) {
            var p = String(paths[i]).replace(/^file:\/\//, "")
            try { p = decodeURIComponent(p) } catch (e) {}
            var name = p.split("/").pop()
            if (!name) continue
            q.push({ path: p, name: name, total: 0, sent: 0, active: false, done: false, error: "" })
        }
        root.queue = q
        root.pumpQueue()
    }

    function pumpQueue() {
        if (root.sending) return
        for (var i = 0; i < root.queue.length; i++) {
            if (!root.queue[i].done && root.queue[i].error === "") {
                root.startPush(i)
                return
            }
        }
    }

    function setRow(i, patch) {
        var q = root.queue.slice()
        var row = {}
        for (var k in q[i]) row[k] = q[i][k]
        for (var f in patch) row[f] = patch[f]
        q[i] = row
        root.queue = q
    }

    function startPush(i) {
        root.sending = true
        pushIndex = i
        var row = root.queue[i]
        root.setRow(i, { active: true })
        root.say("Sending " + row.name + "…")
        sizeProc.command = ["stat", "-c", "%s", row.path]
        sizeProc.running = true
    }
    property int pushIndex: -1

    Process {
        id: sizeProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var total = parseInt(text.trim()) || 0
                root.setRow(root.pushIndex, { total: total })
                var row = root.queue[root.pushIndex]
                pushProc.command = ["adb", "-s", root.deviceId, "push", row.path, "/sdcard/Download/"]
                pushProc.running = true
                progressPoll.restart()
            }
        }
    }

    Process {
        id: pushProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector {
            id: pushErr
            waitForEnd: true
        }
        onExited: function (code) {
            progressPoll.stop()
            var i = root.pushIndex
            root.pushIndex = -1
            root.sending = false
            if (code === 0) {
                var row = root.queue[i]
                root.setRow(i, { active: false, done: true, sent: row.total })
                root.pushHistory(row.name, "sent")
                root.notify("Sent to " + root.deviceName, row.name)
                root.say("Sent " + row.name)
            } else {
                var err = (pushErr.text.trim().split("\n").pop() || "push failed").slice(0, 90)
                root.setRow(i, { active: false, error: err })
                root.say(err)
            }
            Qt.callLater(root.pumpQueue)
        }
    }

    Timer {
        id: progressPoll
        interval: 400
        repeat: true
        onTriggered: {
            if (root.pushIndex < 0) { progressPoll.stop(); return }
            var row = root.queue[root.pushIndex]
            if (!row || row.total <= 0) return
            progressProc.command = ["adb", "-s", root.deviceId, "shell", "stat", "-c", "%s", "/sdcard/Download/" + row.name]
            progressProc.running = true
        }
    }
    Process {
        id: progressProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.pushIndex < 0) return
                var got = parseInt(text.trim()) || 0
                var row = root.queue[root.pushIndex]
                if (row && got > row.sent) root.setRow(root.pushIndex, { sent: Math.min(got, row.total) })
            }
        }
    }

    function pushHistory(name, dir) {
        var entry = { name: name, dir: dir, time: Qt.formatDateTime(new Date(), "HH:mm") }
        var arr = [entry]
        for (var i = 0; i < root.recentFiles.length && i < 9; i++) arr.push(root.recentFiles[i])
        root.recentFiles = arr
    }

    Process {
        id: clipSetProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text
                if (t.indexOf("CLIP_SET_OK") !== -1) root.say("On your phone's clipboard")
                else if (t.indexOf("CLIP_EMPTY") !== -1) root.say("Clipboard is empty (or not text)")
                else if (t.indexOf("CLIP_TOOLONG") !== -1) root.say("Too long for direct set (100KB max)")
                else root.say("Couldn't set it — screen on and unlocked?")
            }
        }
    }
    // C: PC clipboard straight into the phone's clipboard (paste-ready).
    // Needs the tiny adb-clip helper on the phone — auto-deployed on first use,
    // no app install. Falls back to a clear error, never silently to a file.
    function sendClipboard() {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        var home = Quickshell.env("HOME")
        var q = function (s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
        var clipFile = home + "/.cache/phonelink-clipboard.txt"
        var jarDir = home + "/dotfiles/.config/quickshell/scripts/adb-clip"
        clipSetProc.command = ["sh", "-c",
            "D=" + q(root.deviceId) + "; F=" + q(clipFile) + "; J=" + q(jarDir) + "; " +
            "wl-paste -t text/plain --no-newline > \"$F\" 2>/dev/null || { echo CLIP_EMPTY; exit 0; }; " +
            "n=$(wc -c < \"$F\"); " +
            "if [ \"$n\" -eq 0 ]; then echo CLIP_EMPTY; exit 0; fi; " +
            "if [ \"$n\" -gt 100000 ]; then echo CLIP_TOOLONG; exit 0; fi; " +
            "adb -s \"$D\" shell 'test -x /data/local/tmp/clip' >/dev/null 2>&1 || " +
            "{ adb -s \"$D\" push \"$J/clip.jar\" \"$J/clip\" /data/local/tmp >/dev/null 2>&1 && " +
            "adb -s \"$D\" shell chmod 755 /data/local/tmp/clip >/dev/null 2>&1; }; " +
            "adb -s \"$D\" shell 'T=$(cat); /data/local/tmp/clip \"$T\"' < \"$F\" >/dev/null 2>&1 && echo CLIP_SET_OK || echo CLIP_SET_FAIL"]
        clipSetProc.running = true
    }
    function clearFinished() {
        root.queue = root.queue.filter(function (r) { return !r.done && r.error === "" })
    }
    function removeRow(i) {
        var q = root.queue.slice()
        if (i >= 0 && i < q.length) q.splice(i, 1)
        root.queue = q
    }
    function retryRow(i) {
        root.setRow(i, { error: "", active: false })
        root.pumpQueue()
    }

    // ================= pull =================
    function listRemote() {
        if (!root.connected) return
        lsProc.command = ["adb", "-s", root.deviceId, "shell", "ls", "-p", root.remoteDir]
        lsProc.running = true
    }
    Process {
        id: lsProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var rows = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var n = lines[i].trim()
                    if (!n) continue
                    rows.push({ name: n.replace(/\/$/, ""), isDir: n.charAt(n.length - 1) === "/" })
                }
                rows.sort(function (a, b) {
                    if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
                    return a.name.localeCompare(b.name)
                })
                root.remoteRows = rows
                remoteList.currentIndex = rows.length > 0 ? 0 : -1
            }
        }
    }

    function pullFile(name) {
        if (!root.connected || root.pullState !== "") return
        root.pullState = name
        root.pullTotal = 0
        root.pullGot = 0
        root.say("Pulling " + name + "…")
        sizeRemoteProc.command = ["adb", "-s", root.deviceId, "shell", "stat", "-c", "%s", root.remoteDir + "/" + name]
        sizeRemoteProc.running = true
        pullProc.command = ["adb", "-s", root.deviceId, "pull", root.remoteDir + "/" + name, Quickshell.env("HOME") + "/Downloads/"]
        pullProc.running = true
        pullProgress.restart()
    }
    function toggleSelect(name) {
        var sel = root.selected.slice()
        var at = sel.indexOf(name)
        if (at >= 0) sel.splice(at, 1)
        else sel.push(name)
        root.selected = sel
    }
    function pullSelection() {
        var names = root.selected.length > 0 ? root.selected.slice() : []
        if (names.length === 0) {
            var ci = remoteList.currentIndex
            if (ci < 0 && root.remoteRows.length > 0) ci = 0
            if (ci >= 0 && ci < root.remoteRows.length) names.push(root.remoteRows[ci].name)
        }
        if (names.length === 0) return
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        root.pullQueue = root.pullQueue.concat(names)
        root.selected = []
        root.say(names.length > 1 ? ("Pulling " + names.length + " files…") : ("Pulling " + names[0] + "…"))
        root.pumpPullQueue()
    }
    function pumpPullQueue() {
        if (root.pullState !== "" || root.pullQueue.length === 0) return
        var q = root.pullQueue.slice()
        var name = q.shift()
        root.pullQueue = q
        root.pullFile(name)
    }
    Process {
        id: sizeRemoteProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var total = parseInt(text.trim()) || 0
                if (total > 0) root.pullTotal = total
            }
        }
    }
    Timer {
        id: pullProgress
        interval: 400
        repeat: true
        onTriggered: {
            if (root.pullState === "") { pullProgress.stop(); return }
            sizeLocalProc.command = ["stat", "-c", "%s", Quickshell.env("HOME") + "/Downloads/" + root.pullState]
            sizeLocalProc.running = true
        }
    }
    Process {
        id: sizeLocalProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var got = parseInt(text.trim()) || 0
                if (got > root.pullGot) root.pullGot = got
            }
        }
    }
    Process {
        id: pullProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { id: pullErr; waitForEnd: true }
        onExited: function (code) {
            var name = root.pullState
            pullProgress.stop()
            root.pullState = ""
            root.pullTotal = 0
            root.pullGot = 0
            if (code === 0) {
                root.pushHistory(name, "pulled")
                root.notify("Pulled from " + root.deviceName, name)
                root.say("Pulled " + name + " to Downloads")
                if (root.yankAfterPull) {
                    root.yankAfterPull = false
                    var f = Quickshell.env("HOME") + "/Downloads/" + name
                    var q = "'" + f.replace(/'/g, "'\\''") + "'"
                    yankProc.command = ["sh", "-c", "if grep -Iq . " + q + "; then wl-copy < " + q + " && echo YANK_OK || echo YANK_FAIL; else echo NOTEXT; fi"]
                    yankProc.running = true
                }
            } else {
                var err = (pullErr.text.trim().split("\n").pop() || "pull failed").slice(0, 90)
                root.say(err)
            }
            Qt.callLater(root.pumpPullQueue)
        }
    }

    Process {
        id: yankProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                if (t === "YANK_OK") root.say("In your clipboard")
                else if (t === "NOTEXT") root.say("Not text — kept as a file")
                else root.say("Clipboard copy failed")
            }
        }
    }
    function enterRemote(name) {
        if (root.remoteDir === "/sdcard" && name === "..") return
        if (name === "..") {
            var cut = root.remoteDir.lastIndexOf("/")
            root.remoteDir = cut > 0 ? root.remoteDir.slice(0, cut) : "/sdcard"
        } else {
            root.remoteDir = root.remoteDir + "/" + name
        }
        root.remoteRows = []
        remoteList.currentIndex = -1
        root.selected = []
        root.listRemote()
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

            // status line
            Text {
                visible: root.statusMsg !== ""
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.statusMsg
                color: colors.secondary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                elide: Text.ElideRight
            }

            // ---- SEND: drop zone tile ----
            RowLayout {
                Layout.fillWidth: true
                Text { text: "SEND TO PHONE"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                Text {
                    text: "clipboard"
                    color: clipMa.containsMouse ? colors.primary : colors.alpha(colors.outline, 0.6)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    MouseArea { id: clipMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.sendClipboard() }
                }
            }

            Rectangle {
                id: dropTile
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                radius: 12
                color: dropArea.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surfaceVariant, 0.25)
                border.width: 1
                border.color: dropArea.containsMouse ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.1)
                scale: dropArea.containsMouse ? 1.02 : 1
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        text: ""
                        color: dropArea.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.75)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 28
                        scale: dropArea.containsMouse ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Drop files here"
                            color: dropArea.containsMouse ? colors.primary : colors.foreground
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: root.connected ? "lands in Download" : "no phone connected"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 8
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: function (drop) {
                        var paths = []
                        for (var i = 0; i < drop.urls.length; i++) paths.push(drop.urls[i])
                        root.queueFiles(paths)
                    }
                }
            }

            // ---- queue ----
            ColumnLayout {
                visible: root.queue.length > 0
                Layout.fillWidth: true
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "QUEUE (" + root.queue.length + ")"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                    Text {
                        text: "clear done"
                        color: clearMa.containsMouse ? colors.primary : colors.alpha(colors.outline, 0.6)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearFinished() }
                    }
                }
                ListView {
                    id: queueList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(3 * 36, count * 36)
                    clip: true
                    spacing: 4
                    model: root.queue
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    onCountChanged: if (count > 0) positionViewAtEnd()
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        width: queueList.width
                        spacing: 3
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: modelData.error !== "" ? "󰅖" : modelData.done ? "" : "󰇚"
                                color: modelData.error !== "" ? colors.error : modelData.done ? colors.secondary : colors.primary
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                            }
                            Text {
                                text: modelData.error !== "" ? modelData.error : modelData.name
                                color: modelData.error !== "" ? colors.error : colors.foreground
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: modelData.active && modelData.total > 0
                                text: Math.round(100 * modelData.sent / Math.max(1, modelData.total)) + "%"
                                color: colors.primary
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                            Text {
                                visible: modelData.error !== ""
                                text: "retry"
                                color: retryMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.75)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.retryRow(index) }
                            }
                            Text {
                                visible: modelData.done || modelData.error !== ""
                                text: ""
                                color: xMa.containsMouse ? colors.error : colors.alpha(colors.outline, 0.55)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.removeRow(index) }
                            }
                        }
                        Rectangle {
                            visible: modelData.active && !modelData.done
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.surfaceVariant, 0.5)
                            Rectangle {
                                width: parent.width * modelData.sent / Math.max(1, modelData.total)
                                height: parent.height
                                radius: 2
                                color: colors.primary
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }

            // ---- PULL: phone browser ----
            RowLayout {
                Layout.fillWidth: true
                Text { text: "ON THE PHONE (" + root.remoteRows.length + ")"; color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                Text {
                    text: root.remoteDir.replace("/sdcard", "phone")
                    color: colors.alpha(colors.outline, 0.55)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 8
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 120
                }
                Text {
                    text: "s sel · p pull · y yank · c clip"
                    color: colors.alpha(colors.outline, 0.5)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 8
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                radius: 12
                color: colors.alpha(colors.surface, 0.4)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.12)
                clip: true

                Text {
                    visible: !root.connected
                    anchors.centerIn: parent
                    text: "connect a phone to browse it"
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                }
                ListView {
                    id: remoteList
                    visible: root.connected
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    model: root.remoteRows
                    keyNavigationWraps: true
                    highlightMoveDuration: 150
                    highlight: Rectangle { color: colors.alpha(colors.primary, 0.10); radius: 8 }
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: remoteList.width
                        height: 26
                        radius: 8
                        color: root.selected.indexOf(modelData.name) >= 0 ? colors.alpha(colors.primary, 0.20) : rowMa.containsMouse ? colors.alpha(colors.primary, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 6
                            spacing: 6
                            Text {
                                text: modelData.isDir ? "󰉋" : ""
                                color: modelData.isDir ? colors.primary : colors.alpha(colors.foreground, 0.7)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
                            }
                            Text {
                                text: modelData.name
                                color: root.selected.indexOf(modelData.name) >= 0 ? colors.primary : colors.foreground
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Rectangle {
                            visible: root.pullState === modelData.name
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            anchors { leftMargin: 8; rightMargin: 8; bottomMargin: 2 }
                            height: 3
                            radius: 1.5
                            color: colors.alpha(colors.surfaceVariant, 0.5)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: root.pullTotal > 0 ? parent.width * Math.min(1, root.pullGot / root.pullTotal) : parent.width * 0.3
                                radius: 1.5
                                color: colors.primary
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                if (modelData.isDir) root.enterRemote(modelData.name)
                                else root.toggleSelect(modelData.name)
                            }
                        }
                    }
                    header: Rectangle {
                        id: upRow
                        visible: root.remoteDir !== "/sdcard"
                        width: remoteList.width
                        height: 24
                        radius: 8
                        color: upMa.containsMouse ? colors.alpha(colors.primary, 0.12) : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹ up"
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.enterRemote("..") }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        Keys.onEscapePressed: root.open = false
        Keys.onPressed: (e) => {
            if (e.text === "p" || e.text === "P") {
                root.pullSelection()
                e.accepted = true
            } else if (e.key === Qt.Key_S) {
                var si = remoteList.currentIndex
                if (si < 0 && root.remoteRows.length > 0) si = 0
                if (si >= 0 && si < root.remoteRows.length) {
                    root.toggleSelect(root.remoteRows[si].name)
                    if (si + 1 < root.remoteRows.length) remoteList.currentIndex = si + 1
                }
                e.accepted = true
            } else if (e.key === Qt.Key_Y) {
                var yi = remoteList.currentIndex
                if (yi < 0 && root.remoteRows.length > 0) yi = 0
                if (yi >= 0 && yi < root.remoteRows.length && !root.remoteRows[yi].isDir) {
                    root.yankAfterPull = true
                    root.pullFile(root.remoteRows[yi].name)
                }
                e.accepted = true
            } else if (e.key === Qt.Key_C) {
                root.sendClipboard()
                e.accepted = true
            } else if (e.key === Qt.Key_J) {
                if (root.remoteRows.length > 0) remoteList.currentIndex = (remoteList.currentIndex + 1) % root.remoteRows.length
                e.accepted = true
            } else if (e.key === Qt.Key_K) {
                if (root.remoteRows.length > 0) remoteList.currentIndex = (remoteList.currentIndex - 1 + root.remoteRows.length) % root.remoteRows.length
                e.accepted = true
            } else if (e.key === Qt.Key_L) {
                var li = remoteList.currentIndex
                if (li >= 0 && li < root.remoteRows.length) {
                    if (root.remoteRows[li].isDir) root.enterRemote(root.remoteRows[li].name)
                    else root.pullFile(root.remoteRows[li].name)
                }
                e.accepted = true
            } else if (e.key === Qt.Key_H) {
                root.enterRemote("..")
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                var r = remoteList.currentIndex
                if (r >= 0 && r < root.remoteRows.length && root.remoteRows[r].isDir) root.enterRemote(root.remoteRows[r].name)
                e.accepted = true
            }
        }
        focus: root.open
    }
}
