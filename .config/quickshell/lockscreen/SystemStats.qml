import Quickshell
import Quickshell.Io
import QtQuick

// SystemStats — real memory and CPU graphs from /proc. One sample every
// four seconds while the lock is up (nothing when it is not), forty samples
// of history, fixed 0..100% scale. No synthetic data.
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

    SystemMeter {
        id: memMeter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.theme ? root.theme.meterTopMargin : 18
        height: root.theme ? root.theme.meterHeight : 86
        theme: root.theme
        label: "Memory"
        glyph: ""
        valueText: root.memValue
        detailText: root.memDetail
        history: root.memHistory
        tint: root.theme ? root.theme.secondary : "#ffffff"
    }

    SystemMeter {
        id: cpuMeter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: memMeter.bottom
        anchors.topMargin: root.theme ? root.theme.meterGap : 20
        height: root.theme ? root.theme.meterHeight : 86
        theme: root.theme
        label: "CPU"
        glyph: ""
        valueText: root.cpuValue
        detailText: root.cpuDetail
        history: root.cpuHistory
        tint: root.theme ? root.theme.primary : "#ffffff"
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