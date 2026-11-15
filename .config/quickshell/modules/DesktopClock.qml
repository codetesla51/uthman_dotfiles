import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "desktopclock"
import "../components/Bloom.js" as Bloom

// DesktopClock — replaces the wallpaper daemon: one full-screen surface on the
// background layer that draws the wallpaper, the clock, and the subject cutout
// stacked on top of the digits.
//
// Layer order: wallpaper -> clock -> cutout -> date.
// No motion except the wallpaper/cutout crossfade.
PanelWindow {
    id: root

    property var colors

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qs-desktopclock"
    color: "transparent"

    // ---- wallpaper source: the same symlink the shell and set-wallpaper use ----
    property string wallpaperPath: ""

    // Derive from the passed path, not from wallpaperPath, when reacting to a
    // change: a handler can run before sibling bindings have re-evaluated, and
    // reading metaPath there used to hand FileView the previous wallpaper.
    function nameFor(p) {
        if (!p) return ""
        var slash = p.lastIndexOf("/")
        var base = slash >= 0 ? p.substring(slash + 1) : p
        var dot = base.lastIndexOf(".")
        return dot > 0 ? base.substring(0, dot) : base
    }
    readonly property string wallName: nameFor(wallpaperPath)

    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/wallcut"
    readonly property string cutoutPath: cacheDir + "/" + wallName + ".png"
    readonly property string metaPath: cacheDir + "/" + wallName + ".json"
    readonly property string blurPath: cacheDir + "/" + wallName + "-blur.jpg"
    function metaFor(p) { return cacheDir + "/" + nameFor(p) + ".json" }

    property bool cutoutExists: false
    property bool blurExists: false
    property var cutBBox: null
    property var cutGrid: null
    property int gridW: 0
    property int gridH: 0
    property bool forceHideCutout: false
    // Clock + cutout + date all hide together; the wallpaper stays drawn so
    // the desktop never falls back to an empty surface.
    property bool showClock: true

    // Reveal animation: the clock blooms in with a small upward drift and a
    // damped overshoot, then folds away quickly. clockVisible keeps the items
    // mapped until the exit finishes; reveal drives opacity, scale and motion.
    property bool clockVisible: true
    property real reveal: 1
    function playClockReveal() {
        if (showClock) {
            clockVisible = true
            revealOut.stop()
            revealIn.start()
        } else {
            revealIn.stop()
            revealOut.start()
        }
    }
    onShowClockChanged: playClockReveal()

    SpringAnimation {
        id: revealIn
        target: root
        property: "reveal"
        to: 1
        spring: Bloom.islandSpring
        damping: 0.62
        mass: Bloom.islandMass
        epsilon: Bloom.islandEpsilon
    }
    NumberAnimation {
        id: revealOut
        target: root
        property: "reveal"
        to: 0
        duration: 280
        easing.type: Easing.Bezier
        easing.bezierCurve: Bloom.out
        onFinished: if (!root.showClock) root.clockVisible = false
    }

    // ---- palette: live Matugen theme, wallpaper fallback if the file is gone ----
    property bool themeMissing: false
    readonly property color primary: themeMissing ? extracted.primary : colors.primary
    readonly property color secondary: themeMissing ? extracted.secondary : colors.secondary
    readonly property color tertiary: themeMissing ? extracted.primary : colors.tertiary
    readonly property color foreground: colors.foreground
    readonly property color background: colors.background
    readonly property color outline: colors.outline

    // ---- layout: auto picks row unless the subject would bury a digit pair ----
    property string cfgLayout: "auto"       // auto | row | stack
    property var cfgOverrides: ({})
    property string autoLayout: "row"
    readonly property string layout: cfgOverrides[wallName] !== undefined
        ? cfgOverrides[wallName]
        : (cfgLayout === "auto" ? autoLayout : cfgLayout)

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property string hh: String(clock.hours).padStart(2, "0")
    readonly property string mm: String(clock.minutes).padStart(2, "0")

    readonly property string dowText: {
        var d = clock.date
        return d ? Qt.locale().dayName(d.getDay(), Locale.LongFormat) : ""
    }
    readonly property string restText: {
        var d = clock.date
        if (!d) return ""
        return d.getDate() + " " + Qt.locale().monthName(d.getMonth(), Locale.LongFormat)
    }

    // bbox overlap between the cutout's opaque area and the clock's glyph box.
    // Fallback only, for sidecars written before the alpha grid existed.
    function overlapRatio() {
        var bb = cutBBox
        if (!bb || bb.length !== 4) return 0
        var r = clock2.glyphRect
        var bx = bb[0] * width, by = bb[1] * height
        var bw = (bb[2] - bb[0]) * width, bh = (bb[3] - bb[1]) * height
        var x1 = Math.max(r.x, bx), y1 = Math.max(r.y, by)
        var x2 = Math.min(r.x + r.width, bx + bw), y2 = Math.min(r.y + r.height, by + bh)
        var iw = Math.max(0, x2 - x1), ih = Math.max(0, y2 - y1)
        return (iw * ih) / Math.max(1, r.width * r.height)
    }

    // true opaque coverage of the clock box, from the sidecar's alpha grid.
    // Returns -1 when the sidecar has no grid (old file).
    function coverageOf(r) {
        var g = cutGrid
        if (!g || gridW <= 0 || gridH <= 0) return -1
        var cw = width / gridW, ch = height / gridH
        var total = 0
        for (var gy = 0; gy < gridH; gy++) {
            var y0 = gy * ch, y1 = y0 + ch
            var iy = Math.min(r.y + r.height, y1) - Math.max(r.y, y0)
            if (iy <= 0) continue
            for (var gx = 0; gx < gridW; gx++) {
                var x0 = gx * cw, x1 = x0 + cw
                var ix = Math.min(r.x + r.width, x1) - Math.max(r.x, x0)
                if (ix <= 0) continue
                total += ix * iy * g[gy * gridW + gx]
            }
        }
        return total / Math.max(1, r.width * r.height)
    }

    readonly property real cutCoverage: coverageOf(clock2.glyphRect)
    readonly property bool showCutout: cutoutExists && !forceHideCutout
        && (cutCoverage >= 0 ? cutCoverage <= 0.85 : overlapRatio() <= 0.85)

    // ---- placement: keep both digit pairs readable, and keep some overlap ----
    // The total area is not enough: a subject can cover 20% of the box and all
    // of it on the minutes. Hours and minutes are scored separately so one
    // pair cannot be buried while the other stays clean.
    property real shiftX: 0      // normalized, 0 = centered
    property real shiftY: 0

    // Resting tilt: the face leans on the subject, pivoted at the point where
    // the cutout actually crosses the digits (not the screen center).
    property real clockTilt: 0
    property real tiltPivotX: width * 0.5
    property real tiltPivotY: height * 0.5

    function coverageFraction(r, fx0, fy0, fx1, fy1) {
        return coverageOf(Qt.rect(r.x + r.width * fx0, r.y + r.height * fy0,
                                  r.width * (fx1 - fx0), r.height * (fy1 - fy0)))
    }

    // Alpha-weighted center of the subject inside the clock box. This is the
    // physical contact mass the face can lean on.
    function contactCentroid(r) {
        var g = cutGrid
        if (!g || gridW <= 0 || gridH <= 0) return null
        var cw = width / gridW, ch = height / gridH
        var sw = 0, sx = 0, sy = 0
        for (var gy = 0; gy < gridH; gy++) {
            var y0 = gy * ch, y1 = y0 + ch
            var iy = Math.min(r.y + r.height, y1) - Math.max(r.y, y0)
            if (iy <= 0) continue
            for (var gx = 0; gx < gridW; gx++) {
                var x0 = gx * cw, x1 = x0 + cw
                var ix = Math.min(r.x + r.width, x1) - Math.max(r.x, x0)
                if (ix <= 0) continue
                var a = g[gy * gridW + gx]
                if (a <= 0) continue
                var k = ix * iy * a
                sw += k
                sx += k * (x0 + x1) * 0.5
                sy += k * (y0 + y1) * 0.5
            }
        }
        return sw > 0 ? { x: sx / sw, y: sy / sw } : null
    }

    // Peak alpha over the two readable zones. Row: HH | colon | MM.
    // Stack: HH above, MM below.
    function zonePeak(r, stacked) {
        if (stacked)
            return Math.max(coverageFraction(r, 0, 0, 1, 0.5),
                            coverageFraction(r, 0, 0.5, 1, 1))
        return Math.max(coverageFraction(r, 0, 0, 0.437, 1),
                        coverageFraction(r, 0.563, 0, 1, 1))
    }

    // Score every legal position for one layout. The peak penalty is strong:
    // moving the clock beats half-covering one digit pair.
    function bestSpot(gw, gh, stacked) {
        var cx = (width - gw) / 2
        var cy = (height - gh) / 2
        var mx = Math.max(16, width * 0.06)
        var top = Math.max(64, height * 0.06)          // clear the bar
        var bottom = height * 0.085                    // leave the date line alone

        var minSX = (mx - cx) / width
        var maxSX = (width - mx - gw - cx) / width
        var minSY = (top - cy) / height
        var maxSY = (height - bottom - gh - cy) / height
        if (minSX > maxSX) { minSX = 0; maxSX = 0 }
        if (minSY > maxSY) { minSY = 0; maxSY = 0 }

        var centerRect = Qt.rect(cx, cy, gw, gh)
        var centerCov = coverageOf(centerRect)
        var centerPeak = zonePeak(centerRect, stacked)
        // Nothing meaningful on the digits: stay exactly centered.
        if (centerCov <= 0.08 && centerPeak <= 0.12)
            return { x: 0, y: 0, cov: centerCov, peak: centerPeak, score: centerCov }

        var xs = [-0.34, -0.26, -0.18, -0.10, -0.04, 0,
                  0.04, 0.10, 0.18, 0.26, 0.34]
        var ys = [-0.22, -0.15, -0.08, 0, 0.08, 0.15, 0.22]
        var best = null

        for (var iy = 0; iy < ys.length; iy++) {
            for (var ix = 0; ix < xs.length; ix++) {
                var sx = Math.max(minSX, Math.min(maxSX, xs[ix]))
                var sy = Math.max(minSY, Math.min(maxSY, ys[iy]))
                var r = Qt.rect(cx + sx * width, cy + sy * height, gw, gh)
                var cov = coverageOf(r)
                var peak = zonePeak(r, stacked)
                // Aim for a visible overlap (~10% of the box) instead of zero:
                // the character must actually cross the digits for depth. The
                // peak penalty is deliberately harsh: a pair 18% covered is
                // already hard to read when the cutout edge crosses strokes.
                var score = Math.abs(cov - 0.10) * 2.0
                    + 4.0 * Math.max(0, peak - 0.18)
                    + 0.03 * (Math.abs(sx) + Math.abs(sy))
                if (best === null || score < best.score)
                    best = { x: sx, y: sy, cov: cov, peak: peak, score: score }
            }
        }
        return best
    }

    function choosePlacement() {
        if (!cutGrid || gridW <= 0) {
            autoLayout = "row"
            shiftX = 0
            shiftY = 0
            clockTilt = 0
            return
        }

        var rowW = clock2.rowTextSize.width, rowH = clock2.rowTextSize.height
        var stackW = clock2.stackTextSize.width, stackH = clock2.stackTextSize.height
        if (rowW <= 0 || rowH <= 0 || stackW <= 0 || stackH <= 0) return

        var forced = cfgOverrides[wallName] !== undefined
            ? cfgOverrides[wallName]
            : (cfgLayout !== "auto" ? cfgLayout : "")

        var row = bestSpot(rowW, rowH, false)
        var stack = null
        var useStack = false

        if (forced === "stack") {
            useStack = true
        } else if (forced === "") {
            stack = bestSpot(stackW, stackH, true)
            // Row stays the default. Stack only when the row cannot keep a
            // digit pair readable, and only if stacking clearly improves it.
            // 24% of a zone is already enough to make a pair squint-worthy.
            useStack = row.peak > 0.24 && stack.peak < row.peak - 0.06
        }

        if (useStack && stack === null)
            stack = bestSpot(stackW, stackH, true)
        var pick = useStack ? stack : row
        autoLayout = useStack ? "stack" : "row"
        shiftX = pick.x
        shiftY = pick.y

        var gw = useStack ? stackW : rowW
        var gh = useStack ? stackH : rowH
        var box = Qt.rect((width - gw) / 2 + pick.x * width,
                          (height - gh) / 2 + pick.y * height, gw, gh)
        var contact = cutoutExists && showCutout ? contactCentroid(box) : null
        if (contact && pick.cov >= 0.04) {
            // Lift the side the subject stands on, pivoting on the actual
            // contact mass so the digits read as resting against her.
            var subjX = cutBBox ? (cutBBox[0] + cutBBox[2]) * 0.5 * width : width / 2
            var dir = subjX > width / 2 + width * 0.04 ? -1
                    : (subjX < width / 2 - width * 0.04 ? 1 : -1)
            clockTilt = dir * 3.0
            tiltPivotX = contact.x
            tiltPivotY = contact.y
        } else {
            clockTilt = 0
            tiltPivotX = box.x + gw / 2
            tiltPivotY = box.y + gh / 2
        }
    }

    onLayoutChanged: Qt.callLater(choosePlacement)
    onWidthChanged: Qt.callLater(choosePlacement)
    onHeightChanged: Qt.callLater(choosePlacement)

    Connections {
        target: clock2
        function onRowTextSizeChanged() { Qt.callLater(root.choosePlacement) }
        function onStackTextSizeChanged() { Qt.callLater(root.choosePlacement) }
    }

    Wallpaper {
        id: wall
        anchors.fill: parent
        path: root.wallpaperPath
    }

    ClockFace {
        id: clock2
        anchors.fill: parent
        visible: root.clockVisible
        opacity: Math.max(0, Math.min(1, root.reveal * 1.8))
        scale: 0.62 + 0.38 * root.reveal
        rotation: -2.5 * (1 - root.reveal)
        focusBlur: Math.max(0, Math.min(1, 1 - root.reveal))
        transform: Translate { y: root.height * 0.06 * (1 - root.reveal) }
        hh: root.hh
        mm: root.mm
        layout: root.layout
        shiftX: root.shiftX
        shiftY: root.shiftY
        tilt: root.showCutout ? root.clockTilt : 0
        tiltPivotX: root.tiltPivotX
        tiltPivotY: root.tiltPivotY
        primary: root.primary
        secondary: root.secondary
        tertiary: root.tertiary
        foreground: root.foreground
        background: root.background
        outline: root.outline
        blurSource: root.blurExists ? root.blurPath : ""
        frost: root.blurExists
    }

    Subject {
        id: subject
        anchors.fill: parent
        visible: root.clockVisible
        opacity: Math.max(0, Math.min(1, (root.reveal - 0.15) * 1.4))
        source: root.showCutout ? root.cutoutPath : ""
        // Never let the previous cutout sit over a wallpaper it doesn't
        // belong to: reveal only after the new backdrop has fully landed.
        gate: wall.settled && wall.currentPath === root.wallpaperPath
    }

    // Date — above the subject, so a cutout reaching the bottom edge cannot
    // hide it. Pinned to the bottom edge, out of the clock's way.
    Row {
        id: dateRow
        visible: root.clockVisible
        opacity: Math.max(0, Math.min(1, (root.reveal - 0.3) * 1.6))
        transform: Translate { y: root.height * 0.025 * (1 - root.reveal) }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.height * 0.045
        spacing: root.width * 0.012

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.4
            shadowVerticalOffset: 1
            shadowColor: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.85)
        }

        Rectangle {
            width: root.width * 0.026
            height: 1
            color: Qt.rgba(root.primary.r, root.primary.g, root.primary.b, 0.55)
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root.dowText
            color: root.tertiary
            font.family: "FiraCode Nerd Font"
            font.pixelSize: root.height * 0.018
            font.letterSpacing: root.height * 0.004
        }
        Text {
            text: root.restText
            color: Qt.rgba(root.secondary.r, root.secondary.g, root.secondary.b, 1.0)
            font.family: "FiraCode Nerd Font"
            font.pixelSize: root.height * 0.018
            font.letterSpacing: root.height * 0.004
        }
        Rectangle {
            width: root.width * 0.026
            height: 1
            color: Qt.rgba(root.primary.r, root.primary.g, root.primary.b, 0.55)
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    ExtractedColors {
        id: extracted
        source: root.themeMissing ? root.wallpaperPath : ""
    }

    // ---- one watcher for wallpaper + assets + theme ----
    // Prints a line only when something changes. A short poll keeps the new
    // wallpaper within ~0.3s of the symlink, while idle cost stays at one
    // readlink per tick (the rest is shell builtins).
    Process {
        id: wallProc
        running: true
        command: ["sh", "-c",
            "p=\"$HOME/.config/theme/current/background\"; " +
            "[ -e \"$p\" ] || p=\"$HOME/.config/omarchy/current/background\"; " +
            "last=\"\"; " +
            "while :; do " +
            "  cur=$(readlink -f \"$p\" 2>/dev/null); " +
            "  name=${cur##*/}; name=${name%.*}; " +
            "  cut=0; [ -n \"$name\" ] && [ -f \"$HOME/.cache/wallcut/$name.png\" ] && cut=1; " +
            "  blur=0; [ -n \"$name\" ] && [ -f \"$HOME/.cache/wallcut/$name-blur.jpg\" ] && blur=1; " +
            "  th=0; [ -f \"$HOME/.config/quickshell/colors.css\" ] && th=1; " +
            "  line=\"$cur|$cut|$blur|$th\"; " +
            "  [ \"$line\" != \"$last\" ] && { echo \"$line\"; last=\"$line\"; }; " +
            "  sleep 0.3; " +
            "done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) {
                var f = line.trim().split("|")
                if (f.length < 4) return
                var hadCutout = root.cutoutExists
                root.wallpaperPath = f[0]
                root.cutoutExists = f[1] === "1"
                root.blurExists = f[2] === "1"
                root.themeMissing = f[3] !== "1"
                // a cutout that appeared after startup needs its bbox read now
                if (root.cutoutExists && !hadCutout) {
                    metaView.path = ""
                    metaView.path = root.metaFor(root.wallpaperPath)
                }
            }
        }
    }

    FileView {
        id: metaView
        path: root.metaPath
        printErrors: false
        onLoadFailed: {
            if (metaView.path !== root.metaFor(root.wallpaperPath))
                return
            root.cutBBox = null
            root.cutGrid = null
            root.gridW = 0
            root.gridH = 0
            root.choosePlacement()
        }
        onLoaded: {
            // Drop a late load that belongs to the previous wallpaper.
            if (metaView.path !== root.metaFor(root.wallpaperPath))
                return
            try {
                var o = JSON.parse(text())
                root.cutBBox = (o && o.bbox && o.bbox.length === 4) ? o.bbox : null
                root.cutGrid = (o && o.grid && o.gw > 0 && o.gh > 0) ? o.grid : null
                root.gridW = root.cutGrid ? o.gw : 0
                root.gridH = root.cutGrid ? o.gh : 0
                root.choosePlacement()
            } catch (e) {
                root.cutBBox = null
                root.cutGrid = null
                root.gridW = 0
                root.gridH = 0
                root.choosePlacement()
            }
        }
    }

    FileView {
        id: cfgView
        path: Quickshell.env("HOME") + "/.config/quickshell/desktopclock.json"
        printErrors: false
        onLoaded: {
            try {
                var o = JSON.parse(text())
                if (o && typeof o.layout === "string") root.cfgLayout = o.layout
                if (o && o.overrides) root.cfgOverrides = o.overrides
            } catch (e) {}
        }
    }

    onWallpaperPathChanged: {
        cutBBox = null
        cutGrid = null
        gridW = 0
        gridH = 0
        // Keep the current shift/tilt until the new sidecar lands: resetting
        // here made the clock flash through the centre on every switch.
        metaView.path = ""
        metaView.path = metaFor(wallpaperPath)
    }

    IpcHandler {
        target: "desktopclock"
        // Asset flags refresh on their own within 2s; reload only forces the
        // bbox sidecar and layout config to be re-read immediately.
        function reload(): void {
            metaView.path = ""
            metaView.path = root.metaFor(root.wallpaperPath)
            cfgView.path = ""
            cfgView.path = Quickshell.env("HOME") + "/.config/quickshell/desktopclock.json"
        }
        function toggleCutout(): void { root.forceHideCutout = !root.forceHideCutout }
        function toggle(): void { root.showClock = !root.showClock }
        function show(on: bool): void { root.showClock = on }
        function layout(mode: string): void { root.cfgLayout = mode }
        // diagnostic: what the layer actually thinks it has
        function state(): string {
            return JSON.stringify({
                path: root.wallpaperPath,
                name: root.wallName,
                meta: metaView.path,
                wallSettled: wall.settled,
                wallFading: wall.fading,
                wallCurrent: wall.currentPath,
                wallPending: wall.pendingPath,
                wallA: [wall.opacityA, wall.statusA],
                wallB: [wall.opacityB, wall.statusB],
                cutoutExists: root.cutoutExists,
                blurExists: root.blurExists,
                showClock: root.showClock,
                showCutout: root.showCutout,
                ratio: root.overlapRatio(),
                coverage: root.cutCoverage,
                peak: root.zonePeak(clock2.glyphRect, root.layout === "stack"),
                zoneHH: root.layout === "stack"
                    ? root.coverageFraction(clock2.glyphRect, 0, 0, 1, 0.5)
                    : root.coverageFraction(clock2.glyphRect, 0, 0, 0.437, 1),
                zoneMM: root.layout === "stack"
                    ? root.coverageFraction(clock2.glyphRect, 0, 0.5, 1, 1)
                    : root.coverageFraction(clock2.glyphRect, 0.563, 0, 1, 1),
                bbox: root.cutBBox,
                layout: root.layout,
                shiftX: root.shiftX,
                shiftY: root.shiftY,
                tilt: root.clockTilt,
                tiltPivot: [root.tiltPivotX, root.tiltPivotY],
                autoLayout: root.autoLayout,
                rowSize: [clock2.rowTextSize.width, clock2.rowTextSize.height],
                stackSize: [clock2.stackTextSize.width, clock2.stackTextSize.height],
                glyph: {
                    x: clock2.glyphRect.x,
                    y: clock2.glyphRect.y,
                    w: clock2.glyphRect.width,
                    h: clock2.glyphRect.height
                },
                subjectSource: subject.source,
                subjectStatus: subject.imageStatus,
                subject: {
                    gate: subject.gate,
                    want: subject.wantReveal,
                    opacity: subject.cardOpacity,
                    ready: subject.cardReady,
                    cardUrl: subject.cardUrl,
                    wantUrl: subject.wantUrl
                }
            })
        }
    }
}
