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
    property real posBase: 0
    property double stampBase: 0
    property real karaP: 0      // 0..1 progress through the active line
    property real vortexPhase: 0  // UI-only twist phase (visual layer)
    property real vizLevel: 0     // smoothed cava average 0..100, drives the vortex
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
    implicitWidth: 660
    implicitHeight: 560
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    WlrLayershell.namespace: "qs-lyrics"

    onTrackKeyChanged: root.maybeFetch()
    onPlayingChanged: {
        root.posBase = root.player ? root.player.position : 0
        root.stampBase = Date.now()
        root.pos = root.posBase
    }
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
        root.winLines = []
        root.currentIdx = -1
        root.karaP = 0
        root.albumColor = colors.primary
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
        for (var i = 0; i < root.lines.length && i < 7; i++) out.push(root.lines[i].x)
        if (root.lines.length > 7) out.push("… · unsynced")
        return out.join("\n")
    }
    readonly property string terHex: "#" + colors.tertiary.toString().slice(-6)
    readonly property string dimHex: "#" + colors.outline.toString().slice(-6)
    readonly property string foreHex: "#" + colors.foreground.toString().slice(-6)
    function escHtml(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // mock fit(): wrap estimate, shrink until block height fits 60px —
    // two capped neighbors (42px halves) must stay inside 86px drum spacing
    function fitSize(raw) {
        var fs = 30
        while (fs > 14) {
            var rows = Math.ceil(raw.length * fs * 0.72 / 300)
            if (rows * fs * 1.35 <= 54) return fs
            fs--
        }
        return 14
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
                c = lit >= 0.5 ? root.terHex : root.foreHex
            } else c = root.foreHex
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
            if (root.lines[i].t <= root.pos + 0.05) idx = i
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
        // hard resync from the player: catches seeks, pauses, drift
        onTriggered: {
            root.posBase = root.player ? root.player.position : 0
            root.stampBase = Date.now()
            root.pos = root.posBase
        }
    }
    Timer {
        id: localTimer
        interval: 100
        running: root.open && root.playing && root.state === "ready"
        repeat: true
        // elapsed-time clock: immune to timer jitter, rebased on resync
        onTriggered: {
            root.pos = root.posBase + (Date.now() - root.stampBase) / 1000
            root.retrack()
        }
    }

    // rhythm feed — same cava tap as control center, averaged to one level
    Process {
        id: vizProc
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/scripts/cava-qs.conf"]
        running: root.open && root.playing
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var parts = line.trim().split(";")
                if (parts.length < 8) return
                var sum = 0
                for (var i = 0; i < parts.length; i++) sum += Math.max(0, Math.min(100, parseInt(parts[i]) || 0))
                var avg = sum / parts.length
                root.vizLevel = Math.max(avg, root.vizLevel * 0.92)
            }
        }
    }

    // album hue for the vortex: 1x1 dominant-color sample of the cover art
    // (same trick as NowPlaying — cached Image, no extra downloads)
    property color albumColor: colors.primary
    Image {
        id: artProbe
        width: 32; height: 32
        visible: false
        asynchronous: true
        cache: true
        source: root.player ? root.player.trackArtUrl : ""
        onStatusChanged: {
            if (status === Image.Ready) {
                artSampler.pendingUrl = source
                artSampler.loadImage(source)
            } else if (status === Image.Error) {
                root.albumColor = colors.primary
            }
        }
    }
    Canvas {
        id: artSampler
        width: 1; height: 1
        visible: false
        property string pendingUrl: ""
        onImageLoaded: {
            var ctx = getContext("2d")
            ctx.drawImage(pendingUrl, 0, 0, 1, 1)
            requestPaint()
        }
        onPaint: {
            var ctx = getContext("2d")
            var px = ctx.getImageData(0, 0, 1, 1).data
            var r = px[0] / 255, g = px[1] / 255, b = px[2] / 255
            var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if (lum < 0.10) { root.albumColor = colors.primary; return }
            var avg = (r + g + b) / 3, boost = 1.6
            root.albumColor = Qt.rgba(
                Math.min(1, Math.max(0, avg + (r - avg) * boost)),
                Math.min(1, Math.max(0, avg + (g - avg) * boost)),
                Math.min(1, Math.max(0, avg + (b - avg) * boost)), 1)
        }
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
        font.family: "Inter Display"
        font.pixelSize: 15
        font.weight: Font.Bold
        lineHeight: 1.9
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
        font.family: "Inter Display"
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
        readonly property real midX: width / 2
        readonly property real rad: Math.min(width, height) / 2 - 8
        readonly property real discR: rad * 0.62
        readonly property real drumR: discR - 30

        // art living inside the vortex hollow: blurred disc + legibility scrim
        Item {
            visible: root.state === "ready"
            anchors.centerIn: parent
            width: stage.discR * 2
            height: stage.discR * 2
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle { width: stage.discR * 2; height: stage.discR * 2; radius: stage.discR }
            }
            Image {
                id: artImg
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                layer.enabled: true
                layer.effect: FastBlur { radius: 24; transparentBorder: true }
            }
            Rectangle {
                anchors.fill: parent
                visible: artImg.status !== Image.Ready
                color: colors.alpha(colors.surface, 0.3)
            }
            Rectangle {
                anchors.fill: parent
                color: colors.alpha(colors.background, 0.45)
            }
        }

        // stored spiral-C orbiting the disc (timer sits with its canvas)
        Timer {
            interval: 50
            running: root.open && root.state === "ready"
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                root.vortexPhase += 0.09 + root.vizLevel / 100 * 0.3
                if (!root.playing) root.vizLevel *= 0.9
                vortex.requestPaint()
            }
        }
        Canvas {
            id: vortex
            visible: root.state === "ready"
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var t = root.vortexPhase
                var cx = stage.midX, cy = stage.midY
                var pulse = 1 + root.vizLevel / 100 * 0.9   // rays breathe with the beat
                for (var i = 0; i < 72; i++) {
                    var a = (i / 72) * Math.PI * 2 + t * 0.4
                    var wv = Math.sin(i * 0.35 - t * 2.2) * 0.5 + 0.5
                    var r0 = stage.discR + 4
                    var r1 = (stage.rad * 0.66 + wv * stage.rad * 0.3) * pulse
                    var accent = i % 6 === 0 ? colors.tertiary : root.albumColor
                    ctx.strokeStyle = colors.alpha(accent, i % 6 === 0 ? 0.95 : 0.6)
                    ctx.lineWidth = (i % 6 === 0 ? 2.4 : 1.8) + root.vizLevel / 100 * 1.2
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0)
                    ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1)
                    ctx.stroke()
                }
            }
        }

        Repeater {
            model: root.state === "ready" ? root.winLines : []
            delegate: Item {
                required property var modelData
                required property int index
                readonly property int li: root.winBase + index
                readonly property int d: li - root.currentIdx
                readonly property bool isActive: d === 0
                readonly property bool isPast: d < 0
                readonly property string raw: String(modelData.x)
                width: stage.width
                height: Math.min(84, Math.max(56, lyricText.implicitHeight + 12))
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
                // blur suspends mid-drag: layers don't re-render every move event
                layer.enabled: Math.abs(d) > 0 && !dragMa.pressed
                layer.effect: FastBlur {
                    radius: Math.min(10, Math.abs(d) * 1.6)
                    transparentBorder: true
                }

                // words: centered wrapping rich text, capped to the disc width
                Text {
                    id: lyricText
                    width: stage.discR * 1.45
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (parent.height - implicitHeight) / 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.RichText
                    text: root.richLine(raw, li)
                    font.family: "Inter Display"
                    font.pixelSize: root.fitSize(raw) * (isActive ? 1.15 : 1)
                    font.weight: Font.Bold
                    font.letterSpacing: -0.4
                    lineHeight: 1.35
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.85)
                }
            }
        }
    }
}
