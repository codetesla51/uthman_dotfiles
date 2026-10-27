import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// PixelBot — flat 2D pixel bot. One instance owns the `bot` IPC target;
// the Control Center instance disables the handler and runs only while open.
//
// It wanders, dances with music and reacts to CPU, battery, recording,
// network, mute, idle and focus state. The same state names are exposed for
// both the bar and the Control Center:
//
//     ipc call bot ping
//     ipc call bot ok
//     ipc call bot fail
//     ipc call bot hello
//     ipc call bot focus true
//     ipc call bot force dance
//     ipc call bot clear
//     ipc call bot status
Item {
    id: root

    property var colors

    // ---------- settings ----------
    property int pixelScale: 2
    property int roamWidth: 56                  // 16 = no roaming
    property int cpuBusyAt: 80
    property int batteryLowAt: 15
    property int awayAfterSeconds: 180
    property string recorders: "meetcap|wf-recorder|wl-screenrec|obs"
    property bool helloOnWorkspace: false
    property string forced: ""
    property bool active: true                  // pause clock/poller when the panel is closed
    property bool registerIpc: true             // only one instance may own target "bot"
    property bool moodSounds: true              // only one instance should speak
    property bool soundEnabled: true
    property bool soundReady: false             // suppresses the startup state chirp
    property real lastSoundAt: 0
    readonly property string soundDir: Quickshell.env("HOME") + "/.config/quickshell/assets/pixelbot/"
    // Idle/walk are ambient and would chirp constantly; every other state has
    // a sine sound from the "Sine waves only" sound set.
    readonly property var audibleMoods: [
        "alert", "error", "happy", "lowbat", "recording", "busy",
        "offline", "charging", "dance", "focus", "muted", "sleepy", "hello"
    ]

    readonly property bool roam: roamWidth > 16
    readonly property int stageW: roam ? roamWidth : 16
    implicitWidth: stageW * pixelScale
    implicitHeight: 16 * pixelScale

    // ---------- state fed by events and the poller ----------
    property int cpu: 0
    property int battery: 100
    property bool charging: false
    property bool discharging: false
    property bool recording: false
    property bool online: true
    property bool failed: false
    property bool focusMode: false
    property bool busyLatch: false                // CPU has hysteresis: 80% on, 60% off
    property real now: Date.now()
    property real pingUntil: 0
    property real okUntil: 0
    property real helloUntil: Date.now() + 4000
    property real chargeSparkUntil: 0             // one-shot plug-in spark
    property int frame: 0
    property string mood: "idle"
    property var rs: ({ x: 20, dir: 1, wait: 0, target: 20, moving: false })

    readonly property bool muted: Pipewire.defaultAudioSink?.audio?.muted ?? false
    readonly property bool away: idle.isIdle
    readonly property bool music: {
        const ps = Mpris.players.values
        for (let i = 0; i < ps.length; i++)
            if (ps[i].isPlaying) return true
        return false
    }

    onCpuChanged: {
        if (cpu >= cpuBusyAt) busyLatch = true
        else if (cpu < cpuBusyAt - 20) busyLatch = false
    }

    onChargingChanged: {
        // Charging is a status badge, never a mood. Plugging in gets a brief
        // spark and one sound; the bot keeps doing whatever it was doing.
        if (charging) {
            chargeSparkUntil = Date.now() + 1800
            if (soundReady && soundEnabled && moodSounds && active) playSound("charging")
        } else {
            chargeSparkUntil = 0
        }
    }

    // One decision, shared by the renderer and the Control Center caption.
    readonly property var moodInfo: resolve({
        error: failed,
        ping: now < pingUntil,
        ok: now < okUntil,
        low: battery <= batteryLowAt && discharging,
        bat: battery,
        rec: recording,
        cpu: cpu,
        busy: busyLatch,
        offline: !online,
        music: music,
        focus: focusMode,
        muted: muted,
        afk: away,
        hello: now < helloUntil
    })
    readonly property string baseMood: forced !== "" ? forced : moodInfo[0]
    readonly property string moodText: forced !== "" ? forced : moodInfo[1]

    onMoodChanged: {
        cv.requestPaint()
        if (!root.soundReady || !root.soundEnabled || !root.moodSounds || !root.active) return
        if (root.audibleMoods.indexOf(mood) !== -1) root.playSound(mood)
    }

    onForcedChanged: {
        // Let `bot force idle` / `bot force walk` preview their sounds too.
        if (root.forced === "" || !root.soundEnabled || !root.moodSounds || !root.active) return
        if (root.audibleMoods.indexOf(root.forced) === -1) root.playSound(root.forced)
    }

    // ---------- event sources ----------
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    IdleMonitor {
        id: idle
        enabled: root.active
        timeout: root.awayAfterSeconds
        respectInhibitors: true
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (root.active && root.helloOnWorkspace) root.helloUntil = Date.now() + 1500
        }
    }

    // Public triggers used by the bar and IPC.
    function ping() { root.pingUntil = Date.now() + 3000 }
    function ok() { root.okUntil = Date.now() + 3000 }
    function hello() { root.helloUntil = Date.now() + 3000 }
    function fail() { root.failed = true }
    function focus(on) { root.focusMode = on }
    function clear() { root.failed = false; root.forced = "" }
    function force(mood) { root.forced = mood }

    function playSound(name) {
        if (!soundEnabled || !moodSounds || !active) return
        const t = Date.now()
        if (t - lastSoundAt < 220) return
        lastSoundAt = t
        Quickshell.execDetached(["paplay", soundDir + name + ".wav"])
    }

    function status() {
        return "mood=" + root.mood
            + " cpu=" + root.cpu
            + " bat=" + root.battery
            + " charging=" + root.charging
            + " discharging=" + root.discharging
            + " ac=" + (root.charging || (!root.discharging && root.battery >= 100))
            + " recording=" + root.recording
            + " music=" + root.music
            + " muted=" + root.muted
            + " idle=" + root.away
            + " sound=" + root.soundEnabled
            + " size=" + Math.round(root.width) + "x" + Math.round(root.height)
    }

    IpcHandler {
        target: "bot"
        enabled: root.registerIpc
        function ping(): void { root.ping() }
        function ok(): void { root.ok() }
        function hello(): void { root.hello() }
        function fail(): void { root.fail() }
        function focus(on: bool): void { root.focus(on) }
        function clear(): void { root.clear() }
        function force(mood: string): void { root.force(mood) }
        function sound(on: bool): void { root.soundEnabled = on }
        function play(mood: string): void { root.playSound(mood) }
        function status(): string { return root.status() }
    }

    // CPU, battery, recorder and network from one shell loop, every 2 s.
    readonly property string pollScript: `
cpu_read() { read -r l u n s i w q sq sl _ < /proc/stat; T=$((u+n+s+i+w+q+sq+sl)); I=$((i+w)); }
cpu_read; PT=$T; PI=$I
while :; do
  sleep 2
  cpu_read
  dt=$((T-PT)); di=$((I-PI)); PT=$T; PI=$I
  if [ "$dt" -gt 0 ]; then cpu=$((100*(dt-di)/dt)); else cpu=0; fi
  bat=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1)
  sts=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1)
  rec=0; pgrep -x '` + recorders + `' >/dev/null 2>&1 && rec=1
  net=0; ip route get 1.1.1.1 >/dev/null 2>&1 && net=1
  echo "$cpu|$bat|$sts|$rec|$net"
done
`

    Process {
        running: root.active
        command: ["sh", "-c", root.pollScript]
        stdout: SplitParser {
            onRead: data => {
                const a = data.trim().split("|")
                if (a.length < 5) return
                root.cpu = parseInt(a[0]) || 0
                root.battery = a[1] === "" ? 100 : (parseInt(a[1]) || 0)
                root.charging = a[2] === "Charging"
                root.discharging = a[2] === "Discharging"
                root.recording = a[3] === "1"
                root.online = a[4] === "1"
            }
        }
    }

    // ---------- animation clock ----------
    Timer {
        interval: 140
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.frame++
            root.now = Date.now()
            root.roamStep(root.rs, root.baseMood, root.frame, root.stageW, root.roam)
            // Walking is only a visual submood; the public state stays idle so
            // the caption and sound decision do not flicker every few frames.
            root.mood = root.baseMood
            cv.requestPaint()
        }
    }

    // Give the shell a quiet moment to settle before announcing a startup mood.
    Timer {
        interval: 900
        running: root.active && root.moodSounds && !root.soundReady
        onTriggered: root.soundReady = true
    }

    Component.onCompleted: {
        root.now = Date.now()
        rs.x = rs.target = Math.floor((stageW - 16) / 2)
    }

    onActiveChanged: {
        if (active) {
            now = Date.now()
            cv.requestPaint()
        } else {
            soundReady = false
        }
    }

    // Click the bot to make it wave.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.helloUntil = Date.now() + 2000
    }

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.save()
            ctx.scale(root.pixelScale, root.pixelScale)
            const visual = (root.mood === "idle" && root.rs.moving) ? "walk" : root.mood
            root.render(ctx, visual, root.frame, { x: root.roam ? root.rs.x : 0, dir: root.rs.dir, W: root.stageW })
            ctx.restore()
        }
    }

    // ---------- flat 2D sprite ----------
    // The shell keeps the newer state engine; this renderer restores the
    // original flat 2D bot with theme-derived colours.
    function render(ctx, m, f, o) {
        const C = {
            B: colors.alpha(colors.foreground, 0.78),   // casing
            S: colors.background,                       // screen
            A: colors.primary,                          // accent
            O: colors.secondary,                        // secondary accent
            R: colors.error,                            // problem / rec dot
            G: colors.tertiary,                         // third accent
            D: colors.outline,                          // asleep / muted
            Y: colors.secondary,                        // notes
            T: colors.tertiary                          // data
        }
        const p = (x, y, w, h, c) => { ctx.fillStyle = c; ctx.fillRect(x, y, w, h) }

        const body = t => {
            p(7, 0, 2, 2, t); p(7, 2, 2, 1, C.B)                        // antenna
            p(2, 3, 12, 9, C.B); p(1, 6, 1, 3, C.B); p(14, 6, 1, 3, C.B) // head, ears
            p(3, 4, 10, 7, C.S)                                         // screen
            p(4, 12, 8, 2, C.B); p(5, 14, 2, 1, C.B); p(9, 14, 2, 1, C.B) // body, feet
        }
        const E = {
            open: (c, l) => { p(5 + l, 6, 2, 2, c); p(9 + l, 6, 2, 2, c) },
            blink: c => { p(5, 7, 2, 1, c); p(9, 7, 2, 1, c) },
            hap: c => { for (const x of [5, 9]) { p(x, 7, 1, 1, c); p(x + 1, 6, 1, 1, c); p(x + 2, 7, 1, 1, c) } },
            wide: c => { p(5, 5, 2, 3, c); p(9, 5, 2, 3, c) },
            low: c => { p(5, 7, 2, 2, c); p(9, 7, 2, 2, c) },
            x: (c, d) => { for (const x of [5, 9]) for (const a of [[0,0],[2,0],[1,1],[0,2],[2,2]]) p(x + a[0] + d, 5 + a[1], 1, 1, c) },
            heart: c => { for (const x of [5, 9]) { p(x, 5, 1, 1, c); p(x + 2, 5, 1, 1, c); p(x, 6, 3, 1, c); p(x + 1, 7, 1, 1, c) } }
        }
        const M = {
            flat: c => p(7, 9, 2, 1, c),
            smile: c => { p(6, 9, 1, 1, c); p(7, 10, 2, 1, c); p(9, 9, 1, 1, c) },
            o: c => p(7, 9, 2, 2, c),
            frown: c => { p(6, 10, 1, 1, c); p(7, 9, 2, 1, c); p(9, 10, 1, 1, c) }
        }

        // idle gaze: blink twice, look left, look right
        const kk = f % 52
        const g = ((kk >= 20 && kk < 22) || (kk >= 40 && kk < 42)) ? "b" : (kk >= 28 && kk < 36) ? -1 : (kk >= 44) ? 1 : 0
        const eyes = c => { if (g === "b") E.blink(c); else E.open(c, g) }
        const zz = () => {
            const z = (f >> 3) % 3
            if (z === 1) p(13, 2, 1, 1, C.B)
            if (z === 2) { p(12, 0, 3, 1, C.B); p(13, 1, 1, 1, C.B); p(12, 2, 3, 1, C.B) }
        }

        // The newer state names map onto the old visual set.
        let visual = m
        if (visual === "dance") visual = "music"
        else if (visual === "offline") visual = "muted"
        else if (visual === "focus" || visual === "walk") visual = "idle"

        // whole-sprite offsets per mood (bounce, shake, droop, breathe)
        let ox = 0, oy = 0
        switch (visual) {
        case "happy": case "music": oy = (f >> 1) & 1; break
        case "alert": ox = [0, 1, 0, -1][f & 3]; break
        case "lowbat": oy = 1; break
        case "sleepy": oy = (f >> 3) & 1; break
        }

        const x0 = Math.round(o.x)
        ctx.clearRect(0, 0, o.W, 16)
        ctx.save()
        ctx.translate(x0 + ox, oy)

        switch (visual) {
        case "happy":
            body(C.A); E.hap(C.A); M.smile(C.A); break
        case "hello":
            body(C.A); E.hap(C.A); M.smile(C.A)
            if (f & 1) p(15, 3, 1, 3, C.B); else p(15, 5, 1, 3, C.B)
            break
        case "music":
            body((f >> 2) & 1 ? C.O : C.A)
            if ((f >> 1) & 1) E.hap(C.A); else E.open(C.A, 0)
            M.smile(C.A)
            if (f % 6 < 3) { p(15, 0, 1, 3, C.Y); p(14, 2, 1, 1, C.Y) }
            else { p(1, 0, 1, 3, C.Y); p(0, 2, 1, 1, C.Y) }
            break
        case "busy":
            body((f >> 1) & 1 ? C.O : C.A)
            E.open(C.A, (f >> 2) & 1 ? -1 : 1)
            p(4, 9, 8, 1, colors.alpha(colors.surfaceVariant, 0.55))
            p(4 + f % 6, 9, 3, 1, C.A)
            break
        case "alert":
            body(C.O); E.wide(C.O); M.o(C.O)
            if (f & 1) { p(0, 2, 1, 1, C.O); p(15, 2, 1, 1, C.O) }
            break
        case "recording":
            body(C.O); eyes(C.A); M.flat(C.A)
            if ((f >> 2) & 1) p(10, 4, 2, 2, C.R)
            break
        case "lowbat":
            body((f >> 3) & 1 ? C.R : C.D); E.low(C.O); M.frown(C.O)
            if (f % 6 < 4) p(5, 9 + ((f % 6) >> 1), 1, 1, C.T)
            break
        case "charging":
            body((f >> 1) & 1 ? C.G : C.A)
            if ((f >> 2) & 1) E.hap(C.G); else E.heart(C.O)
            M.smile(C.G)
            break
        case "error":
            body(C.R); E.x(C.R, f % 14 < 2 ? 1 : 0)
            p(6, 9, 1, 1, C.R); p(7, 10, 1, 1, C.R); p(8, 9, 1, 1, C.R); p(9, 10, 1, 1, C.R)
            break
        case "muted":
            body(C.D); eyes(C.A)
            p(5, 9, 6, 2, C.D); p(7, 9, 1, 2, C.S); p(9, 9, 1, 2, C.S)   // zipper mouth
            break
        case "sleepy":
            body(C.D); E.blink(C.D); zz(); break
        default:   // idle
            body(C.A); eyes(C.A); M.flat(C.A)
        }

        ctx.restore()

        // Charging stays a status badge, not a mood.
        if (root.charging) {
            ctx.fillStyle = C.G
            for (const q of [[13,0],[12,1],[11,2],[12,2],[12,3]])
                ctx.fillRect(x0 + ox + q[0], oy + q[1], 1, 1)
            if (root.now < root.chargeSparkUntil) {
                ctx.fillStyle = (f & 3) < 2 ? C.Y : C.A
                for (const q of [[10,0],[15,2],[14,4],[1,1]])
                    ctx.fillRect(x0 + ox + q[0], oy + q[1], 1, 1)
            }
        }
    }

    function roamStep(R, m, f, W, on) {
        R.moving = false
        if (!on || !(m === 'idle' || m === 'walk' || m === 'dance')) return
        if (R.wait > 0) { R.wait--; return }
        if (Math.abs(R.target - R.x) < 1) {
            let t = Math.floor(Math.random() * (W - 15))
            if (t === R.x) t = R.x > 0 ? R.x - 1 : R.x + 1
            R.target = t
            R.wait = m === 'dance' ? 0 : 6 + Math.floor(Math.random() * 18)
            if (R.wait > 0) return
        }
        if (m === 'dance' && (f & 1)) return
        R.dir = R.target > R.x ? 1 : -1
        R.x = Math.max(0, Math.min(W - 16, R.x + R.dir))
        R.moving = true
    }

    // Strict priority. One state wins even when several are true:
    // failure > notification > done > low battery > recording > high CPU >
    // offline > music > focus > muted > sleepy > hello > idle.
    // Charging is not in this list on purpose: it is an overlay/status, so it
    // is always visible while charging without ever replacing the mood.
    function resolve(i) {
        if (i.error) return ['error', 'build failed']
        if (i.ping) return ['alert', 'new notification']
        if (i.ok) return ['happy', 'task done']
        if (i.low) return ['lowbat', 'battery at ' + i.bat + '%']
        if (i.rec) return ['recording', 'recording is on']
        if (i.busy) return ['busy', 'CPU at ' + i.cpu + '%']
        if (i.offline) return ['offline', 'no network']
        if (i.music) return ['dance', 'audio is playing']
        if (i.focus) return ['focus', 'do not disturb']
        if (i.muted) return ['muted', 'volume is muted']
        if (i.afk) return ['sleepy', 'away from the keyboard']
        if (i.hello) return ['hello', 'just woke up']
        return ['idle', 'nothing going on']
    }
}
