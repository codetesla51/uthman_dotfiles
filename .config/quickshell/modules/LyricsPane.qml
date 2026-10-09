import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

// LyricsPane — "Safe Dial" design on the theme palette: lyric lines ride a
// rotating drum (30deg per line, R = 40% of stage), active line centered in a
// hairline window with accent pointers, karaoke word-flip driven by the same
// timing math as the mock (word i lights at p*n-i), line numbers in mono.
// Cyan -> primary, pink -> secondary, whites -> foreground/outline.
// Lyrics engine (lrclib fetch, LRC parse, MPRIS follow, drag) unchanged.
// Toggle: `ipc call lyrics toggle` (SUPER ALT L).
//
// One honest approximation: the mock sweeps a gradient across each word;
// QML flips whole words (lit at half progress) — same pacing, no sweep.
// FOCAL: the active line in the window. Nothing else competes.
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
    property real karaP: 0      // 0..1 progress through the active line
    property string fetchedKey: ""
    property int attempt: 0        // 0 = artist+title+duration, 1 = no duration, 2+ = timed retries
    property string state: "idle"   // idle | fetching | ready | plain | none | quiet

    // drum window: ±3 lines instantiated, the rest stay out of the tree
    property var winLines: []
    property int winBase: 0
    onCurrentIdxChanged: root.rewindow()
    onLinesChanged: root.rewindow()
    function rewindow() {
        if (root.state !== "ready") { root.winLines = []; return }
        var b = Math.max(0, root.currentIdx - 3)
        root.winBase = b
        root.winLines = root.lines.slice(b, b + 7)
    }

    property bool freeMove: false
    property int offX: 620
    property int offY: 590
    anchors { left: root.freeMove; top: root.freeMove; bottom: !root.freeMove }
    margins { left: root.offX; top: root.offY; bottom: 64 }
    implicitWidth: 680
    implicitHeight: 430
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
        root.attempt = 0
        root.fetchAttempt()
    }
    function fetchAttempt() {
        root.lines = []
        root.currentIdx = -1
        root.karaP = 0
        root.state = "fetching"
        var dur = (root.player && root.player.length > 0) ? Math.round(root.player.length) : 0
        var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(root.artist)
            + "&track_name=" + encodeURIComponent(root.title)
            + (root.attempt === 0 && dur > 0 ? "&duration=" + dur : "")
        fetchProc.command = ["curl", "-s", "--max-time", "8", url]
        fetchProc.running = true
    }
    // miss ladder: drop duration (mismatch is the top miss reason), then two
    // timed retries for hotspot blips. 3 attempts total, then rest on none.
    function scheduleRetry() {
        if (root.attempt >= 2) { root.state = "none"; return }
        root.attempt += 1
        retryTimer.interval = root.attempt === 1 ? 100 : 8000
        retryTimer.restart()
    }
    Timer {
        id: retryTimer
        repeat: false
        onTriggered: {
            if (!root.open || root.trackKey === "" || root.trackKey !== root.fetchedKey) return
            root.fetchAttempt()
        }
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

    function plainText() {
        var out = []
        for (var i = 0; i < root.lines.length && i < 10; i++) out.push(root.lines[i].x)
        if (root.lines.length > 10) out.push("…")
        return out.join("\n")
    }
    readonly property string terHex: "#" + colors.tertiary.toString().slice(-6)
    readonly property string dimHex: "#" + colors.outline.toString().slice(-6)
    function escHtml(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // mock fit(): wrap estimate, shrink until block height fits 73px (17% of stage)
    function fitSize(raw) {
        var fs = 26
        while (fs > 13) {
            var rows = Math.ceil(raw.length * fs * 0.6 / 540)
            if (rows * fs * 1.15 <= 73) return fs
            fs--
        }
        return 13
    }
    function richLine(raw, li) {
        var ws = String(raw).split(" ")
        var d = li - root.currentIdx
        var out = []
        for (var i = 0; i < ws.length; i++) {
            var c
            if (d < 0) c = root.terHex
            else if (d === 0) {
                var lit = Math.max(0, Math.min(1, root.karaP * ws.length - i))
                c = lit >= 0.5 ? root.terHex : root.dimHex
            } else c = root.dimHex
            out.push('<font color="' + c + '">' + root.escHtml(ws[i]) + "</font>")
        }
        return out.join(" ")
    }
    function lineDur(a) {
        if (a < 0 || a >= root.lines.length) return 0
        if (a + 1 < root.lines.length) return root.lines[a + 1].t - root.lines[a].t
        if (root.player && root.player.length > 0) return root.player.length - root.lines[a].t
        return 0
    }

    function retrack() {
        if (root.lines.length === 0 || root.state !== "ready") return
        var idx = -1
        for (var i = 0; i < root.lines.length; i++) {
            if (root.lines[i].t <= root.pos + 0.15) idx = i
            else break
        }
        root.currentIdx = idx
        root.rekara()
    }

    function rekara() {
        var a = root.currentIdx
        if (a < 0 || root.state !== "ready") { root.karaP = 0; return }
        var dur = root.lineDur(a)
        if (dur <= 0) { root.karaP = 0; return }
        var p = (root.pos - root.lines[a].t) / (dur * 0.85)
        root.karaP = Math.max(0, Math.min(1, p))
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
    Timer {
        id: karaTimer
        interval: 150
        running: root.open && root.state === "ready"
        repeat: true
        onTriggered: root.rekara()
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
                } else root.scheduleRetry()
            }
        }
        onExited: function (code) {
            if (code !== 0 && root.state === "fetching") root.scheduleRetry()
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
        id: plainBlock
        visible: root.state === "plain"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 58
        anchors.rightMargin: 58
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
        text: root.plainText()
        color: colors.alpha(colors.foreground, 0.75)
        font.family: "Inter"
        font.pixelSize: 16
        font.weight: Font.Bold
        wrapMode: Text.WordWrap
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.85)
    }

    Text {
        id: stateLine
        visible: root.state !== "ready" && root.state !== "plain"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 58
        anchors.rightMargin: 58
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignHCenter
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

    // ---- drum stage ----
    Item {
        id: stage
        visible: root.lines.length > 0
        anchors.fill: parent
        readonly property real midY: height / 2
        readonly property real drumR: height * 0.4

        // window band hairlines
        Rectangle {
            width: parent.width
            height: 1
            y: parent.midY - 27
            color: colors.alpha(colors.outline, 0.2)
        }
        Rectangle {
            width: parent.width
            height: 1
            y: parent.midY + 27
            color: colors.alpha(colors.outline, 0.2)
        }
        // pointers
        Shape {
            width: 14
            height: 18
            y: parent.midY - 9
            ShapePath {
                fillColor: colors.tertiary
                strokeColor: "transparent"
                PathMove { x: 0; y: 0 }
                PathLine { x: 14; y: 9 }
                PathLine { x: 0; y: 18 }
                PathLine { x: 0; y: 0 }
            }
        }
        Shape {
            width: 14
            height: 18
            x: parent.width - 14
            y: parent.midY - 9
            ShapePath {
                fillColor: colors.tertiary
                strokeColor: "transparent"
                PathMove { x: 14; y: 0 }
                PathLine { x: 0; y: 9 }
                PathLine { x: 14; y: 18 }
                PathLine { x: 14; y: 0 }
            }
        }

        Repeater {
            model: root.winLines
            delegate: Item {
                required property var modelData
                required property int index
                readonly property int li: root.winBase + index
                readonly property int d: li - root.currentIdx
                readonly property bool isActive: d === 0
                readonly property bool isPast: d < 0
                readonly property string raw: String(modelData.x)
                width: stage.width
                height: Math.min(110, Math.max(52, lyricText.implicitHeight + 10))
                clip: true
                visible: Math.abs(d) <= 3
                y: stage.midY + stage.drumR * Math.sin(d * Math.PI / 6) - height / 2
                Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                opacity: Math.max(0, 1 - Math.abs(d) * 0.3)
                Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                rotation: 0
                transform: Rotation {
                    axis { x: 1; y: 0; z: 0 }
                    origin.x: width / 2
                    origin.y: height / 2
                    angle: -d * 30
                    Behavior on angle { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                }
                layer.enabled: Math.abs(d) > 0
                layer.effect: FastBlur {
                    radius: Math.min(10, Math.abs(d) * 1.6)
                    transparentBorder: true
                }

                // tick
                Rectangle {
                    width: 34
                    height: 3
                    radius: 2
                    x: 27
                    y: 26 - 1.5
                    color: isActive ? colors.tertiary : colors.alpha(colors.foreground, 0.55)
                }
                // line number
                Text {
                    x: 27
                    y: 26 + 8
                    text: li + 1 < 10 ? "0" + (li + 1) : "" + (li + 1)
                    color: isActive ? colors.tertiary : colors.alpha(colors.foreground, 0.4)
                    font.family: "JetBrainsMono Nerd Font Mono"
                    font.pixelSize: 12
                    font.letterSpacing: 2
                }
                // words: centered wrapping rich text — long lines wrap then
                // shrink until the block fits 73px; rails never touched
                Text {
                    id: lyricText
                    width: 540
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height - implicitHeight) / 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.RichText
                    text: root.richLine(raw, li)
                    font.family: "Inter"
                    font.pixelSize: root.fitSize(raw)
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                    lineHeight: 1.15
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.85)
                }
            }
        }
    }
}
