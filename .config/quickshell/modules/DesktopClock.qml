import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import "desktopclock"

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
    readonly property string wallName: {
        var p = wallpaperPath
        if (!p) return ""
        var slash = p.lastIndexOf("/")
        var base = slash >= 0 ? p.substring(slash + 1) : p
        var dot = base.lastIndexOf(".")
        return dot > 0 ? base.substring(0, dot) : base
    }

    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/wallcut"
    readonly property string cutoutPath: cacheDir + "/" + wallName + ".png"
    readonly property string metaPath: cacheDir + "/" + wallName + ".json"
    readonly property string blurPath: cacheDir + "/" + wallName + "-blur.jpg"

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

    // ---- palette: live Matugen theme, wallpaper fallback if the file is gone ----
    property bool themeMissing: false
    readonly property color primary: themeMissing ? extracted.primary : colors.primary
    readonly property color secondary: themeMissing ? extracted.secondary : colors.secondary
    readonly property color tertiary: themeMissing ? extracted.primary : colors.tertiary
    readonly property color foreground: colors.foreground
    readonly property color background: colors.background
    readonly property color outline: colors.outline

    // ---- layout: row by default, stack per wallpaper or globally ----
    property string cfgLayout: "row"
    property var cfgOverrides: ({})
    readonly property string layout: cfgOverrides[wallName] !== undefined ? cfgOverrides[wallName] : cfgLayout

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

    // ---- placement: move the clock to the emptiest band, not blindly to center ----
    property real shiftX: 0      // normalized, 0 = centered
    property real shiftY: 0

    // Scan the whole screen, not just the top-right. The score is the cutout's
    // true alpha coverage of the actual glyph box plus a small pull toward the
    // center, so the clock only moves when that buys a real improvement.
    function choosePlacement() {
        if (!cutGrid || gridW <= 0) {
            shiftX = 0
            shiftY = 0
            return
        }

        var gw = clock2.glyphRect.width
        var gh = clock2.glyphRect.height
        if (gw <= 0 || gh <= 0) return

        var cx = (width - gw) / 2
        var cy = (height - gh) / 2
        var mx = Math.max(16, width * 0.02)
        var top = Math.max(64, height * 0.06)          // clear the bar
        var bottom = height * 0.085                    // leave the date line alone

        var minSX = (mx - cx) / width
        var maxSX = (width - mx - gw - cx) / width
        var minSY = (top - cy) / height
        var maxSY = (height - bottom - gh - cy) / height
        if (minSX > maxSX) { minSX = 0; maxSX = 0 }
        if (minSY > maxSY) { minSY = 0; maxSY = 0 }

        var centerCov = coverageOf(Qt.rect(cx, cy, gw, gh))
        // A few pixels of fur over a digit is fine; do not move for that.
        if (centerCov <= 0.08) {
            shiftX = 0
            shiftY = 0
            return
        }

        var xs = [-0.30, -0.20, -0.10, 0, 0.10, 0.20, 0.30]
        var ys = [-0.24, -0.16, -0.08, 0, 0.08, 0.16, 0.24]
        var bestX = 0, bestY = 0, bestScore = centerCov

        for (var iy = 0; iy < ys.length; iy++) {
            for (var ix = 0; ix < xs.length; ix++) {
                var sx = Math.max(minSX, Math.min(maxSX, xs[ix]))
                var sy = Math.max(minSY, Math.min(maxSY, ys[iy]))
                var cov = coverageOf(Qt.rect(cx + sx * width, cy + sy * height, gw, gh))
                // center pull + slight preference for the top half
                var score = cov + 0.09 * (Math.abs(sx) + Math.abs(sy))
                    + (sy > 0.08 ? 0.02 : 0)
                if (score < bestScore) {
                    bestScore = score
                    bestX = sx
                    bestY = sy
                }
            }
        }

        // Only move if the winning spot clears at least 4 points of coverage.
        if (bestScore >= centerCov - 0.04) {
            shiftX = 0
            shiftY = 0
        } else {
            shiftX = bestX
            shiftY = bestY
        }
    }

    onLayoutChanged: Qt.callLater(choosePlacement)
    onWidthChanged: Qt.callLater(choosePlacement)
    onHeightChanged: Qt.callLater(choosePlacement)

    Wallpaper {
        id: wall
        anchors.fill: parent
        path: root.wallpaperPath
    }

    ClockFace {
        id: clock2
        anchors.fill: parent
        visible: root.showClock
        hh: root.hh
        mm: root.mm
        layout: root.layout
        shiftX: root.shiftX
        shiftY: root.shiftY
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
        visible: root.showClock
        source: root.showCutout ? root.cutoutPath : ""
    }

    // Date — above the subject, so a cutout reaching the bottom edge cannot
    // hide it. Pinned to the bottom edge, out of the clock's way.
    Row {
        id: dateRow
        visible: root.showClock
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
    // Prints a line only when something changes, so idle cost is one
    // readlink + three stats every two seconds. Asset flags live here so a
    // cutout generated while the shell runs appears within two seconds.
    Process {
        id: wallProc
        running: true
        command: ["sh", "-c",
            "p=\"$HOME/.config/theme/current/background\"; " +
            "[ -e \"$p\" ] || p=\"$HOME/.config/omarchy/current/background\"; " +
            "last=\"\"; " +
            "while :; do " +
            "  cur=$(readlink -f \"$p\" 2>/dev/null); " +
            "  name=$(basename \"${cur%.*}\" 2>/dev/null); " +
            "  cut=0; [ -n \"$name\" ] && [ -f \"$HOME/.cache/wallcut/$name.png\" ] && cut=1; " +
            "  blur=0; [ -n \"$name\" ] && [ -f \"$HOME/.cache/wallcut/$name-blur.jpg\" ] && blur=1; " +
            "  th=0; [ -f \"$HOME/.config/quickshell/colors.css\" ] && th=1; " +
            "  line=\"$cur|$cut|$blur|$th\"; " +
            "  if [ \"$line\" != \"$last\" ]; then echo \"$line\"; last=\"$line\"; fi; " +
            "  sleep 2; " +
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
                    metaView.path = root.metaPath
                }
            }
        }
    }

    FileView {
        id: metaView
        path: root.metaPath
        printErrors: false
        onLoaded: {
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
        shiftX = 0
        shiftY = 0
        metaView.path = ""
        metaView.path = metaPath
    }

    IpcHandler {
        target: "desktopclock"
        // Asset flags refresh on their own within 2s; reload only forces the
        // bbox sidecar and layout config to be re-read immediately.
        function reload(): void {
            metaView.path = ""
            metaView.path = root.metaPath
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
                cutoutExists: root.cutoutExists,
                blurExists: root.blurExists,
                showClock: root.showClock,
                showCutout: root.showCutout,
                ratio: root.overlapRatio(),
                coverage: root.cutCoverage,
                bbox: root.cutBBox,
                layout: root.layout,
                shiftX: root.shiftX,
                shiftY: root.shiftY,
                subjectSource: subject.source,
                subjectStatus: subject.imageStatus
            })
        }
    }
}
