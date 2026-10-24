import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// PixelBot — shaded 3D pixel bot. One instance owns the `bot` IPC target;
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
    implicitHeight: 18 * pixelScale

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
    property real chargingUntil: 0             // charging is a one-shot pulse, not a permanent mood
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
        // Plugging in is a brief acknowledgement, not a state that owns the
        // bot forever. It can appear only when nothing more interesting is
        // happening, and it disappears after five seconds.
        chargingUntil = charging ? Date.now() + 5000 : 0
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
        chg: charging && now < chargingUntil,
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

    // ---------- sprite, shading, roaming, rules ----------
    readonly property int gh: 18
    readonly property var pal: ({H:'#b9c3d8',T:'#9aa6bf',A2:'#aab4c8',L:'#8793ad',cy:'#5ad1ff',am:'#f9a15b',rd:'#f38ba8',gn:'#a6e3a1',dm:'#5b6478',ye:'#f9e2af',bl:'#89dceb',pu:'#b4a1ff',D:'#1e1e2e'})
    readonly property var faces: ({
        open:(c,l)=>[[5+l,6,2,2,c],[9+l,6,2,2,c]],
        blink:c=>[[5,7,2,1,c],[9,7,2,1,c]],
        hap:c=>[[5,7,1,1,c],[6,6,1,1,c],[7,7,1,1,c],[9,7,1,1,c],[10,6,1,1,c],[11,7,1,1,c]],
        wide:c=>[[5,5,2,3,c],[9,5,2,3,c]],
        low:c=>[[5,7,2,2,c],[9,7,2,2,c]],
        x:c=>{const o=[];for(const x of [5,9])for(const a of [[0,0],[2,0],[1,1],[0,2],[2,2]])o.push([x+a[0],5+a[1],1,1,c]);return o},
        heart:c=>{const o=[];for(const x of [5,9])o.push([x,5,1,1,c],[x+2,5,1,1,c],[x,6,3,1,c],[x+1,7,1,1,c]);return o},
        flat:c=>[[7,9,2,1,c]],
        smile:c=>[[6,8,1,1,c],[7,9,2,1,c],[9,8,1,1,c]],
        o:c=>[[7,8,2,2,c]],
        frown:c=>[[6,9,1,1,c],[7,8,2,1,c],[9,9,1,1,c]],
        zig:c=>[[6,9,1,1,c],[7,8,1,1,c],[8,9,1,1,c],[9,8,1,1,c]]
    })

    function mix(c, f) {
        f = Math.max(-0.6, Math.min(0.6, f))
        const n = parseInt(c.slice(1), 16), t = f > 0 ? 255 : 0, a = Math.abs(f)
        const h = v => ('0' + Math.round(v + (t - v) * a).toString(16)).slice(-2)
        return '#' + h((n >> 16) & 255) + h((n >> 8) & 255) + h(n & 255)
    }

    function gaze(f) {
        const k = f % 52
        return ((k >= 20 && k < 22) || (k >= 40 && k < 42)) ? 'b'
             : (k >= 28 && k < 36) ? -1
             : (k >= 44) ? 1 : 0
    }

    function build(m, f, o) {
        const P = { tip: pal.cy, la: 0, ra: 0, ll: 0, rl: 0, ox: 0, oy: 0, dim: false, hp: false, ov: [], ex: [] }
        const g = gaze(f), eyes = c => g === 'b' ? faces.blink(c) : faces.open(c, g), k = f & 7, s = (f >> 1) & 1
        switch (m) {
        case 'walk':
            P.ll = s; P.rl = 1 - s; P.la = s; P.ra = 1 - s
            P.ov = faces.open(pal.cy, o.dir > 0 ? 1 : -1).concat(faces.flat(pal.cy)); break
        case 'dance': {
            const A = [[2,2],[1,1],[2,0],[1,1],[0,2],[1,1],[2,2],[0,0]][k]
            P.la = A[0]; P.ra = A[1]; P.ll = (k === 2 || k === 3) ? 1 : 0; P.rl = (k === 6 || k === 7) ? 1 : 0
            P.ox = [0,-1,-1,0,0,1,1,0][k]; P.oy = (k & 1) ? -1 : 0
            P.tip = [pal.cy, pal.pu, pal.rd, pal.ye][(f >> 1) & 3]
            P.ov = faces.hap(pal.cy).concat(faces.smile(pal.cy))
            P.ex = (f % 6 < 3) ? [[15,0,1,3,pal.ye],[14,2,1,1,pal.ye]] : [[1,0,1,3,pal.ye],[0,2,1,1,pal.ye]]
            break
        }
        case 'happy': {
            const J = [0,-1,-2,-2,-1,0,0,0][k], cols = [pal.rd, pal.ye, pal.gn, pal.cy, pal.pu, pal.am]
            P.oy = J; P.la = P.ra = J < 0 ? 2 : 0; P.ll = P.rl = J < 0 ? 1 : 0; P.tip = pal.ye
            P.ov = faces.hap(pal.cy).concat(faces.smile(pal.cy))
            for (let i = 0; i < 6; i++) P.ex.push([(i * 5 + f * 3) % 16, (f * 2 + i * 3) % 4, 1, 1, cols[i]])
            break
        }
        case 'hello':
            P.ra = (f & 1) ? 2 : 1; P.ov = faces.hap(pal.cy).concat(faces.smile(pal.cy)); break
        case 'alert':
            P.ox = [0,1,0,-1][f & 3]; P.la = P.ra = 2; P.tip = pal.am
            P.ov = faces.wide(pal.am).concat(faces.o(pal.am))
            if (f & 1) P.ex = [[0,2,1,1,pal.ye],[15,2,1,1,pal.ye],[0,4,1,1,pal.ye],[15,4,1,1,pal.ye]]
            break
        case 'busy':
            P.tip = ((f >> 1) & 1) ? pal.am : pal.cy; P.la = f & 1; P.ra = 1 - (f & 1)
            P.ov = faces.open(pal.cy, ((f >> 2) & 1) ? -1 : 1).concat([[4,9,8,1,'#262b38'],[4+f%6,9,3,1,pal.cy]]); break
        case 'recording':
            P.tip = pal.rd; P.ov = eyes(pal.cy).concat(faces.flat(pal.cy))
            if ((f >> 2) & 1) P.ov.push([11,5,2,1,pal.rd]); break
        case 'lowbat':
            P.oy = 1; P.tip = ((f >> 3) & 1) ? pal.rd : pal.dm
            P.ov = faces.low(pal.am).concat(faces.frown(pal.am))
            if (f % 6 < 4) P.ov.push([5,9,1,1,pal.bl]); break
        case 'charging':
            P.tip = ((f >> 1) & 1) ? pal.gn : pal.cy
            P.ov = (((f >> 2) & 1) ? faces.hap(pal.gn) : faces.heart(pal.rd)).concat(faces.smile(pal.gn))
            if ((f >> 1) & 1) P.ov.push([8,11,1,1,pal.ye],[7,12,2,1,pal.ye],[7,13,1,1,pal.ye]); break
        case 'error':
            P.tip = pal.rd; P.ox = (f % 14 < 2) ? 1 : 0; P.la = P.ra = 2
            P.ov = faces.x(pal.rd).concat(faces.zig(pal.rd)); break
        case 'muted':
            P.tip = pal.dm; P.ov = eyes(pal.cy).concat([[5,9,6,1,pal.dm],[7,9,1,1,'#0e1015'],[9,9,1,1,'#0e1015']]); break
        case 'offline':
            P.tip = pal.dm; P.la = P.ra = 1
            P.ov = faces.open(pal.cy, ((f >> 1) & 1) ? -1 : 1).concat(faces.zig(pal.am))
            P.ex = (f & 1) ? [[10,1,1,1,pal.ye],[6,0,1,1,pal.ye]] : [[6,1,1,1,pal.ye],[10,0,1,1,pal.ye]]; break
        case 'focus':
            P.tip = pal.pu; P.hp = true; P.oy = (f >> 3) & 1
            P.ov = faces.blink(pal.cy).concat(faces.flat(pal.cy)); break
        case 'sleepy': {
            P.dim = true; P.oy = (f >> 3) & 1; P.ov = faces.blink(pal.dm)
            const z = (f >> 3) % 3, zc = '#aab4c8'
            if (z === 1) P.ex = [[13,2,1,1,zc]]
            if (z === 2) P.ex = [[12,0,3,1,zc],[13,1,1,1,zc],[12,2,3,1,zc]]
            break
        }
        default:
            P.tip = ((f >> 3) & 1) ? mix(pal.cy, 0.4) : pal.cy
            P.ov = eyes(pal.cy).concat(faces.flat(pal.cy))
        }
        return P
    }

    function render(ctx, m, f, o) {
        const W = o.W, x0 = Math.round(o.x), P = build(m, f, o)
        ctx.clearRect(0, 0, W, gh)
        const lift = Math.max(0, -P.oy)
        ctx.fillStyle = 'rgba(0,0,0,' + (0.4 - 0.08 * lift).toFixed(2) + ')'
        ctx.fillRect(x0 + P.ox + 4 + lift, 17, 8 - 2 * lift, 1)

        const arm = (side, p) => side < 0 ? [[1,11],[0,9],[0,6]][p] : [[13,11],[14,9],[14,6]][p]
        const la = arm(-1, P.la), ra = arm(1, P.ra), ly = P.ll ? 13 : 14, ry = P.rl ? 13 : 14
        const parts = [['t',7,2,2,2,P.tip],['h',2,4,12,7,pal.H],['b',4,11,8,3,pal.T],['a',la[0],la[1],2,3,pal.A2],['a',ra[0],ra[1],2,3,pal.A2],['l',4,ly,2,3,pal.L],['l',10,ry,2,3,pal.L]]
        const g = new Array(16 * gh)
        for (const p of parts) for (let y = p[2]; y < p[2] + p[4]; y++) for (let x = p[1]; x < p[1] + p[3]; x++) if (x >= 0 && x < 16 && y >= 0 && y < gh) g[y * 16 + x] = { c: p[5], id: p[0] }

        for (let y = 0; y < gh; y++) for (let x = 0; x < 16; x++) {
            const c = g[y * 16 + x]
            if (!c) continue
            const up = y > 0 && g[(y - 1) * 16 + x], lf = x > 0 && g[y * 16 + x - 1]
            const dn = y < gh - 1 && g[(y + 1) * 16 + x], rt = x < 15 && g[y * 16 + x + 1]
            let t = 0.14 - 0.32 * (y - 2) / 14
            if (!up) t += 0.22
            if (!lf) t += 0.1
            if (!dn) t -= 0.22
            if (!rt) t -= 0.14
            if (up && up.id === 'h' && c.id !== 'h') t -= 0.16
            if (P.dim) t -= 0.38
            ctx.fillStyle = mix(c.c, t)
            ctx.fillRect(x0 + P.ox + x, P.oy + y, 1, 1)
        }

        const sx = x0 + P.ox, sy = P.oy
        ctx.fillStyle = mix(pal.H, P.dim ? 0.1 : 0.55)
        for (const q of [[3,4],[4,4],[2,5]]) ctx.fillRect(sx + q[0], sy + q[1], 1, 1)
        ctx.fillStyle = P.dim ? '#07080b' : '#0e1015'
        ctx.fillRect(sx + 3, sy + 5, 10, 5)
        ctx.fillStyle = '#05060a'
        ctx.fillRect(sx + 3, sy + 5, 10, 1)
        ctx.fillRect(sx + 3, sy + 5, 1, 5)
        ctx.fillStyle = '#1b2030'
        ctx.fillRect(sx + 3, sy + 9, 10, 1)
        ctx.fillRect(sx + 12, sy + 5, 1, 5)

        if (P.hp) {
            const a = '#7c6bd6', b = '#a496f0', d = '#574aa8'
            for (const q of [[0,6,3,4],[13,6,3,4]]) {
                ctx.fillStyle = a; ctx.fillRect(sx + q[0], sy + q[1], q[2], q[3])
                ctx.fillStyle = b; ctx.fillRect(sx + q[0], sy + q[1], q[2], 1)
                ctx.fillStyle = d; ctx.fillRect(sx + q[0], sy + q[1] + q[3] - 1, q[2], 1)
            }
            ctx.fillStyle = a
            ctx.fillRect(sx + 3, sy + 3, 4, 1); ctx.fillRect(sx + 9, sy + 3, 4, 1)
            ctx.fillRect(sx + 2, sy + 4, 1, 2); ctx.fillRect(sx + 13, sy + 4, 1, 2)
        }
        for (const q of P.ov) { ctx.fillStyle = q[4]; ctx.fillRect(sx + q[0], sy + q[1], q[2], q[3]) }
        for (const q of P.ex) { ctx.fillStyle = q[4]; ctx.fillRect(x0 + q[0], q[1], q[2], q[3]) }
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
    // offline > music > focus > muted > sleepy > hello > charging pulse > idle.
    // Charging is deliberately last: it is a 5s acknowledgement after plug-in,
    // so music/focus/idle-time always beat it and it never owns the bot forever.
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
        if (i.chg) return ['charging', 'plugged in']
        return ['idle', 'nothing going on']
    }
}
