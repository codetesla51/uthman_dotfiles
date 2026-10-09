import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PhoneBridge — wireless file sender over ADB. Thin client over the standalone
// ~/phonebridge backend (daemon CLI: devices, battery, clip, push, pull, ls,
// shot, ring, inbox-sync, notifs). No app on the phone, no cable after the
// one-time `tcpip` bootstrap: drop files and they land in Download, browse
// the phone and pull anything back. Toggle: ipc call phonebridge (SUPER ALT K).
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
    // standalone backend (~/phonebridge repo): all adb orchestration lives there
    property string daemon: Quickshell.env("HOME") + "/phonebridge/phonebridge"
    property string pcDest: Quickshell.env("HOME") + "/PhoneBridge"

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
    property string remoteDir: "/sdcard"
    property var remoteRows: []         // [{name, isDir}]
    property string pullState: ""       // name pulling, "" when idle
    property int pullTotal: 0
    property int pullGot: 0
    property var selected: []
    property var pullQueue: []
    property bool yankAfterPull: false

    // --- battery + shot ---
    property int battery: -1
    property bool charging: false
    property string shotName: ""
    property string plugged: ""         // USB | AC | Wireless (dumpsys battery)
    property string signalNet: ""       // LTE / 5G / "" unknown
    property int signalLevel: -1        // 0..4, -1 unknown
    property double mobileMb: -1        // phone cell counters, since reboot
    property double dataCapMb: 2048
    property bool hotspotOn: false
    property string hotspotNote: "Toggling can drop the link"
    property bool hotspotBusy: false
    property bool hotspotWant: false
    property bool dndOn: false
    property int screenTimeout: 60000   // ms

    // --- type-ahead find ---
    property bool searching: false
    property string searchBuf: ""

    // --- notify forward allowlist lives in the daemon config ---
    // (~/.config/phonebridge/config.ini [notify]); the daemon filters + extracts
    // senders, this client only pings.
    property var seenKeys: []        // notification keys already pinged
    property bool primed: false      // first scan after connect absorbs, no pings
    property int pollStart: 0        // ms epoch when the current dump started (stale-poll watchdog)

    title: "PhoneBridge"
    implicitWidth: 700
    implicitHeight: 700
    minimumSize: Qt.size(700, 700)
    maximumSize: Qt.size(700, 700)
    color: "transparent"
    visible: root.open || closeAnim.running

    IpcHandler { target: "phonebridge"; function toggle(): void { root.open = !root.open } }

    // connect at bar startup so inbox/notif watchers run with the panel closed
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

    // shell-quote one argument so names with spaces/quotes survive `adb shell`
    function sq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function clearSearch() {
        root.searching = false
        root.searchBuf = ""
    }

    // type-ahead: jump to the first entry whose name starts with the buffer
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

    // battery via the daemon (JSON: {level, charging})
    function refreshBattery() {
        if (!root.connected) return
        batteryProc.command = [root.daemon, "battery"]
        batteryProc.running = true
    }

    // ── notify forward: the daemon polls the shade and returns parsed records
    // [{key, label, title, sender}]. Works in DND too — DND silences the
    // phone, it does not remove entries from the shade. The desktop ping goes
    // through notify-send to quickshell's own NotificationCenter (owns
    // org.freedesktop.Notifications). First scan after connect absorbs.
    function scanNotifs(fresh) {
        if (!root.primed) {
            // first scan after connect: absorb what is already in the shade,
            // do not re-ping old notifications
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
            Quickshell.execDetached(["notify-send", "-a", f.label,
                who, body])
        }
    }

    // find-my-phone via the daemon: wake, max media volume, ringtone VIEW
    // intent (best-effort), vibration burst (the audible carrier on builds
    // with no media session/ringtones).
    function ringPhone() {
        if (!root.connected) { root.say("No phone connected — same WiFi as the laptop?"); return }
        root.say("Ringing phone…")
        ringProc.command = [root.daemon, "ring"]
        ringProc.running = true
    }

    // phone screenshot -> ~/Pictures/PhoneBridge (daemon names the file)
    function shotPhone() {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        root.say("Snapping shot…")
        shotProc.command = [root.daemon, "shot"]
        shotProc.running = true
    }

    // --- phone settings + radio (direct adb, same pattern as progressProc) ---
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
        dndSetProc.command = root.adbArgs(["settings", "put", "global", "zen_mode", root.dndOn ? "1" : "0"])
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
    // The daemon owns pairing state (~/.config/phonebridge/config.ini, written
    // by ~/phonebridge/init.sh). If nothing is attached we ask it to connect
    // to the remembered target; first-time Wi-Fi needs `adb tcpip 5555` once.
    // The daemon bounds every adb call (connect 8s), and the watchdog below
    // is the backstop for a wedged daemon: without it a hung discovery leaves
    // busy=true forever and the panel looks frozen instead of unreachable.
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

    // auto-reconnect: phone rebooted, walked out of WiFi range, adbd dozed —
    // keep knocking with a backoff (10s → 60s cap) instead of waiting for a
    // manual retry. Resets the moment a device answers. Only while open.
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
                    // several devices can be visible (cable + wifi): prefer the paired one
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
                    root.reconnectDelay = 10
                    reconnectTimer.interval = 10000
                    root.refreshBattery()
                    if (root.remoteRows.length === 0) root.listRemote()
                    root.refreshPhoneState()
                    return
                }
                // nothing attached: fall through to remembered-target connect
                if (!root.connected) {
                    root.connectTo("")
                } else {
                    root.connected = false
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

    // ── notify forward watcher: poll the shade every 4s while a phone is paired
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
                // stale poll (hung adb on flaky wifi): stop it so the next tick restarts
                if (now - root.pollStart > 10000) notifProc.running = false
                return
            }
            root.pollStart = now
            // the daemon truncates + greps the ~1 MB --noredact dump phone-side
            // and returns parsed records (~5 KB/s)
            notifProc.command = [root.daemon, "notifs"]
            notifProc.running = true
        }
    }

    // ── inbox auto-delivery: the daemon pulls new share-sheet files into
    // ~/Downloads itself (dedupe by name+size, >250 MB stays in the browser).
    // This client just announces arrivals.
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
            // don't fight a manual browser pull
            if (inboxSyncProc.running || root.pullState !== "" || root.pullQueue.length > 0) return
            inboxSyncProc.command = [root.daemon, "inbox-sync"]
            inboxSyncProc.running = true
        }
    }

    // one-shot runner for the ring sequence
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
                // daemon pushes + fires the media scanner; stdout is JSON (ignored here)
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
    // C: PC clipboard straight into the phone's clipboard (paste-ready).
    // Clipboard *reading* stays here (wl-paste is compositor-specific); the
    // daemon takes the bytes via --file. Text goes through the PhoneRelay
    // flash app; images push straight into Download. Caveat (verified): this
    // ROM's clipboard watcher reaps clips set by the relay app within
    // ~seconds of idle — paste right away.
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
        // dirs have no meaningful single size — leave pullTotal 0 for the indeterminate bar
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
    // plugged type from dumpsys battery (daemon owns level/charging)
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
    // cell net + bars from the registry dump (unknowns stay hidden)
    Process {
        id: signalProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lv = text.match(/level=(\d)/)
                root.signalLevel = lv ? Math.min(4, parseInt(lv[1])) : -1
                var net = text.match(/(5G|LTE|NR|WCDMA|HSPA|UMTS|EDGE|GSM|CDMA)/)
                root.signalNet = net ? (net[1] === "NR" ? "5G" : net[1]) : ""
            }
        }
    }
    // mobile bytes: rmnet/ccmni/qmap only (wlan/tun/clat would double-count)
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
                    if (!iface.match(/^(rmnet|ccmni|qmap)/)) continue
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
    }    Process {
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
    // softap status: best-effort grep, keeps the assumed state on no match
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
    }    function enterRemote(name) {
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
    // bento glyph chip: circle, accent-tinted fill/border, nerd glyph (house style)
    component GlyphChip: Rectangle {
        required property string glyph
        property string fontFam: ""
        property var tapped: function() {}
        property color accent: colors.primary
        property int px: 26
        implicitWidth: px
        implicitHeight: px
        radius: px / 2
        color: colors.alpha(accent, 0.15)
        border.width: 1
        border.color: colors.alpha(accent, 0.3)
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: chipHover.containsMouse ? colors.primary : parent.accent
            font.family: parent.fontFam !== "" ? parent.fontFam : colors.fontSans
            font.pixelSize: 12
        }
        MouseArea { id: chipHover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tapped() }
    }

    // action tile: phosphor glyph + label, lifts on hover (house motion)
    component ActionTile: Rectangle {
        id: tile
        required property string glyph
        required property string label
        property var tapped: function() {}
        property bool lit: false
        implicitWidth: tileRow.implicitWidth + 22
        implicitHeight: 30
        radius: 10
        color: tileMa.containsMouse ? colors.alpha(colors.primary, 0.14) : colors.alpha(colors.surfaceVariant, 0.25)
        border.width: 1
        border.color: lit ? colors.alpha(colors.primary, 0.55) : tileMa.containsMouse ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.12)
        scale: tileMa.containsMouse ? 1.05 : 1
        y: tileMa.containsMouse ? -2 : 0
        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        RowLayout {
            id: tileRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: tile.glyph; color: tile.lit ? colors.primary : colors.alpha(colors.primary, 0.85); font.family: "Phosphor"; font.pixelSize: 14 }
            Text { text: tile.label; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
        }
        MouseArea { id: tileMa; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tapped() }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        clip: true
        color: colors.alpha(colors.surface, 0.88)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        // bezier pair — open pops with overshoot bounce (fast), close hurries
        // out with none. Same curves as the notification drawer.
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
            anchors.margins: 14
            spacing: 8

            // device row — dot, name/link, battery/charge, signal, relink
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Text {
                        text: root.connected ? root.deviceName : "No phone paired"
                        color: root.connected ? colors.foreground : colors.alpha(colors.outline, 0.8)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.hotspotBusy ? "switching hotspot" : root.connected ? (root.deviceId + " · wifi") : "adb tcpip 5555 once"
                        color: root.hotspotBusy ? colors.tertiary : root.connected ? colors.alpha(colors.primary, 0.8) : colors.alpha(colors.outline, 0.45)
                        font.family: colors.fontSans
                        font.pixelSize: 8
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                ColumnLayout {
                    visible: root.connected
                    spacing: 0
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: "" + (root.battery >= 0 ? root.battery + "%" : "…")
                        color: root.charging ? colors.primary : root.battery < 15 && root.battery >= 0 ? colors.error : colors.foreground
                        font.family: "Phosphor"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignRight
                    }
                    Text {
                        text: root.charging ? ("CHARGING" + (root.plugged !== "" ? " · " + root.plugged : "")) : "ON BATTERY"
                        color: root.charging ? colors.primary : colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                        Layout.alignment: Qt.AlignRight
                    }
                }
                ColumnLayout {
                    visible: root.connected && root.signalLevel >= 0
                    spacing: 0
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: ""
                        color: colors.primary
                        font.family: "Phosphor"
                        font.pixelSize: 11
                        Layout.alignment: Qt.AlignRight
                    }
                    Text {
                        text: (root.signalNet !== "" ? root.signalNet + " · " : "") + root.signalLevel + "/4"
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignRight
                    }
                }
                GlyphChip { visible: root.connected; glyph: ""; fontFam: "Phosphor"; px: 22; accent: colors.primary; Layout.alignment: Qt.AlignVCenter; tapped: () => root.refreshDevices() }
            }
            // ---- DATA + HOTSPOT ----
            RowLayout {
                visible: root.connected
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    radius: 12
                    color: colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.topMargin: 7
                        anchors.bottomMargin: 8
                        spacing: 3
                        Text { text: "MOBILE DATA · SINCE REBOOT"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Text { text: root.dataText(); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.surfaceVariant, 0.5)
                            Rectangle {
                                width: root.mobileMb < 0 ? 0 : parent.width * Math.min(1, root.mobileMb / root.dataCapMb)
                                height: parent.height
                                radius: 2
                                color: colors.tertiary
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 148
                    Layout.preferredHeight: 54
                    radius: 12
                    color: root.hotspotOn ? colors.alpha(colors.primary, 0.10) : colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: root.hotspotOn ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.12)
                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        anchors.topMargin: 7
                        anchors.bottomMargin: 8
                        spacing: 3
                        Text { text: "HOTSPOT"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: root.hotspotBusy ? "…" : root.hotspotOn ? "On" : "Off"; color: root.hotspotOn ? colors.primary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; Layout.fillWidth: true }
                            GlyphChip { glyph: ""; fontFam: "Phosphor"; px: 22; accent: root.hotspotOn ? colors.primary : colors.outline; tapped: () => root.toggleHotspot() }
                        }
                    }
                }
            }
            Text {
                visible: root.connected
                text: root.hotspotNote
                color: colors.alpha(colors.outline, 0.5)
                font.family: colors.fontSans
                font.pixelSize: 7
                Layout.alignment: Qt.AlignHCenter
            }

            // ---- ACTIONS ----
            Flow {
                visible: root.connected
                Layout.fillWidth: true
                spacing: 6
                ActionTile { glyph: ""; label: "Ring"; tapped: () => root.ringPhone() }
                ActionTile { glyph: ""; label: "Shot"; tapped: () => root.shotPhone() }
                ActionTile { glyph: ""; label: "Clip"; tapped: () => root.sendClipboard() }
                ActionTile { glyph: ""; label: root.dndOn ? "DND on" : "DND"; lit: root.dndOn; tapped: () => root.toggleDnd() }
                ActionTile { glyph: ""; label: root.timeoutLabel(); tapped: () => root.cycleTimeout() }
            }
            // ---- SEND: drop zone tile ----
            RowLayout {
                Layout.fillWidth: true
                Text { text: "SEND TO PHONE"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
            }

            Rectangle {
                id: dropTile
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                radius: 14
                color: dropArea.containsMouse ? colors.alpha(colors.primary, 0.12) : colors.alpha(colors.surfaceVariant, 0.25)
                border.width: 1
                border.color: dropArea.containsMouse ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.1)
                scale: dropArea.containsMouse ? 1.02 : 1
                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    Rectangle {
                        width: 44
                        height: 44
                        radius: 22
                        color: colors.alpha(colors.primary, dropArea.containsMouse ? 0.22 : 0.12)
                        border.width: 1
                        border.color: colors.alpha(colors.primary, dropArea.containsMouse ? 0.5 : 0.22)
                        Text {
                            anchors.centerIn: parent
                            text: "󰈔"
                            color: dropArea.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.8)
                            font.family: colors.fontSans
                            font.pixelSize: 22
                            scale: dropArea.containsMouse ? 1.1 : 1
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 180 } }
                        }
                    }
                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Drop files here"
                            color: dropArea.containsMouse ? colors.primary : colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: root.connected ? "lands in Download" : "no phone connected"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: colors.fontSans
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
                    Text { text: "QUEUE (" + root.queue.length + ")"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                    Text {
                        text: "clear done"
                        color: clearMa.containsMouse ? colors.primary : colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearFinished() }
                    }
                }
                ListView {
                    id: queueList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(2 * 36, count * 36)
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
                                font.family: colors.fontSans
                                font.pixelSize: 10
                            }
                            Text {
                                text: modelData.error !== "" ? modelData.error : modelData.name
                                color: modelData.error !== "" ? colors.error : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                visible: modelData.active && modelData.total > 0
                                text: Math.round(100 * modelData.sent / Math.max(1, modelData.total)) + "%"
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                            Text {
                                visible: modelData.error !== ""
                                text: "retry"
                                color: retryMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.75)
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.retryRow(index) }
                            }
                            Text {
                                visible: modelData.done || modelData.error !== ""
                                text: "×"
                                color: xMa.containsMouse ? colors.error : colors.alpha(colors.outline, 0.55)
                                font.family: colors.fontSans
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
                Text { text: "ON THE PHONE (" + root.remoteRows.length + ")"; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text {
                    text: root.remoteDir.replace("/sdcard", "phone")
                    color: colors.alpha(colors.outline, 0.55)
                    font.family: colors.fontSans
                    font.pixelSize: 8
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 120
                }
                Text {
                    visible: root.searching
                    text: "find: " + root.searchBuf + "▍"
                    color: colors.primary
                    font.family: colors.fontSans
                    font.pixelSize: 8
                    font.weight: Font.Bold
                }
                Text {
                    visible: root.selected.length > 0 && !root.searching
                    text: root.selected.length + " sel"
                    color: selMa.containsMouse ? colors.primary : colors.tertiary
                    font.family: colors.fontSans
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    MouseArea { id: selMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.pullSelection() }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 340
                Layout.minimumHeight: 200
                radius: 14
                color: colors.alpha(colors.surface, 0.35)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.12)
                clip: true

                Text {
                    visible: !root.connected
                    anchors.centerIn: parent
                    text: "connect a phone to browse it"
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: colors.fontSans
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
                    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
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
                                font.family: colors.fontSans
                                font.pixelSize: 11
                            }
                            Text {
                                text: modelData.name
                                color: root.selected.indexOf(modelData.name) >= 0 ? colors.primary : colors.foreground
                                font.family: colors.fontSans
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
                                remoteList.currentIndex = index
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
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                        MouseArea { id: upMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.enterRemote("..") }
                    }
                }
            }

            RowLayout {
                visible: root.connected
                Layout.fillWidth: true
                Text {
                    text: "j/k move · l open · p pull · s sel · S shot · y yank · c clip · r ring · d dnd · t timeout · g/G ends · h up · / find · esc close"
                    color: colors.alpha(colors.outline, 0.4)
                    font.family: colors.fontSans
                    font.pixelSize: 7
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            // status pill — transient messages, bottom-anchored
            Rectangle {
                visible: root.statusMsg !== ""
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                radius: 11
                color: colors.alpha(colors.secondary, 0.12)
                border.width: 1
                border.color: colors.alpha(colors.secondary, 0.2)
                Text {
                    anchors.centerIn: parent
                    text: root.statusMsg
                    color: colors.secondary
                    font.family: colors.fontSans
                    font.pixelSize: 8
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }
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
                    root.searchTimer.restart()
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
                    root.searchTimer.restart()
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
