import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// PixelBot — 16x16 pixel-art bot that lives in the center island where the
// notification bell used to be. One mood wins at a time, highest first:
// error, alert, happy, lowbat, recording, busy, charging, music, muted,
// sleepy, hello, idle.
//
// It is event-driven where the system offers an event (UPower, Pipewire,
// Mpris, idle, notifications) and borrows the CPU reading from the Cpu pill,
// so the only thing it polls itself is "is a recorder running".
//
//     quickshell -p ~/.config/quickshell ipc call bot ping
//     quickshell -p ~/.config/quickshell ipc call bot ok
//     quickshell -p ~/.config/quickshell ipc call bot fail
//     quickshell -p ~/.config/quickshell ipc call bot hello
//     quickshell -p ~/.config/quickshell ipc call bot force busy
//     quickshell -p ~/.config/quickshell ipc call bot clear
//     quickshell -p ~/.config/quickshell ipc call bot sound false
//     quickshell -p ~/.config/quickshell ipc call bot status
Item {
    id: root

    property var colors

    // ---------- settings ----------
    property int pixelScale: 2                  // sprite is 16x16, drawn at 16 * pixelScale px
    property real cpuUsage: 0                   // fed by the Cpu pill; no second /proc poll
    property int cpuBusyAt: 80                  // percent
    property int batteryLowAt: 15               // percent
    property int awayAfterSeconds: 180          // idle time before the bot falls asleep
    property string recorders: "meetcap|wf-recorder|wl-screenrec|obs|gpu-screen-recorder"
    property bool helloOnWorkspace: false       // wave when the focused Hyprland workspace changes
    property string forced: ""                  // set to a mood name to preview it; "" = automatic
    property bool active: true                  // false pauses the clock/poller (panel closed)
    property bool registerIpc: true             // only one instance may own target "bot"
    property bool soundEnabled: true
    property bool moodSounds: true              // allow state sounds (one instance only)
    // Only states worth interrupting you for. Ambient states (idle, sleepy,
    // muted, music, charging, busy) stay silent; click/hello is still audible.
    property var audibleMoods: ["alert", "error", "lowbat", "recording", "happy", "hello"]
    property bool soundReady: false             // suppresses the startup state chirp
    property string soundDir: Quickshell.env("HOME") + "/.config/quickshell/assets/pixelbot/"
    property real lastSoundAt: 0
    property bool busyLatch: false
    property bool ambientHello: false            // workspace wave: visible, but silent

    implicitWidth: 16 * pixelScale
    implicitHeight: 16 * pixelScale

    // ---------- state fed by events ----------
    property bool recording: false
    property bool failed: false
    property real now: Date.now()
    property real pingUntil: 0
    property real okUntil: 0
    property real helloUntil: 0                    // ambient greet (workspace change)
    property real pokeUntil: Date.now() + 4000     // direct greet (startup, click, IPC)
    property int frame: 0

    readonly property var batDev: UPower.displayDevice
    readonly property int batteryLevel: batDev ? Math.round(batDev.percentage * 100) : 100
    readonly property bool charging: batDev
        ? (batDev.state === UPowerDeviceState.Charging
           || batDev.state === UPowerDeviceState.PendingCharge) : false
    readonly property bool discharging: batDev
        ? (batDev.state === UPowerDeviceState.Discharging
           || batDev.state === UPowerDeviceState.PendingDischarge) : false
    readonly property bool muted: Pipewire.defaultAudioSink?.audio?.muted ?? false
    readonly property bool onAc: !UPower.onBattery
    readonly property bool away: idle.isIdle
    readonly property bool music: {
        // Reading frame makes this re-evaluate on the animation tick. Stream
        // properties arrive asynchronously after a new node is tracked, and a
        // bare QVariantMap read is not a binding dependency.
        const tick = root.frame
        const ps = Mpris.players.values
        for (let i = 0; i < ps.length; i++)
            if (ps[i].playbackState === MprisPlaybackState.Playing) return true

        // Browsers (Firefox especially) play audio without publishing MPRIS,
        // so also watch live PipeWire output streams. Skip our own paplay
        // chirps; otherwise the bot would hear itself and switch to "music".
        const ns = Pipewire.nodes.values
        for (let i = 0; i < ns.length; i++) {
            const n = ns[i]
            if (!n || !n.isStream) continue
            const p = n.properties || {}
            if (p["media.class"] !== "Stream/Output/Audio") continue
            if (p["pulse.corked"] === true || p["pulse.corked"] === "true") continue
            const app = String(p["application.name"] || "").toLowerCase()
            if (app === "paplay") continue
            return true
        }
        return false
    }

    // ---------- the one decision: which mood wins ----------
    readonly property string mood: {
        if (forced !== "") return forced
        if (failed) return "error"
        if (now < pingUntil) return "alert"
        if (now < okUntil) return "happy"
        if (now < pokeUntil) return "hello"          // a wave you asked for always wins
        if (batteryLevel <= batteryLowAt && discharging) return "lowbat"
        if (recording) return "recording"
        if (busyLatch) return "busy"
        if (charging) return "charging"
        if (music) return "music"
        if (muted) return "muted"
        if (away) return "sleepy"
        if (now < helloUntil) return "hello"
        return "idle"
    }
    onMoodChanged: {
        cv.requestPaint()
        if (mood === "hello") {
            if (soundReady && moodSounds && !ambientHello) playSound(mood)
            return
        }
        // a workspace wave is silent, including its return to idle/sleepy;
        // a real event interrupting it still gets its own sound
        const urgent = mood === "error" || mood === "alert"
                    || mood === "lowbat" || mood === "recording" || mood === "happy"
        if (ambientHello) {
            ambientHello = false
            if (!urgent) return
        }
        if (soundReady && moodSounds && audibleMoods.indexOf(mood) !== -1) playSound(mood)
    }
    onPixelScaleChanged: cv.requestPaint()
    onCpuUsageChanged: {
        // hysteresis: enter busy at 80, leave only below 65, so the chirp
        // does not flap with every 3 s CPU sample
        if (cpuUsage >= cpuBusyAt) busyLatch = true
        else if (cpuUsage <= cpuBusyAt - 15) busyLatch = false
    }
    onActiveChanged: {
        if (active) { now = Date.now(); cv.requestPaint() }
        else { recording = false; soundReady = false }
    }

    // ---------- sound ----------
    // Every mood has a tiny chiptune motif, so a state change is audible.
    // paplay is already the shell's player (see Pomodoro / Hornet).
    function playSound(name) {
        if (!soundEnabled || !active) return
        var t = Date.now()
        if (t - lastSoundAt < 220) return
        lastSoundAt = t
        Quickshell.execDetached(["paplay", soundDir + name + ".wav"])
    }

    Timer {
        interval: 650
        running: root.active && !root.soundReady
        onTriggered: root.soundReady = true
    }

    // ---------- event sources ----------
    // Track every node: node properties (media.class, pulse.corked, audio
    // state) are only populated for tracked objects. The old tracker only
    // covered the default sink, which is why browser streams were invisible.
    PwObjectTracker { objects: Pipewire.nodes.values }

    IdleMonitor {
        id: idle
        enabled: root.active
        timeout: root.awayAfterSeconds
        respectInhibitors: true
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            // only wave when it will actually be the visible mood; otherwise
            // the ambient flag would sit around and swallow a later state chirp
            if (root.helloOnWorkspace && (root.mood === "idle" || root.mood === "sleepy")) {
                root.ambientHello = true       // set before helloUntil changes mood
                root.helloUntil = Date.now() + 1500
            }
        }
    }

    // public triggers — the IpcHandler and the bar both call these.
    // No direct sound here: reaching a new mood plays that mood's motif.
    function ping() { root.pingUntil = Date.now() + 3000 }
    function ok() { root.okUntil = Date.now() + 3000 }
    function hello() {
        var wasHello = root.mood === "hello"
        root.ambientHello = false
        root.helloUntil = Date.now() + 3000
        root.pokeUntil = Date.now() + 3000
        if (wasHello) playSound("hello")
    }
    function fail() { root.failed = true }
    function clear() { root.failed = false; root.forced = "" }
    function force(mood) { root.forced = mood }
    function setSound(on) { root.soundEnabled = on }
    function status() {
        return "mood=" + root.mood
            + " cpu=" + Math.round(root.cpuUsage)
            + " bat=" + root.batteryLevel
            + " charging=" + root.charging
            + " ac=" + root.onAc
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
        function clear(): void { root.clear() }
        function force(mood: string): void { root.force(mood) }
        function sound(on: bool): void { root.setSound(on) }
        function status(): string { return root.status() }
    }

    // Only poll what the system does not announce. 3 s is responsive enough
    // for a recording dot and costs one tiny pgrep, not a /proc parser.
    Process {
        running: root.active
        command: ["sh", "-c", "while :; do "
            + "pgrep -f '(^|/)(" + root.recorders + ")( |$)' >/dev/null 2>&1 "
            + "&& echo 1 || echo 0; sleep 3; done"]
        stdout: SplitParser {
            onRead: data => { root.recording = data.trim() === "1" }
        }
    }

    // ---------- animation clock (7 fps for the chunky pixel feel) ----------
    Timer {
        interval: 140
        running: root.active
        repeat: true
        onTriggered: {
            root.frame++
            root.now = Date.now()
            cv.requestPaint()
        }
    }

    // click the bot to make it wave; hover lifts it off the island
    readonly property bool hovered: botMouse.containsMouse
    scale: hovered ? 1.1 : 1
    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
    }

    MouseArea {
        id: botMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            var wasHello = root.mood === "hello"
            root.ambientHello = false
            root.pokeUntil = Date.now() + 2000
            if (wasHello || !root.moodSounds) root.playSound("hello")
        }
    }

    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: root.draw(getContext("2d"), root.mood, root.frame, root.pixelScale)
    }

    // ---------- the sprite ----------
    function draw(ctx, k, f, s) {
        // Every colour is a Matugen role — the bot follows the wallpaper like
        // the rest of the shell instead of carrying its own hardcoded palette.
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

        // whole-sprite offsets per mood (bounce, shake, droop, breathe)
        let ox = 0, oy = 0
        switch (k) {
        case "happy": case "music": oy = (f >> 1) & 1; break
        case "alert": ox = [0, 1, 0, -1][f & 3]; break
        case "lowbat": oy = 1; break
        case "sleepy": oy = (f >> 3) & 1; break
        }

        ctx.clearRect(0, 0, 16 * s, 16 * s)
        ctx.save()
        ctx.scale(s, s)
        ctx.translate(ox, oy)

        switch (k) {
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
    }
}
