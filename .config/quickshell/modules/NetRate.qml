import Quickshell.Io
import QtQuick

// Live network throughput sampler — parses /proc/net/dev once a second,
// exposes rx/tx rates in KB/s. Reusable (panel + bar pill).
Item {
    id: root

    property real rxKbs: 0   // download KB/s
    property real txKbs: 0   // upload KB/s
    property var rxHistory: []   // last N samples for sparklines
    readonly property int historyLen: 40
    property real totalRxMb: 0   // cumulative since boot
    property real totalTxMb: 0

    property string _prevLine: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            devFile.path = ""               // drop handle...
            devFile.path = "/proc/net/dev"  // ...then force fresh read
        }
    }

    FileView {
        id: devFile
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: {
            var totalRx = 0, totalTx = 0
            var lines = text().split("\n")
            for (var i = 2; i < lines.length; i++) {   // skip headers
                var parts = lines[i].split(":")
                if (parts.length !== 2) continue
                var iface = parts[0].trim()
                if (iface === "lo") continue
                var fields = parts[1].trim().split(/\s+/)
                if (fields.length < 9) continue
                totalRx += parseInt(fields[0]) || 0
                totalTx += parseInt(fields[8]) || 0
            }
            root.totalRxMb = totalRx / 1024 / 1024
            root.totalTxMb = totalTx / 1024 / 1024
            if (_prevLine !== "") {
                root.rxKbs = Math.max(0, (totalRx - _prevRx) / 1024)
                root.txKbs = Math.max(0, (totalTx - _prevTx) / 1024)
            }
            _prevRx = totalRx; _prevTx = totalTx; _prevLine = "init"

            var h = root.rxHistory.slice()
            h.push(root.rxKbs)
            if (h.length > root.historyLen) h.shift()
            root.rxHistory = h
        }
    }

    property real _prevRx: 0
    property real _prevTx: 0

    function fmtTotal(mb) {
        if (mb >= 1024) return (mb / 1024).toFixed(1) + " GB"
        return mb.toFixed(0) + " MB"
    }

    function fmt(kbs) {
        if (kbs >= 1024 * 1024) return (kbs / 1024 / 1024).toFixed(1) + " GB/s"
        if (kbs >= 1024) return (kbs / 1024).toFixed(1) + " MB/s"
        return kbs.toFixed(0) + " KB/s"
    }
}
