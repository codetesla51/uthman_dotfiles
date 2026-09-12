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

    // --- battery + shot ---
    property int battery: -1
    property bool charging: false
    property string shotName: ""

    // --- type-ahead find ---
    property bool searching: false
    property string searchBuf: ""

    // --- notify forward allowlist ---
    // package substring -> desktop app label; anything matching gets a toast
    property var notifyApps: [
        { pkg: "whatsapp", name: "WhatsApp" },
        { pkg: "telegram", name: "Telegram" },
        { pkg: "messages", name: "Messages" },
        { pkg: "messaging", name: "SMS" },
        { pkg: "sms", name: "SMS" },
        { pkg: "mms", name: "SMS" }
    ]
    property var seenKeys: []        // notification keys already pinged
    property bool primed: false      // first scan after connect absorbs, no pings
    property int pollStart: 0        // ms epoch when the current dump started (stale-poll watchdog)

    title: "PhoneLink"
    width: 400
    height: 520
    minimumSize: Qt.size(360, 480)
    maximumSize: Qt.size(460, 620)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "phonelink"; function toggle(): void { root.open = !root.open } }

    function say(text) {
        root.statusMsg = text
        statusLife.restart()
    }
    Timer { id: statusLife; interval: 5000; onTriggered: root.statusMsg = "" }
    Timer { id: searchTimer; interval: 1200; onTriggered: root.clearSearch() }

    function notify(title, body) {
        Quickshell.execDetached(["sh", "-c", "notify-send -u normal -i phone '" + String(title).replace(/'/g, "'\\''") + "' '" + String(body).replace(/'/g, "'\\''") + "'"])
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

    // battery: dumpsys battery is read-only with no path args — no quoting needed
    function refreshBattery() {
        if (!root.connected) return
        batteryProc.command = ["adb", "-s", root.deviceId, "shell", "dumpsys", "battery"]
        batteryProc.running = true
    }

    // ── notify forward: poll the notification shade, ping the desktop on new
    // entries from allowlisted apps. Works in DND too — DND silences the
    // phone, it does not remove entries from the shade. The desktop ping goes
    // through notify-send to quickshell's own NotificationCenter (owns
    // org.freedesktop.Notifications).
    function scanNotifs(dump) {
        function flush() { if (cur && cur.key) fresh.push(cur); cur = null }
        var lines = String(dump).split("\n")
        var cur = null
        var fresh = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var h = line.match(/NotificationRecord\([^:]*: pkg=([^\s]+)/)
            if (h) {
                flush()
                for (var a = 0; a < root.notifyApps.length; a++)
                    if (h[1].indexOf(root.notifyApps[a].pkg) !== -1) {
                        cur = { key: (line.match(/key=([^:\s]+)/) || [])[1] || null, title: "", label: root.notifyApps[a].name }
                        break
                    }
                continue
            }
            if (!cur) continue
            cur.key = cur.key || (line.match(/key=([^:\s]+)/) || [])[1] || null
            if (!cur.title) { var t = line.match(/android\.title=String \(([^)]*)\)/); if (t) cur.title = t[1] }
        }
        flush()
        for (var j = 0; j < fresh.length; j++) {
            var rec = fresh[j]
            // w4b embeds the author in group-chat titles:
            // "Group (149 messages): ~ Jay"; 1:1 titles are the contact
            // themselves, channels have no suffix at all
            rec.sender = ""
            if (rec.label === "WhatsApp" && rec.title) {
                var sm = rec.title.match(/[:：]\s*~?\s*(.+)$/)
                if (sm) {
                    var tail = sm[1].trim().replace(/\)\s*$/, "").trim()
                    if (tail && !/^\s*\d/.test(tail) && tail.length <= 30) rec.sender = tail
                }
            }
        }
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
            Quickshell.execDetached(["notify-send", "-a", f.label,
                f.title || "New " + f.label + " notification",
                f.sender ? "from " + f.sender : ""])
        }
    }

    // find-my-phone: wake, max media volume, try the ringtone, buzz hard.
    // Probed on this device: the `media` tool and /system/media/audio/ringtones
    // do not exist, no media session to resume, shell notification posts play
    // no sound — so the vibration burst is the audible carrier; the ringtone
    // VIEW intent is best-effort (no player handles it on this build).
    function ringPhone() {
        if (!root.connected) { root.say("No phone connected — same WiFi as the laptop?"); return }
        root.say("Ringing phone…")
        ringProc.command = ["sh", "-c",
            "a=adb; i=" + root.sq(root.deviceId) + "; " +
            "$a -s $i shell input keyevent 224; " +                                  // wake
            "$a -s $i shell cmd media_session volume --stream 3 --set 15; " +        // media volume max
            "$a -s $i shell am start -a android.intent.action.VIEW -d content://settings/system/ringtone; " +
            "$a -s $i shell cmd vibrator_manager synced -f oneshot 400 255; sleep 0.35; " +
            "$a -s $i shell cmd vibrator_manager synced -f oneshot 400 255; sleep 0.35; " +
            "$a -s $i shell cmd vibrator_manager synced -f oneshot 400 255"]
        ringProc.running = true
    }

    // phone screenshot -> ~/Pictures/PhoneLink
    function shotPhone() {
        if (!root.connected) {
            root.say("No phone connected — same WiFi as the laptop?")
            return
        }
        var shots = Quickshell.env("HOME") + "/Pictures/PhoneLink"
        var d = new Date()
        function p2(n) { return (n < 10 ? "0" : "") + n }
        root.shotName = "phonelink-" + d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) +
            "-" + p2(d.getHours()) + p2(d.getMinutes()) + p2(d.getSeconds()) + ".png"
        root.say("Snapping shot…")
        shotProc.command = ["sh", "-c",
            "mkdir -p " + root.sq(shots) + " && adb -s " + root.sq(root.deviceId) +
            " exec-out screencap -p > " + root.sq(shots + "/" + root.shotName)]
        shotProc.running = true
    }

    // ================= discovery =================
    // Remembered target first (~/.config/phone-sender/target); if that fails we
    // say how to bootstrap over USB. No gateway guessing — the phone is a
    // device on the LAN, not the hotspot router.

    FileView {
        id: rememberedFile
        path: Quickshell.env("HOME") + "/.config/phone-sender/target"
        printErrors: false
        blockLoading: true
        onLoaded: root.remembered(text())
        onLoadFailed: root.say("No phone pair — USB cable once: adb tcpip 5555, then reconnect")
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
            root.say("No phone pair — USB cable once: adb tcpip 5555, then reconnect")
        }
    }

    function refreshDevices() {
        if (root.busy) return
        root.busy = true
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["adb", "devices", "-l"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.busy = false
                var lines = text.trim().split("\n")
                var found = []
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/^(\S+)\s+device\b/)
                    if (m) {
                        var mod = lines[i].match(/\bmodel:(\S+)/)
                        found.push({ id: m[1], name: mod ? mod[1].replace(/_/g, " ") : "Phone" })
                        continue
                    }
                    if (!root.connected && lines[i].match(/^(\S+)\s+unauthorized/)) {
                        root.say("Accept the RSA prompt on your phone (cable once)")
                    }
                }
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
                    root.refreshBattery()
                    if (root.remoteRows.length === 0) root.listRemote()
                    return
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
        onExited: function (code) {
            if (code === 127) root.say("adb not installed — sudo pacman -S android-tools")
        }
    }

    // ── notify forward watcher: poll the shade every 4s while a phone is paired
    Process {
        id: notifProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.scanNotifs(text)
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
                // stale poll (hung adb on flaky wifi): kill so the next tick restarts
                if (now - root.pollStart > 10000) notifProc.kill()
                return
            }
            root.pollStart = now
            // phone-side filter: the full --noredact dump is ~1 MB; we only
            // consume record headers + key= + android.title lines, so truncate
            // the Notification(...) blob and grep to ~19 KB per poll (~5 KB/s)
            notifProc.command = ["adb", "-s", root.deviceId, "shell",
                "dumpsys notification --noredact | sed 's/ Notification(.*//' | grep -E 'NotificationRecord\\(|key=|android.title'"]
            notifProc.running = true
        }
    }

    // one-shot runner for the ring sequence
    Process { id: ringProc }


    Timer { interval: 15000; running: root.open; repeat: true; triggeredOnStart: false; onTriggered: { root.refreshDevices(); root.refreshBattery() } }
    onOpenChanged: { if (open) { root.refreshDevices(); root.refreshBattery(); remoteList.focus = true } }

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
                root.notify("Sent to " + root.deviceName, row.name)
                root.say("Sent " + row.name)
                root.scanMedia("/sdcard/Download/" + row.name)
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

    // ── media scan: adb push bypasses MediaStore, so a freshly pushed file is
    // invisible in Recents/Photos/Downloads until the scanner notices it.
    // Fire the per-file MEDIA_SCANNER broadcast right after each push succeeds.
    Process {
        id: scanProc
    }

    Process {
        id: batteryProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lv = text.match(/level:\s*(\d+)/)
                var st = text.match(/status:\s*(\d+)/)
                root.battery = lv ? parseInt(lv[1]) : -1
                root.charging = st ? parseInt(st[1]) === 2 : false
            }
        }
    }
    Process {
        id: shotProc
        onExited: function (code) {
            if (code === 0) {
                root.notify("Phone shot", root.shotName)
                root.say("Shot saved to Pictures/PhoneLink")
            } else {
                root.say("Shot failed — screen on and unlocked?")
            }
        }
    }
    function scanMedia(remotePath) {
        var uri = "file://" + encodeURIComponent(remotePath).replace(/%2F/g, "/")
        scanProc.command = ["adb", "-s", root.deviceId, "shell",
            "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d " + root.sq(uri)]
        scanProc.running = true
    }

    Process {
        id: clipSetProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text
                if (t.indexOf("CLIP_IMG_OK") !== -1) root.say("Image on your phone — saved in Download")
                else if (t.indexOf("CLIP_SET_OK") !== -1) root.say("On your phone's clipboard")
                else if (t.indexOf("CLIP_EMPTY") !== -1) root.say("Clipboard is empty (or not text/image)")
                else if (t.indexOf("CLIP_TOOLONG") !== -1) root.say("Too long for direct set (100KB max)")
                else if (t.indexOf("CLIP_FAIL") !== -1) root.say("Image push failed — screen on and unlocked?")
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
            "D=" + q(root.deviceId) + "; F=" + q(clipFile) + "; J=" + q(jarDir) + "; I=/tmp/.qs-phonelink-img.png; " +
            "case \"$(wl-paste --list-types 2>/dev/null)\" in *image*) " +
            "wl-paste -t image/png > \"$I\" 2>/dev/null; " +
            "if [ ! -s \"$I\" ]; then echo CLIP_EMPTY; exit 0; fi; " +
            "TS=$(date +%H%M%S); " +
            "adb -s \"$D\" push \"$I\" \"/sdcard/Download/clipboard-$TS.png\" >/dev/null 2>&1 && " +
            "{ adb -s \"$D\" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d \"file:///sdcard/Download/clipboard-$TS.png\" >/dev/null 2>&1; echo CLIP_IMG_OK; } || echo CLIP_FAIL;; " +
            "*) " +
            "wl-paste -t text/plain --no-newline > \"$F\" 2>/dev/null || { echo CLIP_EMPTY; exit 0; }; " +
            "n=$(wc -c < \"$F\"); " +
            "if [ \"$n\" -eq 0 ]; then echo CLIP_EMPTY; exit 0; fi; " +
            "if [ \"$n\" -gt 100000 ]; then echo CLIP_TOOLONG; exit 0; fi; " +
            "adb -s \"$D\" shell 'test -x /data/local/tmp/clip' >/dev/null 2>&1 || " +
            "{ adb -s \"$D\" push \"$J/clip.jar\" \"$J/clip\" /data/local/tmp >/dev/null 2>&1 && " +
            "adb -s \"$D\" shell chmod 755 /data/local/tmp/clip >/dev/null 2>&1; }; " +
            "adb -s \"$D\" shell 'T=$(cat); /data/local/tmp/clip \"$T\"' < \"$F\" >/dev/null 2>&1 && echo CLIP_SET_OK || echo CLIP_SET_FAIL;; " +
            "esac"]
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
        lsProc.command = ["adb", "-s", root.deviceId, "shell", "ls", "-p", root.sq(root.remoteDir)]
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
        if (!root.connected) return
        if (root.pullState !== "") {
            root.say("Busy — pulling " + root.pullState + "…")
            return
        }
        root.pullState = name
        root.pullTotal = 0
        root.pullGot = 0
        root.say("Pulling " + name + "…")
        sizeRemoteProc.command = ["adb", "-s", root.deviceId, "shell", "stat", "-c", "%s", root.sq(root.remoteDir + "/" + name)]
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
        root.clearSearch()
        root.listRemote()
    }

    // ================= UI =================
    // bento glyph chip: circle, accent-tinted fill/border, nerd glyph (house style)
    component GlyphChip: Rectangle {
        required property string glyph
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
            font.family: colors.fontSans
            font.pixelSize: 12
        }
        MouseArea { id: chipHover; anchors.fill: parent; hoverEnabled: true; onClicked: parent.tapped() }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        clip: true
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // device card — phone identity + battery + actions (bento)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 12
                color: colors.alpha(colors.surfaceVariant, root.connected ? 0.30 : 0.16)
                border.width: 1
                border.color: colors.alpha(colors.outline, root.connected ? 0.14 : 0.10)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 8
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8
                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: colors.alpha(root.connected ? colors.primary : colors.outline, root.connected ? 0.15 : 0.08)
                        border.width: 1
                        border.color: colors.alpha(root.connected ? colors.primary : colors.outline, root.connected ? 0.30 : 0.14)
                        Text {
                            anchors.centerIn: parent
                            text: "󰪜"
                            color: root.connected ? colors.primary : colors.alpha(colors.outline, 0.6)
                            font.family: colors.fontSans
                            font.pixelSize: 18
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: root.connected ? root.deviceName : "No phone paired"
                            color: root.connected ? colors.foreground : colors.alpha(colors.outline, 0.8)
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.connected ? ("adb · " + root.deviceId) : "USB cable once: adb tcpip 5555"
                            color: colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans
                            font.pixelSize: 8
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    // battery pill
                    Rectangle {
                        visible: root.connected && root.battery >= 0
                        Layout.preferredWidth: 46
                        Layout.fillHeight: true
                        radius: 9
                        color: root.battery < 15 ? colors.alpha(colors.error, 0.15) : colors.alpha(colors.tertiary, 0.12)
                        border.width: 1
                        border.color: root.battery < 15 ? colors.alpha(colors.error, 0.3) : colors.alpha(colors.tertiary, 0.25)
                        Text {
                            anchors.centerIn: parent
                            text: root.battery + "%"
                            color: root.battery < 15 ? colors.error : colors.tertiary
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            font.weight: Font.ExtraBold
                        }
                    }
                    Rectangle {
                        visible: root.connected && root.battery < 0
                        Layout.preferredWidth: 46
                        Layout.fillHeight: true
                        radius: 9
                        color: colors.alpha(colors.outline, 0.08)
                        Text {
                            anchors.centerIn: parent
                            text: "…"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: colors.fontSans
                            font.pixelSize: 10
                        }
                    }
                    GlyphChip { visible: root.connected; glyph: "󰉏"; px: 30; accent: colors.primary; Layout.alignment: Qt.AlignVCenter; tapped: () => root.shotPhone() }
                    GlyphChip { visible: root.connected; glyph: "󰳨"; px: 30; accent: colors.tertiary; Layout.alignment: Qt.AlignVCenter; tapped: () => root.ringPhone() }
                }
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
                Layout.preferredHeight: 280
                Layout.minimumHeight: 120
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
                    text: "j/k move · l open · p pull · s sel · y yank · c clip · g/G ends · h up · / find · esc close"
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
