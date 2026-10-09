import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PhoneBridge — wireless file sender over ADB. Thin client over the standalone
// ~/phonebridge backend (daemon CLI: devices, battery, clip, push, pull, ls,
// shot, ring, inbox-sync, notifs). Toggle: ipc call phonebridge (SUPER ALT K).
FloatingWindow {
    id: root

    // Fallback palette so colors.* reads never throw during startup.
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
        property string fontSans: "sans-serif"
        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    }
    property var colors: fallback
    property bool open: false
    property string daemon: Quickshell.env("HOME") + "/phonebridge/phonebridge"
    property string pcDest: Quickshell.env("HOME") + "/PhoneBridge"

    // --- device state ---
    property string deviceId: ""
    property string deviceName: "Phone"
    property bool connected: false
    property bool linkLost: false       // was connected, now gone, watchdog knocking
    property string statusMsg: ""
    property bool busy: false

    // --- send queue: [{path, name, total, sent, active, done, error}] ---
    property var queue: []
    property bool sending: false

    // --- pull browser ---
    property string remoteDir: "/sdcard"
    property var remoteRows: []
    property string pullState: ""
    property int pullTotal: 0
    property int pullGot: 0
    property var selected: []
    property var pullQueue: []
    property bool yankAfterPull: false

    // --- battery + shot ---
    property int battery: -1
    property bool charging: false
    property string shotName: ""
    property string plugged: ""
    property string signalNet: ""
    property int signalLevel: -1
    property double mobileMb: -1
    property double dataCapMb: 2048
    property bool hotspotOn: false
    property string hotspotNote: "Toggling can drop the link"
    property bool hotspotBusy: false
    property bool hotspotWant: false
    property bool dndOn: false
    property int screenTimeout: 60000

    // --- type-ahead find ---
    property bool searching: false
    property string searchBuf: ""

    property var seenKeys: []
    property bool primed: false
    property int pollStart: 0

    title: "PhoneBridge"
    implicitWidth: 700
    implicitHeight: 700
    minimumSize: Qt.size(700, 700)
    maximumSize: Qt.size(700, 700)
    color: "transparent"
    visible: root.open || closeAnim.running

    IpcHandler { target: "phonebridge"; function toggle(): void { root.open = !root.open } }

    Component.onCompleted: root.refreshDevices()

    function say(text) {
        root.statusMsg = text
        statusLife.restart()
    }
    Timer { id: statusLife; interval: 5000; onTriggered: root.statusMsg = "" }
    Timer { id: searchTimer; interval: 1200; onTriggered: root.clearSearch() }

    function notify(title, body) {
        Quickshell.execDetached(["sh", "-c", "notify-send -u normal -a 'Phone' '" + String(title).replace(/'/g, "'\\''") + "' '" + String(body).replace(/'/g, "'\\''") + "'"])
    }

    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function clearSearch() {
        root.searching = false
        root.searchBuf = ""
    }

    function findJump() {
        var q = root.searchBuf.toLowerCase()
        if (q === "") return
        for (var i = 0; i < root.remoteRows.length; i++) {
            if (String(root.remoteRows[i].name).toLowerCase().indexOf(q) === 0) {
                remoteList.currentIndex = i
                break
            }
        }
    }

    function refreshBattery() {
        if (!root.connected) return
        batteryProc.command = [root.daemon, "battery"]
        batteryProc.running = true
    }

    function scanNotifs(fresh) {
        if (!root.primed) {
            for (var p = 0; p < fresh.length; p++) root.seenKeys.push(fresh[p].key)
            root.primed = true
            return
        }
        for (var k = 0; k < fresh.length; k++) {
            var f = fresh[k]
            if (root.seenKeys.indexOf(f.key) !== -1) continue
            root.seenKeys.push(f.key)
            if (root.seenKeys.length > 200) root.seenKeys.shift()
            var who = f.sender || ("New " + f.label + " notification")
            var body = f.body ? String(f.body) : (f.sender ? "via " + f.label : "")
            Quickshell.execDetached(["notify-send", "-a", f.label, who, body])
        }
    }

    function ringPhone() {
        if (!root.connected) { root.say("No phone connected — same WiFi as the laptop?"); return }
        root.say("Ringing phone…")
        ringProc.command = [root.daemon, "ring"]
        ringProc.running = true
    }

    function shotPhone() {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        root.say("Snapping shot…")
        shotProc.command = [root.daemon, "shot"]
        shotProc.running = true
    }

    // --- phone settings + radio (direct adb) ---
    function adbArgs(extra) { return ["adb", "-s", root.deviceId, "shell"].concat(extra) }
    function refreshPhoneState() {
        if (!root.connected || root.deviceId === "") return
        if (!pluggedProc.running) { pluggedProc.command = root.adbArgs(["dumpsys", "battery"]); pluggedProc.running = true }
        if (!signalProc.running) { signalProc.command = root.adbArgs(["dumpsys", "telephony.registry"]); signalProc.running = true }
        if (!dataProc.running) { dataProc.command = root.adbArgs(["cat", "/proc/net/dev"]); dataProc.running = true }
        if (!dndGetProc.running) { dndGetProc.command = root.adbArgs(["settings", "get", "global", "zen_mode"]); dndGetProc.running = true }
        if (!timeoutGetProc.running) { timeoutGetProc.command = root.adbArgs(["settings", "get", "system", "screen_off_timeout"]); timeoutGetProc.running = true }
        if (!hotspotStatProc.running) { hotspotStatProc.command = root.adbArgs(["dumpsys", "wifi"]); hotspotStatProc.running = true }
    }
    function dataText() {
        if (root.mobileMb < 0) return "…"
        var g = root.mobileMb / 1024
        return (g >= 1 ? g.toFixed(1) + " GB" : Math.round(root.mobileMb) + " MB") + " of " + Math.round(root.dataCapMb / 1024) + " GB"
    }
    function toggleDnd() {
        if (!root.connected) return
        root.dndOn = !root.dndOn
        root.say(root.dndOn ? "DND on" : "DND off")
        dndSetProc.command = root.adbArgs(["cmd", "notification", "set_dnd", root.dndOn ? "priority" : "off"])
        dndSetProc.running = true
    }
    function timeoutLabel() {
        var m = root.screenTimeout
        if (m <= 15000) return "15s"
        if (m <= 30000) return "30s"
        if (m <= 60000) return "1m"
        if (m <= 300000) return "5m"
        return "10m"
    }
    function cycleTimeout() {
        if (!root.connected) return
        var steps = [15000, 30000, 60000, 300000, 600000]
        var next = steps[0]
        for (var i = 0; i < steps.length; i++) if (root.screenTimeout < steps[i]) { next = steps[i]; break }
        if (root.screenTimeout >= steps[steps.length - 1]) next = steps[0]
        timeoutSetProc.command = root.adbArgs(["settings", "put", "system", "screen_off_timeout", String(next)])
        timeoutSetProc.running = true
    }
    function toggleHotspot() {
        if (!root.connected || root.hotspotBusy) return
        root.hotspotWant = !root.hotspotOn
        root.hotspotBusy = true
        root.hotspotNote = "Switching — link may drop"
        root.say(root.hotspotWant ? "Starting hotspot…" : "Stopping hotspot…")
        hotspotProc.command = root.adbArgs(["cmd", "wifi", root.hotspotWant ? "start-softap" : "stop-softap"])
        hotspotProc.running = true
    }

    // ================= discovery =================
    property int discoveryStart: 0
    function connectTo(addr) {
        connectProc.command = addr ? [root.daemon, "connect", addr] : [root.daemon, "connect"]
        root.discoveryStart = Date.now()
        root.say("Connecting…")
        discoveryWatchdog.restart()
        connectProc.running = true
    }

    function refreshDevices() {
        if (root.busy) return
        root.busy = true
        root.discoveryStart = Date.now()
        discoveryWatchdog.restart()
        listProc.running = true
    }

    Timer {
        id: discoveryWatchdog
        interval: 15000
        repeat: false
        onTriggered: {
            var killed = false
            if (connectProc.running) { connectProc.running = false; killed = true }
            if (listProc.running) { listProc.running = false; killed = true }
            if (root.busy) root.busy = false
            if (killed && !root.connected) root.say("Phone not answering — same WiFi as the laptop?")
        }
    }

    property int reconnectDelay: 10
    Timer {
        id: reconnectTimer
        interval: 10000
        running: root.open && !root.connected && !root.busy
        repeat: true
        onTriggered: {
            root.reconnectDelay = Math.min(60, root.reconnectDelay + 10)
            reconnectTimer.interval = root.reconnectDelay * 1000
            root.refreshDevices()
        }
    }

    Process {
        id: listProc
        command: [root.daemon, "devices"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                discoveryWatchdog.stop()
                root.busy = false
                var found = []
                try { found = JSON.parse(text) } catch (e) {}
                if (found.length > 0) {
                    var pick = found[0]
                    for (var j = 0; j < found.length; j++) {
                        if (found[j].id === root.deviceId) pick = found[j]
                    }
                    root.deviceId = pick.id
                    root.deviceName = pick.name
                    if (!root.connected) {
                        root.connected = true
                        root.say("Connected to " + root.deviceName)
                    }
                    root.linkLost = false
                    root.reconnectDelay = 10
                    reconnectTimer.interval = 10000
                    root.refreshBattery()
                    if (root.remoteRows.length === 0) root.listRemote()
                    root.refreshPhoneState()
                    return
                }
                if (!root.connected) {
                    root.connectTo("")
                } else {
                    root.connected = false
                    root.linkLost = true
                    root.deviceId = ""
                }
            }
        }
        onExited: {
            discoveryWatchdog.stop()
            if (root.busy) {
                root.busy = false
                if (!root.connected) root.say("No phone pair — run ~/phonebridge/init.sh (cable once for tcpip 5555)")
            }
        }
    }

    Process {
        id: connectProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                discoveryWatchdog.stop()
                var ok = false
                try { ok = JSON.parse(text).status === "ok" } catch (e) {}
                if (ok) root.refreshDevices()
                else root.say("Phone not answering — cable once for tcpip?")
            }
        }
        onExited: function (code) {
            discoveryWatchdog.stop()
            if (code === 127) root.say("adb not installed — sudo pacman -S android-tools")
            else if (code !== 0 && !root.connected) root.say("Phone not answering — cable once for tcpip?")
        }
    }

    // notify forward watcher
    Process {
        id: notifProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var fresh = []
                try { fresh = JSON.parse(text) } catch (e) {}
                root.scanNotifs(fresh)
            }
        }
    }
    Timer {
        id: notifTimer
        interval: 4000
        running: root.connected
        repeat: true
        onTriggered: {
            var now = Date.now()
            if (notifProc.running) {
                if (now - root.pollStart > 10000) notifProc.running = false
                return
            }
            root.pollStart = now
            notifProc.command = [root.daemon, "notifs"]
            notifProc.running = true
        }
    }

    // inbox auto-delivery
    Process {
        id: inboxSyncProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var pulled = [], skipped = []
                try {
                    var r = JSON.parse(text)
                    pulled = r.pulled || []
                    skipped = r.skipped || []
                } catch (e) {}
                for (var i = 0; i < pulled.length; i++) root.say("Phone → PC: " + pulled[i].name)
                for (var j = 0; j < skipped.length; j++)
                    if (skipped[j].reason === "too-big")
                        root.say("Inbox " + skipped[j].name + " too big — pull via browser")
            }
        }
    }

    Timer {
        id: inboxTimer
        interval: 5000
        running: root.connected
        repeat: true
        onTriggered: {
            if (inboxSyncProc.running || root.pullState !== "" || root.pullQueue.length > 0) return
            inboxSyncProc.command = [root.daemon, "inbox-sync"]
            inboxSyncProc.running = true
        }
    }

    Process { id: ringProc }

    Timer { interval: 15000; running: root.open; repeat: true; triggeredOnStart: false; onTriggered: { root.refreshDevices(); root.refreshBattery(); root.refreshPhoneState() } }
    onOpenChanged: { if (open) { root.refreshDevices(); root.refreshBattery(); root.refreshPhoneState(); remoteList.focus = true; openAnim.restart() } else closeAnim.restart() }

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
                pushProc.command = [root.daemon, "push", row.path]
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
            progressProc.command = ["adb", "-s", root.deviceId, "shell", "stat", "-c", "%s", root.sq("/sdcard/Download/" + row.name)]
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

    Process {
        id: batteryProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var b = JSON.parse(text)
                    root.battery = b.level
                    root.charging = b.charging
                } catch (e) {}
            }
        }
    }
    Process {
        id: shotProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var s = JSON.parse(text)
                    root.shotName = s.name
                } catch (e) { root.shotName = "" }
            }
        }
        onExited: function (code) {
            if (code === 0) {
                root.notify("Phone shot", root.shotName)
                root.say("Shot saved to Pictures/PhoneBridge")
            } else {
                root.say("Shot failed — screen on and unlocked?")
            }
        }
    }
    Process {
        id: clipSetProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var st = ""
                try { st = JSON.parse(text).status } catch (e) {}
                if (st === "ok") root.say("On your phone's clipboard")
                else if (st === "empty") root.say("Clipboard is empty (or not text/image)")
                else if (st === "toolong") root.say("Too long for direct set (100KB max)")
                else root.say("Couldn't set it — screen on and unlocked?")
            }
        }
        onExited: function (code) { if (code !== 0) root.say("Couldn't set it — screen on and unlocked?") }
    }
    function sendClipboard() {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        root.say("Sending clipboard…")
        clipReadProc.command = ["sh", "-c",
            "if wl-paste --list-types 2>/dev/null | grep -q image; then echo CLIP_HAS_IMAGE; " +
            "else wl-paste -t text/plain --no-newline > " + root.sq(root.clipFile) + " 2>/dev/null && echo CLIP_HAS_TEXT || echo CLIP_EMPTY; fi"]
        clipReadProc.running = true
    }
    property string clipFile: Quickshell.env("HOME") + "/.cache/phonebridge-clipboard.txt"
    Process {
        id: clipReadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                if (t.indexOf("CLIP_HAS_IMAGE") !== -1) {
                    root.say("Sending image…")
                    var d = new Date()
                    function p2(n) { return (n < 10 ? "0" : "") + n }
                    var ip = "/tmp/clipboard-" + p2(d.getHours()) + p2(d.getMinutes()) + p2(d.getSeconds()) + ".png"
                    clipImgProc.command = ["sh", "-c",
                        "wl-paste -t image/png > " + root.sq(ip) + " 2>/dev/null && " +
                        "[ -s " + root.sq(ip) + " ] && " + root.sq(root.daemon) + " push " + root.sq(ip)]
                    clipImgProc.running = true
                } else if (t.indexOf("CLIP_HAS_TEXT") !== -1) {
                    clipSetProc.command = [root.daemon, "clip", "--file", root.clipFile]
                    clipSetProc.running = true
                } else {
                    root.say("Clipboard is empty (or not text/image)")
                }
            }
        }
    }
    Process {
        id: clipImgProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var ok = false
                try { ok = JSON.parse(text).status === "ok" } catch (e) {}
                root.say(ok ? "Image on your phone — saved in Download" : "Image push failed — screen on and unlocked?")
            }
        }
        onExited: function (code) { if (code !== 0) root.say("Image push failed — screen on and unlocked?") }
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
    function clearFinished() {
        root.queue = root.queue.filter(function(r){ return !r.done })
    }

    // ================= pull =================
    function listRemote() {
        if (!root.connected) return
        lsProc.command = [root.daemon, "ls", root.remoteDir]
        lsProc.running = true
    }
    Process {
        id: lsProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var rows = []
                try { rows = JSON.parse(text) } catch (e) {}
                root.remoteRows = rows
                remoteList.currentIndex = rows.length > 0 ? 0 : -1
            }
        }
    }

    function pullFile(name) {
        if (!root.connected) return
        if (root.pullState !== "") {
            root.say("Busy — pulling " + root.pullState + "…")
            return
        }
        root.pullState = name
        root.pullTotal = 0
        root.pullGot = 0
        root.say("Pulling " + name + "…")
        var isDir = false
        for (var d = 0; d < root.remoteRows.length; d++)
            if (root.remoteRows[d].name === name) { isDir = root.remoteRows[d].isDir; break }
        if (!isDir)
            sizeRemoteProc.command = ["adb", "-s", root.deviceId, "shell", "stat", "-c", "%s", root.sq(root.remoteDir + "/" + name)]
        sizeRemoteProc.running = !isDir
        pullProc.command = [root.daemon, "pull", name, "--dir", root.remoteDir, "--dest", root.pcDest]
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
            sizeLocalProc.command = ["stat", "-c", "%s", root.pcDest + "/" + root.pullState]
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
                root.notify("Pulled from " + root.deviceName, name)
                root.say("Pulled " + name + " to PhoneBridge")
                if (root.yankAfterPull) {
                    root.yankAfterPull = false
                    var f = root.pcDest + "/" + name
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
    Process {
        id: pluggedProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.match(/Wireless powered: true/)) root.plugged = "WIRELESS"
                else if (text.match(/USB powered: true/)) root.plugged = "USB"
                else if (text.match(/AC powered: true/)) root.plugged = "AC"
                else root.plugged = ""
            }
        }
    }
    Process {
        id: signalProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lv = -1, lm, lre = /mLte=CellSignalStrengthLte:[^}]*?level=(\d)/g
                while ((lm = lre.exec(text)) !== null) lv = Math.max(lv, parseInt(lm[1]))
                root.signalLevel = Math.min(4, lv)
                var rt = text.match(/getRilDataRadioTechnology=\d+\((\w+)\)/)
                root.signalNet = rt ? (rt[1] === "NR" ? "5G" : rt[1]) : ""
            }
        }
    }
    Process {
        id: dataProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var total = 0, any = false
                var devLines = text.split("\n")
                for (var i = 0; i < devLines.length; i++) {
                    var ci = devLines[i].indexOf(":")
                    if (ci < 0) continue
                    var iface = devLines[i].slice(0, ci).trim()
                    if (!iface.match(/^(rmnet|ccmni|qmap|seth_)/)) continue
                    var f = devLines[i].slice(ci + 1).trim().split(/\s+/)
                    if (f.length < 9) continue
                    total += (parseInt(f[0]) || 0) + (parseInt(f[8]) || 0)
                    any = true
                }
                root.mobileMb = any ? total / 1048576 : -1
            }
        }
    }
    Process {
        id: dndGetProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { root.dndOn = text.trim() !== "0" && text.trim() !== "null" }
        }
    }
    Process {
        id: dndSetProc
        onExited: function (code) {
            dndGetProc.command = root.adbArgs(["settings", "get", "global", "zen_mode"]); dndGetProc.running = true
            if (code !== 0) root.say("DND failed — screen on and unlocked?")
        }
    }
    Process {
        id: timeoutGetProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { var v = parseInt(text.trim()); if (!isNaN(v) && v > 0) root.screenTimeout = v }
        }
    }
    Process {
        id: timeoutSetProc
        onExited: function (code) {
            if (code === 0) { timeoutGetProc.command = root.adbArgs(["settings", "get", "system", "screen_off_timeout"]); timeoutGetProc.running = true; root.say("Timeout " + root.timeoutLabel()) }
            else root.say("Timeout failed — screen on and unlocked?")
        }
    }
    Process {
        id: hotspotStatProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var low = text.toLowerCase()
                var si = low.indexOf("softap")
                if (si >= 0) {
                    var win = low.slice(si, si + 160)
                    if (win.match(/disabl|stop|idle|inactive|failed/)) root.hotspotOn = false
                    else if (win.match(/enabl|start|active|running/)) root.hotspotOn = true
                }
            }
        }
    }
    Process {
        id: hotspotProc
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { id: hotspotErr; waitForEnd: true }
        onExited: function (code) {
            root.hotspotBusy = false
            if (code === 0) {
                root.hotspotOn = root.hotspotWant
                root.hotspotNote = root.hotspotOn ? "On — join the phone wifi if the link dropped" : "Toggling can drop the link"
                root.say(root.hotspotOn ? "Hotspot on" : "Hotspot off")
            } else {
                var err = (hotspotErr.text.trim().split("\n").pop() || "hotspot failed").slice(0, 90)
                root.say(err)
                root.hotspotNote = "Toggle failed — " + err
            }
            root.refreshDevices()
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
        root.clearSearch()
        root.listRemote()
    }
    // ================= UI =================
    // Type scale: 9 caps label · 11 body · 13 title.  Spacing: 10 between
    // blocks, 12 inside cards.  Every block is full width and left aligned.

    // section caption
    component Cap: Text {
        color: colors.alpha(colors.outline, 0.75)
        font.family: colors.fontSans
        font.pixelSize: 9
        font.weight: Font.Bold
        font.letterSpacing: 1.2
    }

    // flat surface
    component Surface: Rectangle {
        radius: 12
        color: colors.alpha(colors.surfaceVariant, 0.25)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
    }

    // text button — lifts 2px on hover. Uses a transform so it still moves
    // inside layouts (a layout owns x/y).
    component Btn: Rectangle {
        id: btn
        required property string label
        property bool lit: false
        property bool solid: false
        property var tapped: function() {}
        implicitHeight: 32
        implicitWidth: btnText.implicitWidth + 28
        radius: 9
        color: solid ? (btnMa.containsMouse ? colors.alpha(colors.primary, 0.85) : colors.primary)
                     : btnMa.containsMouse ? colors.alpha(colors.primary, 0.16)
                     : lit ? colors.alpha(colors.primary, 0.10) : colors.alpha(colors.surfaceVariant, 0.35)
        border.width: 1
        border.color: solid ? colors.primary : (lit || btnMa.containsMouse) ? colors.alpha(colors.primary, 0.55) : colors.alpha(colors.outline, 0.14)
        transform: Translate {
            y: btnMa.containsMouse ? -2 : 0
            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: btn.solid ? colors.background : btn.lit ? colors.primary : colors.foreground
            font.family: colors.fontSans
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        MouseArea { id: btnMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.tapped() }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        clip: true
        color: colors.alpha(colors.surface, 0.88)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // ── status header ───────────────────────────────
            Surface {
                Layout.fillWidth: true
                Layout.preferredHeight: 58
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 18
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: root.connected ? root.deviceName : root.linkLost ? "Link lost" : "No phone paired"
                            color: root.linkLost ? colors.error : colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.hotspotBusy ? "Switching hotspot, link may drop"
                                : root.connected ? root.deviceId + " · wifi"
                                : root.linkLost ? "Watching, retrying in " + root.reconnectDelay + "s"
                                : "Run adb tcpip 5555 once"
                            color: root.hotspotBusy ? colors.tertiary : root.connected ? colors.alpha(colors.primary, 0.85) : colors.alpha(colors.outline, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    ColumnLayout {
                        visible: root.connected
                        spacing: 2
                        Text {
                            text: root.battery >= 0 ? root.battery + "%" : "…"
                            color: root.battery >= 0 && root.battery < 15 && !root.charging ? colors.error : colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }
                        Text {
                            text: root.charging ? "CHARGING" + (root.plugged !== "" ? " · " + root.plugged : "") : "ON BATTERY"
                            color: root.charging ? colors.primary : colors.alpha(colors.outline, 0.75)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 0.8
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    ColumnLayout {
                        visible: root.connected && root.signalLevel >= 0
                        spacing: 4
                        Item {
                            Layout.alignment: Qt.AlignRight
                            width: 19
                            height: 13
                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    x: index * 5
                                    width: 4
                                    height: 4 + index * 3
                                    y: 13 - height
                                    radius: 1
                                    color: index < root.signalLevel ? colors.primary : colors.alpha(colors.outline, 0.3)
                                }
                            }
                        }
                        Text {
                            text: (root.signalNet !== "" ? root.signalNet + " · " : "") + root.signalLevel + "/4"
                            color: colors.alpha(colors.outline, 0.75)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                    Btn { label: root.connected ? "Re-link" : "Retry"; Layout.preferredHeight: 28; tapped: () => root.refreshDevices() }
                }
            }

            // ── data + hotspot ──────────────────────────────
            RowLayout {
                visible: root.connected
                Layout.fillWidth: true
                spacing: 10
                Surface {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 10
                        anchors.bottomMargin: 12
                        spacing: 4
                        Cap { text: "MOBILE DATA · SINCE REBOOT" }
                        Text { text: root.dataText(); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                        Item { Layout.fillHeight: true }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.surfaceVariant, 0.6)
                            Rectangle {
                                width: root.mobileMb < 0 ? 0 : parent.width * Math.min(1, root.mobileMb / root.dataCapMb)
                                height: parent.height
                                radius: 2
                                color: root.mobileMb / root.dataCapMb > 0.9 ? colors.error : colors.tertiary
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
                Surface {
                    Layout.preferredWidth: 270
                    Layout.preferredHeight: 70
                    color: root.hotspotOn ? colors.alpha(colors.primary, 0.10) : colors.alpha(colors.surfaceVariant, 0.25)
                    border.color: root.hotspotOn ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.12)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Cap { text: "HOTSPOT" }
                            Text {
                                text: root.hotspotBusy ? "Switching…" : root.hotspotOn ? "On" : "Off"
                                color: root.hotspotOn ? colors.primary : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                text: root.hotspotNote
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Btn { label: root.hotspotOn ? "Turn off" : "Turn on"; lit: root.hotspotOn; tapped: () => root.toggleHotspot() }
                    }
                }
            }

            // ── quick actions: five equal columns ───────────
            RowLayout {
                visible: root.connected
                Layout.fillWidth: true
                spacing: 8
                Btn { label: "Ring"; Layout.fillWidth: true; Layout.preferredWidth: 1; tapped: () => root.ringPhone() }
                Btn { label: "Screenshot"; Layout.fillWidth: true; Layout.preferredWidth: 1; tapped: () => root.shotPhone() }
                Btn { label: "Clipboard"; Layout.fillWidth: true; Layout.preferredWidth: 1; tapped: () => root.sendClipboard() }
                Btn { label: root.dndOn ? "DND on" : "DND off"; lit: root.dndOn; Layout.fillWidth: true; Layout.preferredWidth: 1; tapped: () => root.toggleDnd() }
                Btn { label: "Screen " + root.timeoutLabel(); Layout.fillWidth: true; Layout.preferredWidth: 1; tapped: () => root.cycleTimeout() }
            }

            // ── send ────────────────────────────────────────
            RowLayout {
                visible: root.connected
                Layout.fillWidth: true
                Cap { text: "SEND TO PHONE"; Layout.fillWidth: true }
                Text {
                    visible: root.queue.length > 0
                    text: root.queue.length + " in queue"
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                }
                Btn {
                    visible: root.queue.length > 0
                    label: "Clear"
                    Layout.preferredHeight: 24
                    tapped: () => root.clearFinished()
                }
            }
            Surface {
                id: dropTile
                visible: root.connected
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: dropArea.containsMouse || dropArea.containsDrag ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surfaceVariant, 0.25)
                border.color: dropArea.containsMouse || dropArea.containsDrag ? colors.alpha(colors.primary, 0.55) : colors.alpha(colors.outline, 0.12)
                transform: Translate {
                    y: dropArea.containsMouse || dropArea.containsDrag ? -2 : 0
                    Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    spacing: 2
                    Text {
                        text: "Drop files to send"
                        color: dropArea.containsMouse || dropArea.containsDrag ? colors.primary : colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Text {
                        text: "Lands in Download on the phone"
                        color: colors.alpha(colors.outline, 0.7)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                    }
                }
                DropArea {
                    id: dropArea
                    anchors.fill: parent
                    property bool containsMouse: containsDrag
                    keys: ["text/uri-list"]
                    onDropped: function (drop) {
                        var paths = []
                        for (var i = 0; i < drop.urls.length; i++) paths.push(drop.urls[i])
                        root.queueFiles(paths)
                    }
                }
            }
            ListView {
                id: queueList
                visible: root.connected && root.queue.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(2, count) * 30 + Math.max(0, Math.min(2, count) - 1) * 4
                clip: true
                spacing: 4
                model: root.queue
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                onCountChanged: if (count > 0) positionViewAtEnd()
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: queueList.width
                    height: 30
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 8
                        Text {
                            text: modelData.error !== "" ? "×" : modelData.done ? "" : "↑"
                            color: modelData.error !== "" ? colors.error : modelData.done ? colors.secondary : colors.primary
                            font.family: modelData.done && modelData.error === "" ? "Phosphor" : colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            Layout.preferredWidth: 10
                        }
                        Text {
                            text: modelData.error !== "" ? modelData.error : modelData.name
                            color: modelData.error !== "" ? colors.error : colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: modelData.active && modelData.total > 0
                            text: Math.round(100 * modelData.sent / Math.max(1, modelData.total)) + "%"
                            color: colors.primary
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: modelData.error !== ""
                            text: "retry"
                            color: retryMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.75)
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            MouseArea { id: retryMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.retryRow(index) }
                        }
                        Text {
                            visible: modelData.done || modelData.error !== ""
                            text: "×"
                            color: xMa.containsMouse ? colors.error : colors.alpha(colors.outline, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            MouseArea { id: xMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.removeRow(index) }
                        }
                    }
                    Rectangle {
                        visible: modelData.active && !modelData.done
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        height: 3
                        radius: 1.5
                        color: colors.alpha(colors.surfaceVariant, 0.6)
                        Rectangle {
                            width: parent.width * modelData.sent / Math.max(1, modelData.total)
                            height: parent.height
                            radius: 1.5
                            color: colors.primary
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }

            // ── phone browser ───────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Cap { text: "ON THE PHONE · " + root.remoteRows.length; Layout.fillWidth: true }
                Text {
                    visible: root.searching
                    text: "find: " + root.searchBuf + "▍"
                    color: colors.primary
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
                Text {
                    text: root.remoteDir.replace("/sdcard", "phone")
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 200
                }
                Btn {
                    visible: root.selected.length > 0
                    solid: true
                    label: "Pull " + root.selected.length
                    Layout.preferredHeight: 24
                    tapped: () => root.pullSelection()
                }
            }
            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 140
                color: colors.alpha(colors.surface, 0.35)
                clip: true

                Text {
                    visible: !root.connected
                    anchors.centerIn: parent
                    text: root.linkLost ? "Link lost, watching… will re-link on its own" : "Connect a phone to browse it"
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: colors.fontSans
                    font.pixelSize: 11
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
                    highlightMoveDuration: 120
                    highlight: Rectangle { color: colors.alpha(colors.primary, 0.10); radius: 8 }
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
                    header: Item {
                        width: remoteList.width
                        height: root.remoteDir !== "/sdcard" ? 28 : 0
                        visible: root.remoteDir !== "/sdcard"
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: upMa.containsMouse ? colors.alpha(colors.primary, 0.12) : "transparent"
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 28
                            anchors.verticalCenter: parent.verticalCenter
                            text: "‹  up"
                            color: colors.primary
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.enterRemote("..") }
                    }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool isSel: root.selected.indexOf(modelData.name) >= 0
                        width: remoteList.width
                        height: 28
                        radius: 8
                        color: isSel ? colors.alpha(colors.primary, 0.18) : rowMa.containsMouse ? colors.alpha(colors.primary, 0.10) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        transform: Translate {
                            x: rowMa.containsMouse ? 3 : 0
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8
                            Text {
                                text: isSel ? "✓" : ""
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                Layout.preferredWidth: 10
                            }
                            Text {
                                text: modelData.name + (modelData.isDir ? "/" : "")
                                color: isSel || modelData.isDir ? colors.primary : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: modelData.isDir ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: root.pullState === modelData.name
                                text: root.pullTotal > 0 ? Math.round(100 * Math.min(1, root.pullGot / root.pullTotal)) + "%" : "pulling…"
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }
                        Rectangle {
                            visible: root.pullState === modelData.name
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.bottomMargin: 2
                            height: 3
                            radius: 1.5
                            color: colors.alpha(colors.surfaceVariant, 0.6)
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
                                remoteList.currentIndex = index
                                if (modelData.isDir) root.enterRemote(modelData.name)
                                else root.toggleSelect(modelData.name)
                            }
                        }
                    }
                }
            }

            // ── footer: status message replaces the key hints while active ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                Text {
                    anchors.fill: parent
                    visible: root.statusMsg !== ""
                    text: root.statusMsg
                    color: colors.secondary
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    anchors.fill: parent
                    visible: root.statusMsg === ""
                    text: "j/k move · l open · h up · s select · p pull · y yank · / find · r ring · d dnd · t timeout · esc close"
                    color: colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Keys.onPressed: (e) => {
            // type-ahead find: "/" arms, next chars jump, idle or esc disarms
            if (root.searching || e.text === "/") {
                e.accepted = true
                if (e.text === "/") {
                    root.searching = true
                    root.searchBuf = ""
                } else if (e.key === Qt.Key_Backspace) {
                    root.searchBuf = root.searchBuf.slice(0, -1)
                    searchTimer.restart()
                    root.findJump()
                } else if (e.key === Qt.Key_Escape) {
                    root.clearSearch()
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    var fi = remoteList.currentIndex
                    if (fi >= 0 && fi < root.remoteRows.length) {
                        var fr = root.remoteRows[fi]
                        root.clearSearch()
                        if (fr.isDir) root.enterRemote(fr.name)
                        else root.pullFile(fr.name)
                    }
                } else if (e.text.length > 0 && e.text.charCodeAt(0) > 31) {
                    root.searchBuf += e.text
                    searchTimer.restart()
                    root.findJump()
                }
                return
            }
            if (e.key === Qt.Key_Escape) { root.open = false; e.accepted = true; return }
            if (e.text === "p" || e.text === "P") { root.pullSelection(); e.accepted = true; return }
            if (e.text === "S") { root.shotPhone(); e.accepted = true; return }
            if (e.text === "r" || e.text === "R") { root.ringPhone(); e.accepted = true; return }
            if (e.text === "d" || e.text === "D") { root.toggleDnd(); e.accepted = true; return }
            if (e.text === "t" || e.text === "T") { root.cycleTimeout(); e.accepted = true; return }
            if (e.key === Qt.Key_S) {
                var si = remoteList.currentIndex
                if (si < 0 && root.remoteRows.length > 0) si = 0
                if (si >= 0 && si < root.remoteRows.length) {
                    root.toggleSelect(root.remoteRows[si].name)
                    if (si + 1 < root.remoteRows.length) remoteList.currentIndex = si + 1
                }
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_Y) {
                var yi = remoteList.currentIndex
                if (yi < 0 && root.remoteRows.length > 0) yi = 0
                if (yi >= 0 && yi < root.remoteRows.length && !root.remoteRows[yi].isDir) {
                    root.yankAfterPull = true
                    root.pullFile(root.remoteRows[yi].name)
                }
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_C) { root.sendClipboard(); e.accepted = true; return }
            if (e.key === Qt.Key_J) {
                var nj = root.remoteRows.length
                if (nj > 0) remoteList.currentIndex = (remoteList.currentIndex + 1) % nj
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_K) {
                var nk = root.remoteRows.length
                if (nk > 0) remoteList.currentIndex = remoteList.currentIndex < 0 ? nk - 1 : (remoteList.currentIndex - 1 + nk) % nk
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_L) {
                var li = remoteList.currentIndex
                if (li >= 0 && li < root.remoteRows.length) {
                    if (root.remoteRows[li].isDir) root.enterRemote(root.remoteRows[li].name)
                    else root.pullFile(root.remoteRows[li].name)
                }
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_H) { root.enterRemote(".."); e.accepted = true; return }
            if (e.key === Qt.Key_Home || e.text === "g") {
                if (root.remoteRows.length > 0) remoteList.currentIndex = 0
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_End || e.text === "G") {
                if (root.remoteRows.length > 0) remoteList.currentIndex = root.remoteRows.length - 1
                e.accepted = true
                return
            }
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                var ri = remoteList.currentIndex
                if (ri >= 0 && ri < root.remoteRows.length) {
                    if (root.remoteRows[ri].isDir) root.enterRemote(root.remoteRows[ri].name)
                    else root.pullFile(root.remoteRows[ri].name)
                }
                e.accepted = true
                return
            }
        }
        focus: root.open
    }
}
