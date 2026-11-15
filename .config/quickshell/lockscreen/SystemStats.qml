import Quickshell
import Quickshell.Io
import QtQuick

// SystemStats — CPU and memory as one real activity curve, sampled from
// /proc every four seconds while the lock is up. Both series share a fixed
// 0..100% scale and are drawn as smooth midpoint-bezier curves (the same
// shape language as the Control Center's screen-time chart), so a quiet
// machine reads flat and a busy one climbs. The live head of each line is
// marked, and the legend carries the current numbers.
Item {
    id: root

    property var theme

    property real memUsedMb: 0
    property real memTotalMb: 0
    property real load1: NaN
    property real cpuPercent: 0
    property var memHistory: []
    property var cpuHistory: []

    property real _prevTotal: 0
    property real _prevIdle: 0
    property bool _cpuSeeded: false

    readonly property color cpuColor: root.theme ? root.theme.primary : "#ffffff"
    readonly property color memColor: root.theme ? root.theme.tertiary : "#c6c6c6"

    readonly property real memFraction: root.memTotalMb > 0
        ? Math.max(0, Math.min(1, root.memUsedMb / root.memTotalMb)) : 0
    readonly property string memValue: root.memTotalMb > 0
        ? Math.round(root.memFraction * 100) + "%" : "—"
    readonly property string memDetail: root.memTotalMb > 0
        ? (root.memUsedMb / 1024).toFixed(1)
            + " / " + (root.memTotalMb / 1024).toFixed(1) + "G"
        : ""
    readonly property string cpuValue: Math.round(root.cpuPercent) + "%"
    readonly property string cpuDetail: isNaN(root.load1)
        ? "" : "load " + root.load1.toFixed(2)

    function pushSample(list, value) {
        var next = list.slice()
        if (next.length >= 40) next.shift()
        next.push(Math.max(0, Math.min(1, value)))
        return next
    }

    function seed(value) {
        var next = []
        for (var i = 0; i < 40; i++) next.push(value)
        return next
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: root.theme ? root.theme.hairlineSoft : "#1a1a1a"
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.theme ? root.theme.statsHeaderHeight : 24

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                glyph: ""
                size: 12
                tint: root.theme
                    ? root.theme.alpha(root.theme.primary, 0.9) : "#ffffff"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Activity"
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.headingSize : 10
                font.letterSpacing: root.theme ? root.theme.headingTracking : 1.4
                font.weight: Font.DemiBold
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.cpuDetail !== ""
                text: root.cpuDetail
                color: root.theme ? root.theme.quiet : "#565656"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 9
                font.letterSpacing: 0.2
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18

            Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 2
                    radius: 1
                    color: root.cpuColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CPU"
                    color: root.theme ? root.theme.quiet : "#565656"
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.tinySize : 9
                    font.letterSpacing: 0.6
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cpuValue
                    color: root.cpuColor
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.smallSize : 10
                    font.weight: Font.DemiBold
                }
            }

            Row {
                spacing: 6

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 2
                    radius: 1
                    color: root.memColor
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "MEM"
                    color: root.theme ? root.theme.quiet : "#565656"
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.tinySize : 9
                    font.letterSpacing: 0.6
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.memValue
                    color: root.memColor
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.smallSize : 10
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    Canvas {
        id: graph
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: root.theme ? root.theme.statsChartTopGap : 10
        anchors.bottom: parent.bottom
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onMemHistoryChanged() { graph.requestPaint() }
            function onCpuHistoryChanged() { graph.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var W = width
            var H = height
            if (W <= 0 || H <= 0) return

            var padTop = 8
            var padBottom = 2
            var top = padTop
            var bottom = H - padBottom
            var usable = Math.max(1, bottom - top)

            function clamp01(v) {
                return Math.max(0, Math.min(1, v))
            }
            function Y(v) {
                return bottom - clamp01(v) * usable
            }
            function points(hist) {
                var n = hist.length
                var list = []
                for (var i = 0; i < n; i++)
                    list.push({ x: i * W / (n - 1), y: Y(hist[i]) })
                return list
            }
            function trace(pts) {
                ctx.beginPath()
                ctx.moveTo(pts[0].x, pts[0].y)
                for (var i = 1; i < pts.length; i++) {
                    var cx = (pts[i - 1].x + pts[i].x) / 2
                    ctx.bezierCurveTo(cx, pts[i - 1].y, cx, pts[i].y,
                        pts[i].x, pts[i].y)
                }
            }
            function fill(pts, color, alphaTop) {
                if (pts.length < 2) return
                trace(pts)
                ctx.lineTo(pts[pts.length - 1].x, bottom)
                ctx.lineTo(pts[0].x, bottom)
                ctx.closePath()
                var g = ctx.createLinearGradient(0, top, 0, bottom)
                g.addColorStop(0, root.theme
                    ? root.theme.alpha(color, alphaTop)
                    : "rgba(255,255,255," + alphaTop + ")")
                g.addColorStop(1, root.theme
                    ? root.theme.alpha(color, 0.0) : "rgba(255,255,255,0)")
                ctx.fillStyle = g
                ctx.fill()
            }
            function stroke(pts, color, lineWidth) {
                if (pts.length < 2) return
                trace(pts)
                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.stroke()
            }
            function head(pts, color) {
                if (pts.length === 0) return
                var p = pts[pts.length - 1]
                ctx.beginPath()
                ctx.arc(p.x, p.y, 6, 0, Math.PI * 2)
                ctx.fillStyle = root.theme
                    ? root.theme.alpha(color, 0.18)
                    : "rgba(255,255,255,0.18)"
                ctx.fill()
                ctx.beginPath()
                ctx.arc(p.x, p.y, 2.4, 0, Math.PI * 2)
                ctx.fillStyle = color
                ctx.fill()
            }

            // Fixed quarter rules: the scale is 0..100%, so quiet always
            // sits low and busy always sits high.
            ctx.strokeStyle = root.theme
                ? root.theme.alpha(root.theme.foreground, 0.055)
                : "rgba(255,255,255,0.055)"
            ctx.lineWidth = 1
            for (var r = 1; r <= 3; r++) {
                var gy = bottom - (r / 4) * usable
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(W, gy)
                ctx.stroke()
            }

            var memPts = root.memHistory.length >= 2
                ? points(root.memHistory) : []
            var cpuPts = root.cpuHistory.length >= 2
                ? points(root.cpuHistory) : []

            fill(memPts, root.memColor, 0.10)
            fill(cpuPts, root.cpuColor, 0.15)
            stroke(memPts, root.theme
                ? root.theme.alpha(root.memColor, 0.92) : "#c6c6c6", 1.7)
            stroke(cpuPts, root.cpuColor, 2.2)
            head(memPts, root.memColor)
            head(cpuPts, root.cpuColor)
        }
    }

    FileView {
        id: memView
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            var total = 0
            var avail = 0
            var lines = text().split("\n")
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].indexOf("MemTotal:") === 0)
                    total = parseInt(lines[i].split(/\s+/)[1], 10)
                else if (lines[i].indexOf("MemAvailable:") === 0)
                    avail = parseInt(lines[i].split(/\s+/)[1], 10)
            }
            if (total <= 0) return
            root.memTotalMb = total / 1024
            root.memUsedMb = Math.max(0, total - avail) / 1024
            var f = root.memUsedMb / root.memTotalMb
            root.memHistory = root.memHistory.length === 0
                ? root.seed(f) : root.pushSample(root.memHistory, f)
        }
    }

    FileView {
        id: statView
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            var first = text().split("\n")[0].trim()
            if (first.indexOf("cpu") !== 0) return
            var p = first.split(/\s+/)
            var total = 0
            for (var i = 1; i < p.length; i++)
                total += Number(p[i]) || 0
            var idle = (Number(p[4]) || 0) + (Number(p[5]) || 0)

            if (root._prevTotal > 0 && total > root._prevTotal) {
                var delta = total - root._prevTotal
                var pct = 100 * (1 - (idle - root._prevIdle) / delta)
                pct = Math.max(0, Math.min(100, pct))
                root.cpuPercent = root._cpuSeeded
                    ? root.cpuPercent * 0.55 + pct * 0.45 : pct
                var f = root.cpuPercent / 100
                root.cpuHistory = root._cpuSeeded
                    ? root.pushSample(root.cpuHistory, f) : root.seed(f)
                root._cpuSeeded = true
            }

            root._prevTotal = total
            root._prevIdle = idle
        }
    }

    FileView {
        id: loadView
        path: "/proc/loadavg"
        printErrors: false
        onLoaded: {
            var n = parseFloat(text())
            if (!isNaN(n)) root.load1 = n
        }
    }

    // Same-path FileView reads are no-ops; reset to empty first.
    Timer {
        interval: 4000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            memView.path = ""
            memView.path = "/proc/meminfo"
            statView.path = ""
            statView.path = "/proc/stat"
            loadView.path = ""
            loadView.path = "/proc/loadavg"
        }
    }
}
