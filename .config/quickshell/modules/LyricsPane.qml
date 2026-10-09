import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick

// LyricsPane — transparent synced-lyrics overlay. No background, no chrome:
// text only, floating bottom-center. Lyrics come from lrclib (direct
// artist+title lookup, ~1s, synced LRC lines included) instead of the
// player's own slower round-trip. Toggle with `ipc call lyrics toggle`
// (SUPER ALT L). Fetches only while open, one request per track.
//
// HEIGHT BUDGET ~250: credit 18 + list 190 + margins 42.
// FOCAL: the current line. Rank2: context lines. Rank3: credit.
PanelWindow {
    id: root

    property var colors
    property bool open: false

    property var player: Mpris.players.values.find(function (p) { return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string trackKey: (artist !== "" || title !== "") ? (artist + " - " + title) : ""
    readonly property bool playing: player !== null && player.playbackState === MprisPlaybackState.Playing

    property var lines: []
    property int currentIdx: -1
    property real pos: 0
    property string fetchedKey: ""
    property string state: "idle"   // idle | fetching | ready | plain | none | quiet

    anchors { bottom: true }
    margins { bottom: 64 }
    implicitWidth: 640
    implicitHeight: 250
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    WlrLayershell.namespace: "qs-lyrics"

    IpcHandler {
        target: "lyrics"
        function toggle(): void { root.open = !root.open }
    }

    onTrackKeyChanged: root.maybeFetch()
    onOpenChanged: {
        if (root.open) root.maybeFetch()
    }

    function maybeFetch() {
        if (!root.open) return
        if (root.trackKey === "") { root.state = "quiet"; root.lines = []; return }
        if (root.trackKey === root.fetchedKey) return
        root.fetchedKey = root.trackKey
        root.lines = []
        root.currentIdx = -1
        root.state = "fetching"
        var dur = (root.player && root.player.length > 0) ? Math.round(root.player.length) : 0
        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(root.artist)
            + "&track_name=" + encodeURIComponent(root.title)
            + (dur > 0 ? "&duration=" + dur : "")
        fetchProc.command = ["curl", "-s", "--max-time", "8", url]
        fetchProc.running = true
    }

    function parseLrc(synced) {
        var out = []
        var raw = synced.split("\n")
        for (var i = 0; i < raw.length; i++) {
            var line = raw[i]
            var re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
            var m
            var stamps = []
            while ((m = re.exec(line)) !== null) stamps.push(parseInt(m[1], 10) * 60 + parseFloat(m[2]))
            var text = line.replace(/\[[^\]]*\]/g, "").trim()
            if (stamps.length === 0 || text === "") continue
            for (var k = 0; k < stamps.length; k++) out.push({ t: stamps[k], x: text })
        }
        out.sort(function (a, b) { return a.t - b.t })
        return out
    }

    function retrack() {
        if (root.lines.length === 0 || root.state !== "ready") return
        var idx = -1
        for (var i = 0; i < root.lines.length; i++) {
            if (root.lines[i].t <= root.pos + 0.15) idx = i
            else break
        }
        root.currentIdx = idx
    }

    onPosChanged: root.retrack()

    Timer {
        id: posTimer
        interval: 500
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pos = root.player ? root.player.position : 0
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(text) } catch (e) { d = null }
                if (d && d.syncedLyrics) {
                    root.lines = root.parseLrc(d.syncedLyrics)
                    if (root.lines.length > 0) {
                        root.state = "ready"
                        root.retrack()
                    } else root.state = "none"
                } else if (d && d.plainLyrics) {
                    var parts = d.plainLyrics.split("\n")
                    var arr = []
                    for (var i = 0; i < parts.length; i++) {
                        if (parts[i].trim() !== "") arr.push({ t: -1, x: parts[i].trim() })
                    }
                    root.lines = arr
                    root.state = arr.length > 0 ? "plain" : "none"
                } else root.state = "none"
            }
        }
        onExited: function (code) {
            if (code !== 0 && root.state === "fetching") root.state = "none"
        }
    }

    // state line: credit / status, dim and small — never the focus
    Text {
        id: credit
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        horizontalAlignment: Text.AlignHCenter
        text: root.state === "quiet" ? "nothing playing"
            : root.state === "fetching" ? "finding lyrics…"
            : root.state === "none" ? "no lyrics found"
            : root.trackKey
        color: colors.alpha(colors.outline, 0.7)
        font.family: colors.fontSans
        font.pixelSize: 10
        font.letterSpacing: 1.2
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.75)
    }

    ListView {
        id: lineList
        visible: root.lines.length > 0
        anchors.top: credit.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 6
        clip: true
        model: root.lines
        interactive: false
        currentIndex: root.currentIdx
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 70
        preferredHighlightEnd: 110
        highlightMoveDuration: 250
        delegate: Text {
            required property var modelData
            required property int index
            width: lineList.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: modelData.x
            color: index === root.currentIdx ? colors.primary : colors.alpha(colors.foreground, 0.55)
            font.family: colors.fontSans
            font.pixelSize: index === root.currentIdx ? 17 : 13
            font.weight: index === root.currentIdx ? Font.Bold : Font.Normal
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.8)
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }
}
