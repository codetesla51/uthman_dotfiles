import Quickshell
import Quickshell.Io
import QtQuick

// LyricsSource — LRCLIB synced lyrics for the current MPRIS track.
// Cache first (one file per artist/title), then two network attempts:
// with duration, then without (duration mismatches are the usual miss).
// Every failure lands in state "none" and renders nothing.
QtObject {
    id: root

    property var config
    property string artist: ""
    property string title: ""
    property real duration: 0
    property bool active: true

    property var lines: []
    property string state: "idle"   // idle | loading | ready | none
    property string trackKey: ""
    property string cachePath: ""
    property int attempt: 0
    property bool _fromCache: false

    readonly property string cacheDir: root.config ? root.config.lyricsCacheDir : ""

    function sanitize(s) {
        return String(s).replace(/[^A-Za-z0-9 ._-]/g, "_").slice(0, 110)
    }

    function cachePathFor() {
        if (root.cacheDir === "") return ""
        var base = root.sanitize(root.artist + " - " + root.title)
        if (base === "" || base === " - ") return ""
        return root.cacheDir + "/" + base + ".lrc"
    }

    function refetch() {
        var a = root.artist.trim()
        var t = root.title.trim()
        if (!root.active || a === "" || t === "") {
            root.lines = []
            root.state = "idle"
            root.trackKey = ""
            return
        }
        var key = a + "\n" + t
        if (key === root.trackKey && (root.state === "loading" || root.state === "ready"))
            return
        root.trackKey = key
        root.lines = []
        root.state = "loading"
        root.attempt = 0
        root._fromCache = false
        root.cachePath = root.cachePathFor()
        if (root.cachePath === "") {
            root.fetchAttempt()
            return
        }
        cacheView.path = ""
        cacheView.path = root.cachePath
    }

    onArtistChanged: root.refetch()
    onTitleChanged: root.refetch()
    onActiveChanged: {
        if (root.active) root.refetch()
        else {
            root.lines = []
            root.state = "idle"
        }
    }

    function parseLrc(synced) {
        var out = []
        var raw = String(synced).split("\n")
        for (var i = 0; i < raw.length; i++) {
            var line = raw[i]
            var re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
            var m
            var stamps = []
            while ((m = re.exec(line)) !== null)
                stamps.push(parseInt(m[1], 10) * 60 + parseFloat(m[2]))
            var text = line.replace(/\[[^\]]*\]/g, "").trim()
            if (stamps.length === 0 || text === "") continue
            for (var k = 0; k < stamps.length; k++)
                out.push({ t: stamps[k], x: text })
        }
        out.sort(function (a, b) { return a.t - b.t })
        return out
    }

    function apply(raw, fromCache) {
        var parsed = root.parseLrc(raw)
        if (parsed.length > 0) {
            root.lines = parsed
            root.state = "ready"
            root._fromCache = !!fromCache
            if (!fromCache && root.cachePath !== "" && root.cacheView.path !== "")
                root.cacheView.setText(raw)
            return
        }
        if (root.state === "loading") root.fetchAttempt()
    }

    function fetchAttempt() {
        if (root.attempt >= 2) {
            root.state = "none"
            return
        }
        root.attempt += 1
        var url = "https://lrclib.net/api/get"
            + "?artist_name=" + encodeURIComponent(root.artist)
            + "&track_name=" + encodeURIComponent(root.title)
            + (root.attempt === 1 && root.duration > 0
                ? "&duration=" + Math.round(root.duration) : "")
        fetchProc.command = ["curl", "-sL", "--max-time", "10", url]
        fetchProc.running = true
    }

    property FileView cacheView: FileView {
        path: ""
        printErrors: false
        onLoaded: {
            if (root.state === "loading")
                root.apply(text(), true)
        }
        onLoadFailed: {
            if (root.state === "loading")
                root.fetchAttempt()
        }
    }

    property Process fetchProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var d = null
                try {
                    d = JSON.parse(text)
                } catch (e) {
                    d = null
                }
                if (d && d.syncedLyrics) {
                    root.apply(d.syncedLyrics, false)
                } else if (root.state === "loading") {
                    root.fetchAttempt()
                }
            }
        }
        onExited: function (code) {
            if (code !== 0 && root.state === "loading")
                root.fetchAttempt()
        }
    }

    property Process mkdirProc: Process {
        command: ["mkdir", "-p", root.cacheDir]
        running: false
    }

    Component.onCompleted: {
        if (root.cacheDir !== "") root.mkdirProc.running = true
        root.refetch()
    }
}