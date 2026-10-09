import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import Qt5Compat.GraphicalEffects

// LyricsPane — "Focus" design: one sharp active line, context lines fall off
// by distance (blur d*2.6, opacity 1-d*.3 floor .1, scale 1-d*.07 floor .8),
// track auto-centers, left origin. Transparent, draggable anywhere.
// Lyrics from lrclib, fetched only while open, one request per track.
// Toggle: `ipc call lyrics toggle` (SUPER ALT L).
//
// FOCAL: the active line. Nothing else competes.
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

    readonly property int screenW: {
        try {
            var ss = Quickshell.screens
            var list = (ss && ss.values) ? ss.values : ss
            if (list && list.length) return list[0].width || 1920
        } catch (e) {}
        return 1920
    }
    readonly property int screenH: {
        try {
            var ss = Quickshell.screens
            var list = (ss && ss.values) ? ss.values : ss
            if (list && list.length) return list[0].height || 1080
        } catch (e) {}
        return 1080
    }

    property bool freeMove: false
    property int offX: 620
    property int offY: 676
    anchors { left: root.freeMove; top: root.freeMove; bottom: !root.freeMove }
    margins { left: root.offX; top: root.offY; bottom: 64 }
    implicitWidth: 680
    implicitHeight: 340
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    WlrLayershell.namespace: "qs-lyrics"

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

    // drag anywhere on the pane to move it; margins follow, stays where dropped
    MouseArea {
        id: dragMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: dragMa.pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property int px: 0
        property int py: 0
        onPressed: function (e) { root.freeMove = true; px = e.x; py = e.y }
        onPositionChanged: function (e) {
            if (!pressed) return
            root.offX += Math.round(e.x - px)
            root.offY += Math.round(e.y - py)
            px = e.x
            py = e.y
        }
    }

    Text {
        id: stateLine
        visible: root.lines.length === 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 58
        anchors.rightMargin: 58
        anchors.verticalCenter: parent.verticalCenter
        text: root.state === "quiet" ? "nothing playing"
            : root.state === "fetching" ? "finding lyrics…"
            : root.state === "none" ? "no lyrics found"
            : ""
        color: colors.alpha(colors.foreground, 0.5)
        font.family: "Inter"
        font.pixelSize: 22
        font.weight: Font.ExtraBold
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.85)
    }

    ListView {
        id: lineList
        visible: root.lines.length > 0
        anchors.fill: parent
        anchors.leftMargin: 58
        anchors.rightMargin: 58
        clip: true
        model: root.lines
        interactive: false
        spacing: 26
        currentIndex: root.currentIdx
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 130
        preferredHighlightEnd: 170
        highlightMoveDuration: 900
        highlightMoveVelocity: -1
        delegate: Text {
            required property var modelData
            required property int index
            readonly property int d: Math.abs(index - root.currentIdx)
            readonly property real fall: Math.max(0.8, 1 - d * 0.07)
            width: lineList.width
            wrapMode: Text.WordWrap
            text: modelData.x
            color: d === 0 ? colors.foreground : colors.alpha(colors.foreground, Math.max(0.1, 1 - d * 0.3))
            opacity: d === 0 ? 1 : Math.max(0.1, 1 - d * 0.3)
            font.family: "Inter"
            font.pixelSize: Math.round(34 * fall)
            font.weight: Font.ExtraBold
            font.letterSpacing: -0.7
            lineHeight: 1.12
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.85)
            layer.enabled: d > 0
            layer.effect: FastBlur {
                radius: Math.min(16, d * 2.6)
                transparentBorder: true
            }
            Behavior on opacity { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        }
    }
}
