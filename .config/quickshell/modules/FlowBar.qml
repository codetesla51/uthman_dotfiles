import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// FlowBar: everything for the flowing "gates" bar in one file.
//
// One particle beam runs left to right across the whole bar: through the
// workspace gates, behind the island, then through the MEM / CPU / BAT gates.
// The beam squeezes thin at idle gates and swells wide at open ones (the
// active workspace, a busy CPU). Gate height follows how open the gate is.
//
// Layout: the bar reserves a plain Item "slot" for the workspace gates and
// one for the stat gates, and hands them to FlowBar. FlowBar draws into those
// slots, so the other items in the bar rows can move freely around them.
// Put FlowBar BELOW the island and the rows (declare it before them).
Canvas {
    id: root

    required property var colors

    property Item wsSlot       // Item of size wsWidth x 34 inside the left row
    property Item statSlot     // Item of size statWidth x 34 inside the right row
    property Item island       // the island; the beam passes calmly behind it
    property bool running: true    // false while the bar sides are hidden: stops the timer
    property bool kanji: true
    property string fontFamily: "Noto Sans CJK JP"

    // click MEM or CPU -> openSysMon, click BAT -> openBattery
    signal openSysMon()
    signal openBattery()

    // sizes the bar should give the two slots
    readonly property int wsCount: 6
    readonly property real wsWidth: wsCount * 34
    readonly property int statCount: hasBattery ? 3 : 2
    readonly property real statWidth: statCount * 75

    // design units -> pixels. Everything is drawn in a 52-unit-tall design
    // space centred on the slots, so proportions hold at any bar size.
    readonly property real unit: 34 / 52

    // ---- state ------------------------------------------------------

    readonly property var kanjiDigits: ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
    readonly property int active: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    // 0-based workspace slot the indicator is travelling toward
    readonly property real tgt: Math.min(wsCount, Math.max(1, active)) - 1

    // pos glides to tgt; surge is how far it still has to go, and speeds the flow up
    property real pos: tgt
    Behavior on pos { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    readonly property real surge: Math.abs(tgt - pos)

    // stats, all 0..1; Behavior makes the gates glide when a new sample arrives
    property real mem: 0
    property real cpu: 0
    property real bat: 1
    property bool charging: false
    property bool hasBattery: false
    Behavior on mem { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    Behavior on cpu { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    Behavior on bat { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    property real flow: 0      // distance phase of the particles
    property real clock: 0     // seconds, drives the wobble behind the island

    Timer {
        interval: 33
        repeat: true
        running: root.running && root.visible
        onTriggered: {
            root.flow += 0.033 * (1 + root.surge * 3)
            root.clock += 0.033
            root.requestPaint()
        }
    }
    onRunningChanged: if (running) requestPaint()

    // ---- stats sampling ----------------------------------------------
    // One shell call every 2 seconds. Output lines: 0 = memory used fraction,
    // 1 = the "cpu" line of /proc/stat, 2 = battery capacity, 3 = battery
    // status (lines 2-3 exist only when a battery does).
    property real _cpuTotal: 0
    property real _cpuIdle: 0
    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    Process {
        id: sampler
        command: ["sh", "-c",
            "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print 1-a/t}' /proc/meminfo;"
            + " grep '^cpu ' /proc/stat;"
            + " cat /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/BAT*/status 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = this.text.trim().split("\n")
                if (lines.length < 2) return
                root.mem = root.clamp01(parseFloat(lines[0]) || 0)

                // cpu busy share since the previous sample
                var f = lines[1].trim().split(/\s+/).slice(1).map(Number)
                if (f.length >= 5) {
                    var idle = f[3] + f[4]
                    var total = f.reduce(function(a, b) { return a + b }, 0)
                    if (root._cpuTotal > 0 && total > root._cpuTotal)
                        root.cpu = root.clamp01(1 - (idle - root._cpuIdle) / (total - root._cpuTotal))
                    root._cpuTotal = total
                    root._cpuIdle = idle
                }

                if (lines.length >= 4) {
                    root.hasBattery = true
                    root.bat = root.clamp01((parseFloat(lines[2]) || 0) / 100)
                    root.charging = lines[3].trim() === "Charging"
                } else {
                    root.hasBattery = false
                }
            }
        }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler.running = true
    }

    // ---- helpers ----------------------------------------------------

    // workspace ids that currently exist (have windows or are focused)
    function occupied() {
        var seen = {}
        var list = Hyprland.workspaces.values
        for (var i = 0; i < list.length; i++) seen[list[i].id] = true
        return seen
    }

    function label(i) { return root.kanji && i < 9 ? kanjiDigits[i] : String(i + 1) }

    // 0 below a, 1 above b, smooth in between
    function smoothstep(a, b, x) {
        var t = Math.max(0, Math.min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }

    // Every gate the beam passes: x in pixels, v = how open (0..1).
    // kind "ws" are workspace gates, "stat" are MEM / CPU / BAT.
    function gates() {
        var out = []
        var i
        if (wsSlot)
            for (i = 0; i < wsCount; i++)
                out.push({ kind: "ws", i: i, v: Math.max(0, 1 - Math.abs(i - pos)),
                           x: wsSlot.mapToItem(root, (i + 0.5) * wsSlot.width / wsCount, 0).x })
        if (statSlot) {
            var values = hasBattery ? [mem, cpu, bat] : [mem, cpu]
            for (i = 0; i < statCount; i++)
                out.push({ kind: "stat", i: i, v: values[i],
                           x: statSlot.mapToItem(root, (i + 0.5) * statSlot.width / statCount, 0).x })
        }
        return out
    }

    // index of the gate under (x, y) inside a slot, or -1
    function hit(slot, count, x, y) {
        if (!slot) return -1
        var p = slot.mapFromItem(root, x, y)
        if (p.x < 0 || p.x >= slot.width || p.y < 0 || p.y >= slot.height) return -1
        return Math.floor(p.x / (slot.width / count))
    }

    // ---- drawing ----------------------------------------------------

    onPaint: {
        var c = getContext("2d")
        c.reset()
        var k = root.unit
        // vertical centre of the beam = centre of the workspace slot
        var cyPx = root.wsSlot ? root.wsSlot.mapToItem(root, 0, root.wsSlot.height / 2).y : height / 2
        c.translate(0, cyPx)
        c.scale(k, k)
        var W = width / k

        var list = root.gates()
        var gx = []
        for (var g = 0; g < list.length; g++) gx.push(list[g].x / k)

        // island span in design units; the beam is calmer and wobbles behind it
        var hasHole = root.island !== null && root.island !== undefined
        var hx0 = 0, hx1 = 0
        if (hasHole) {
            hx0 = root.island.mapToItem(root, 0, 0).x / k
            hx1 = hx0 + root.island.width / k
        }
        function behind(x) {
            return hasHole ? root.smoothstep(hx0 - 17, hx0 + 13, x) * (1 - root.smoothstep(hx1 - 13, hx1 + 17, x)) : 0
        }

        // half-height of the beam at x: thin base, a bump at every gate
        // (taller for open gates), a little extra behind the island
        function halfHeight(x) {
            var e = 2 + 3.5 * behind(x)
            for (var j = 0; j < list.length; j++) {
                var d = (x - gx[j]) / 30
                e += (2 + 9 * list[j].v) * Math.exp(-d * d)
            }
            return e
        }

        // beam: primary -> secondary -> tertiary across the bar
        var P = root.colors.primary, Q = root.colors.secondary, T = root.colors.tertiary
        var n = Math.round(W / 6), gap = (W + 20) / n
        for (var i = 0; i < n; i++) {
            var x = ((root.flow * (110 + (i % 5) * 34) + i * gap) % (W + 20)) - 10
            var side = ((i * 0.61803) % 1) * 2 - 1
            var y = side * halfHeight(x) + behind(x) * Math.sin(x * 0.03 - root.clock * 3 + i) * 2.2
            var u = x / W
            var tone = u < 0.5 ? root.mix(P, Q, u * 2) : root.mix(Q, T, (u - 0.5) * 2)
            c.fillStyle = Qt.rgba(tone.r, tone.g, tone.b, 0.35 + 0.5 * Math.abs(Math.cos(i)))
            c.fillRect(x - 1.1, y - 1.1, 2.2, 2.2)
        }

        // gates on top of the beam
        var seen = root.occupied()
        var names = ["MEM", "CPU", "BAT"]
        c.lineCap = "round"
        c.lineWidth = 2
        c.textAlign = "center"
        c.textBaseline = "middle"
        for (var q = 0; q < list.length; q++) {
            var gate = list[q], gxq = gx[q], v = gate.v, on = v > 0.5, h = 9 + 11 * v

            if (gate.kind === "ws") {
                c.globalAlpha = (seen[gate.i + 1] || on) ? 1 : 0.45
                c.strokeStyle = on ? P : root.colors.alpha(P, 0.35)
                c.beginPath()
                c.moveTo(gxq - 12, -h); c.lineTo(gxq - 17, -h); c.lineTo(gxq - 17, h); c.lineTo(gxq - 12, h)
                c.moveTo(gxq + 12, -h); c.lineTo(gxq + 17, -h); c.lineTo(gxq + 17, h); c.lineTo(gxq + 12, h)
                c.stroke()
                c.font = (on ? 700 : 500) + " " + (on ? 18 : 14) + "px '" + root.fontFamily + "'"
                c.fillStyle = on ? Qt.lighter(P, 1.6) : root.colors.alpha(root.colors.outline, 0.9)
                c.fillText(root.label(gate.i), gxq, 1)
            } else {
                // a very busy CPU turns its gate to the warning accent
                var stat = (gate.i === 1 && v > 0.8) ? T : Q
                c.globalAlpha = 1
                c.strokeStyle = root.colors.alpha(stat, on ? 1 : 0.5)
                c.beginPath()
                c.moveTo(gxq - 35, -h); c.lineTo(gxq - 40, -h); c.lineTo(gxq - 40, h); c.lineTo(gxq - 35, h)
                c.moveTo(gxq + 35, -h); c.lineTo(gxq + 40, -h); c.lineTo(gxq + 40, h); c.lineTo(gxq + 35, h)
                c.stroke()
                var plus = (gate.i === 2 && root.charging) ? "+" : ""
                c.font = "600 14px sans-serif"
                c.fillStyle = root.colors.alpha(Qt.lighter(stat, 1.4), on ? 1 : 0.8)
                c.fillText(names[gate.i] + " " + Math.round(v * 100) + "%" + plus, gxq, 1)
            }
        }
        c.globalAlpha = 1
    }

    // ---- input ------------------------------------------------------
    // Only the gate slots take the mouse; everywhere else clicks pass through.
    MouseArea {
        anchors.fill: parent
        onPressed: function(m) {
            m.accepted = root.hit(root.wsSlot, root.wsCount, m.x, m.y) >= 0
                      || root.hit(root.statSlot, root.statCount, m.x, m.y) >= 0
        }
        onClicked: function(m) {
            var w = root.hit(root.wsSlot, root.wsCount, m.x, m.y)
            if (w >= 0) { Hyprland.dispatch("workspace " + (w + 1)); return }
            var s = root.hit(root.statSlot, root.statCount, m.x, m.y)
            if (s < 0) return
            if (root.hasBattery && s === 2) root.openBattery()
            else root.openSysMon()
        }
        onWheel: function(w) {
            if (root.hit(root.wsSlot, root.wsCount, w.x, w.y) < 0) { w.accepted = false; return }
            Hyprland.dispatch(w.angleDelta.y > 0 ? "workspace e-1" : "workspace e+1")
        }
    }
}
