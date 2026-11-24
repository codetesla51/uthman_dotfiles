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
    function metaFor(p) { return cacheDir + "/" + nameFor(p) + ".json" }

    property bool cutoutExists: false
    property bool blurExists: false
    // Single source of truth for the frost image. Keeping the path and the
    // existence check in one property avoids a frame where blurSource points
    // at the new wallpaper's not-yet-written file while blurExists is still
    // true from the old one.
    property string blurFile: ""
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
    property string cfgLayout: "auto"       // auto | center | row | stack
    property var cfgOverrides: ({})
    property string autoLayout: "row"
    readonly property string layout: {
        var ov = overrideFor(wallName)
        var mode = ov ? (ov.layout || "auto") : cfgLayout
        if (mode === "auto") return autoLayout
        return mode === "center" ? "row" : mode
    }

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

    // summed-area table of the sidecar alpha grid: coverage of any candidate
    // box is then four array reads instead of a full grid walk. Searching a
    // fine grid of positions is only affordable because of this.
    property var sat: null
    function rebuildSat() {
        var g = cutGrid
        if (!g || gridW <= 0 || gridH <= 0) { sat = null; return }
        var stride = gridW + 1
        var s = []
        for (var x = 0; x <= gridW; x++) s[x] = 0
        for (var y = 0; y <= gridH; y++) s[y * stride] = 0
        for (var gy = 1; gy <= gridH; gy++) {
            for (var gx = 1; gx <= gridW; gx++) {
                s[gy * stride + gx] = g[(gy - 1) * gridW + (gx - 1)]
                    + s[(gy - 1) * stride + gx] + s[gy * stride + gx - 1]
                    - s[(gy - 1) * stride + gx - 1]
            }
        }
        sat = s
    }

    // true opaque coverage of the clock box, from the sidecar's alpha grid.
    // Returns -1 when the sidecar has no grid (old file). Cell rounding keeps
    // this cheap; the grid cells are ~60px, well below a glyph's stroke width.
    function coverageOf(r) {
        if (!sat) return -1
        var cw = width / gridW, ch = height / gridH
        var x0 = Math.max(0, Math.min(gridW, Math.round(r.x / cw)))
        var x1 = Math.max(0, Math.min(gridW, Math.round((r.x + r.width) / cw)))
        var y0 = Math.max(0, Math.min(gridH, Math.round(r.y / ch)))
        var y1 = Math.max(0, Math.min(gridH, Math.round((r.y + r.height) / ch)))
        if (x1 <= x0 || y1 <= y0) return 0
        var stride = gridW + 1
        var total = sat[y1 * stride + x1] - sat[y0 * stride + x1]
            - sat[y1 * stride + x0] + sat[y0 * stride + x0]
        return total / ((x1 - x0) * (y1 - y0))
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

    // Modal manual placement. Nothing moves unless the user enters move mode;
    // Enter commits the spot as a manual pin, Esc puts the auto placement back.
    property bool moveMode: false
    property real manualX: 0
    property real manualY: 0
    property real moveStartX: 0
    property real moveStartY: 0
    property string manualPinnedFor: ""
    property real manualTilt: 0
    property real moveStartTilt: 0
    property bool showDigits: true

    function shiftLimits(gw, gh) {
        var cx = (width - gw) / 2
        var cy = (height - gh) / 2
        var mx = Math.max(16, width * 0.008)
        var top = Math.max(64, height * 0.06)
        var bottom = height * 0.055
        var minX = (mx - cx) / width, maxX = (width - mx - gw - cx) / width
        var minY = (top - cy) / height, maxY = (height - bottom - gh - cy) / height
        if (minX > maxX) { minX = 0; maxX = 0 }
        if (minY > maxY) { minY = 0; maxY = 0 }
        return { minX: minX, maxX: maxX, minY: minY, maxY: maxY }
    }

    function startMove() {
        if (moveMode) return
        showClock = true
        moveStartX = shiftX
        moveStartY = shiftY
        moveStartTilt = clockTilt
        manualTilt = clockTilt
        manualX = shiftX
        manualY = shiftY
        moveMode = true
    }

    function nudgeClock(dx, dy) {
        if (!moveMode) return
        manualX += dx / width
        manualY += dy / height
        var gw = autoLayout === "stack" ? clock2.stackTextSize.width : clock2.rowTextSize.width
        var gh = autoLayout === "stack" ? clock2.stackTextSize.height : clock2.rowTextSize.height
        var lim = shiftLimits(gw, gh)
        manualX = Math.max(lim.minX, Math.min(lim.maxX, manualX))
        manualY = Math.max(lim.minY, Math.min(lim.maxY, manualY))
        setBox(gw, gh, manualX, manualY)
        clockTilt = manualTilt
    }

    // Rotate by small steps while moving; the lean is separate from the auto
    // tilt so nudging never snaps a chosen angle back.
    function rotateClock(deg) {
        if (!moveMode) return
        manualTilt = Math.max(-18, Math.min(18, manualTilt + deg))
        clockTilt = manualTilt
    }

    function endMove(save) {
        if (!moveMode) return
        moveMode = false
        if (save) {
            manualPinnedFor = wallName
            savePlacement(autoLayout, manualX, manualY, manualTilt)
        } else {
            manualX = moveStartX
            manualY = moveStartY
            choosePlacement()
            clockTilt = moveStartTilt
        }
    }

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

    // Peak alpha over the two readable zones, including each digit's half.
    // Row: HH | colon | MM. Stack: HH above, MM below. A subject crossing one
    // digit only is caught here even when the whole pair looks mostly clear.
    function zonePeak(r, stacked) {
        if (stacked)
            return Math.max(coverageFraction(r, 0, 0, 1, 0.5),
                            coverageFraction(r, 0, 0.5, 1, 1))
        var hh = Math.max(coverageFraction(r, 0, 0, 0.437, 1),
                          coverageFraction(r, 0, 0, 0.2185, 0.5),
                          coverageFraction(r, 0, 0.5, 0.2185, 1))
        var mm = Math.max(coverageFraction(r, 0.563, 0, 1, 1),
                          coverageFraction(r, 0.563, 0, 0.7815, 0.5),
                          coverageFraction(r, 0.563, 0.5, 0.7815, 1))
        return Math.max(hh, mm)
    }

    // Score every legal position for one layout. A position with a digit pair
    // more than ~12% covered is effectively unreadable, so that penalty comes
    // first; then aim for a little overlap (~9% of the box) so the subject
    // still crosses the type, then prefer the smallest move.
    function bestSpot(gw, gh, stacked) {
        var cx = (width - gw) / 2
        var cy = (height - gh) / 2
        var lim = shiftLimits(gw, gh)
        var minSX = lim.minX, maxSX = lim.maxX
        var minSY = lim.minY, maxSY = lim.maxY

        var centerRect = Qt.rect(cx, cy, gw, gh)
        var centerCov = coverageOf(centerRect)
        var centerPeak = zonePeak(centerRect, stacked)
        // Nothing meaningful on the digits: stay exactly centered.
        if (centerCov <= 0.05 && centerPeak <= 0.12)
            return { x: 0, y: 0, cov: centerCov, peak: centerPeak, score: centerCov }

        var best = null
        for (var sy = minSY; sy <= maxSY + 0.0001; sy += 0.02) {
            for (var sx = minSX; sx <= maxSX + 0.0001; sx += 0.02) {
                var r = Qt.rect(cx + sx * width, cy + sy * height, gw, gh)
                var cov = coverageOf(r)
                var peak = zonePeak(r, stacked)
                var score = 100 * Math.max(0, peak - 0.12)
                    + Math.abs(cov - 0.09) * 2.0
                    + 0.01 * (Math.abs(sx) + Math.abs(sy))
                if (best === null || score < best.score)
                    best = { x: sx, y: sy, cov: cov, peak: peak, score: score }
            }
        }
        // Zero can fall between the 0.02 steps; always give it a chance.
        var zr = Qt.rect(cx, cy, gw, gh)
        var zc = coverageOf(zr), zp = zonePeak(zr, stacked)
        var zs = 100 * Math.max(0, zp - 0.12) + Math.abs(zc - 0.09) * 2.0
        if (best === null || zs < best.score)
            best = { x: 0, y: 0, cov: zc, peak: zp, score: zs }
        return best
    }

    // Overrides accept either a bare mode ("center", "row", "stack") or a
    // pinned object ({ layout, x, y }). A pin is written the first time auto
    // has to move the clock off centre, so a wallpaper keeps the placement it
    // was composed with instead of drifting between loads.
    function overrideFor(name) {
        var o = cfgOverrides ? cfgOverrides[name] : undefined
        if (o === undefined || o === null) return null
        if (typeof o === "string") return { layout: o }
        if (typeof o === "object") return o
        return null
    }

    function setBox(gw, gh, sx, sy) {
        shiftX = sx
        shiftY = sy
        var box = Qt.rect((width - gw) / 2 + sx * width,
                          (height - gh) / 2 + sy * height, gw, gh)
        var contact = cutoutExists && showCutout ? contactCentroid(box) : null
        // Only a shifted clock leans. A centred one stays level: a tilt there
        // reads as a mistake, not as the type resting against her.
        if (contact && coverageOf(box) >= 0.04 && Math.abs(sx) > 0.02) {
            // Lean only when the subject actually crosses the digits, pivoting
            // on the contact mass so the type reads as resting against her.
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

    // Write the resolved placement into desktopclock.json so this wallpaper
    // never re-decides. Centre placements are deterministic and stay out of
    // the file; only a real shift is worth remembering.
    property string pinnedFor: ""
    function savePlacement(layout, sx, sy, tilt) {
        if (wallName === "") return
        var o = {}
        for (var k in cfgOverrides) o[k] = cfgOverrides[k]
        var entry = { layout: layout, x: Math.round(sx * 1000) / 1000,
                      y: Math.round(sy * 1000) / 1000 }
        if (tilt !== undefined && Math.abs(tilt) > 0.01)
            entry.tilt = Math.round(tilt * 10) / 10
        o[wallName] = entry
        pinnedFor = wallName
        cfgOverrides = o
        writeCfg(o)
    }
    function pinPlacement(gw, gh, sx, sy) {
        if (pinnedFor === wallName || wallName === "") return
        if (Math.abs(sx) < 0.001 && Math.abs(sy) < 0.001) return
        if (overrideFor(wallName) !== null) return
        savePlacement(autoLayout, sx, sy)
    }

    function writeCfg(overrides) {
        var payload = { layout: cfgLayout, overrides: overrides }
        var b64 = Qt.btoa(JSON.stringify(payload))
        cfgProc.command = ["sh", "-c",
            "mkdir -p '" + Quickshell.env("HOME") + "/.config/quickshell' && " +
            "echo '" + b64 + "' | base64 -d > '" +
            Quickshell.env("HOME") + "/.config/quickshell/desktopclock.json'"]
        cfgProc.running = true
    }

    // Switching mode always clears the pin for this wallpaper: a stored
    // placement would otherwise outvote the mode the user just asked for.
    function setMode(mode) {
        cfgLayout = (mode === "" || mode === "auto") ? "auto" : mode
        if (overrideFor(wallName) !== null) {
            var o = {}
            for (var k in cfgOverrides)
                if (k !== wallName) o[k] = cfgOverrides[k]
            cfgOverrides = o
            writeCfg(o)
        }
        pinnedFor = ""
        manualPinnedFor = ""
        Qt.callLater(choosePlacement)
    }
    function unpin() { setMode("auto") }

    function choosePlacement() {
        if (!cutGrid || gridW <= 0 || !sat) {
            autoLayout = "row"
            shiftX = 0
            shiftY = 0
            clockTilt = 0
            return
        }

        var rowW = clock2.rowTextSize.width, rowH = clock2.rowTextSize.height
        var stackW = clock2.stackTextSize.width, stackH = clock2.stackTextSize.height
        if (rowW <= 0 || rowH <= 0 || stackW <= 0 || stackH <= 0) return

        // While the user is nudging the clock, no auto rule or pin gets a vote.
        if (moveMode) {
            var mgw = autoLayout === "stack" ? stackW : rowW
            var mgh = autoLayout === "stack" ? stackH : rowH
            setBox(mgw, mgh, manualX, manualY)
            return
        }

        var ov = overrideFor(wallName)
        var mode = ov ? (ov.layout || "auto") : cfgLayout
        var replacePin = false

        // A pin is trusted only while it still keeps both digit pairs
        // readable. Pins written by the old, coarse search buried minutes on
        // several wallpapers and then outvoted every later improvement.
        if (ov && (ov.x !== undefined || ov.y !== undefined)) {
            var pl = ov.layout === "stack" ? "stack" : "row"
            var pgw = pl === "stack" ? stackW : rowW
            var pgh = pl === "stack" ? stackH : rowH
            var psx = Number(ov.x) || 0, psy = Number(ov.y) || 0
            var pr = Qt.rect((width - pgw) / 2 + psx * width,
                             (height - pgh) / 2 + psy * height, pgw, pgh)
            // A pin the user placed by hand is never second-guessed.
            if (manualPinnedFor === wallName || zonePeak(pr, pl === "stack") <= 0.18) {
                autoLayout = pl
                setBox(pgw, pgh, psx, psy)
                if (ov.tilt !== undefined) clockTilt = Number(ov.tilt) || 0
                return
            }
            replacePin = true
        }

        if (mode === "center") {
            autoLayout = "row"
            setBox(rowW, rowH, 0, 0)
            if (replacePin) savePlacement("row", 0, 0)
            return
        }

        if (mode === "stack") {
            var sp = bestSpot(stackW, stackH, true)
            autoLayout = "stack"
            setBox(stackW, stackH, sp.x, sp.y)
            if (replacePin) savePlacement("stack", sp.x, sp.y)
            else if (!ov) pinPlacement(stackW, stackH, sp.x, sp.y)
            return
        }

        var row = bestSpot(rowW, rowH, false)
        if (mode === "row") {
            autoLayout = "row"
            setBox(rowW, rowH, row.x, row.y)
            if (replacePin) savePlacement("row", row.x, row.y)
            else if (!ov) pinPlacement(rowW, rowH, row.x, row.y)
            return
        }

        // Auto: stay wide when the row is readable, otherwise the narrow
        // stack has far more room to dodge a large subject.
        var stack = bestSpot(stackW, stackH, true)
        if (stack.peak + 0.03 < row.peak) {
            autoLayout = "stack"
            setBox(stackW, stackH, stack.x, stack.y)
            if (replacePin) savePlacement("stack", stack.x, stack.y)
            else if (!ov) pinPlacement(stackW, stackH, stack.x, stack.y)
            return
        }
        autoLayout = "row"
        setBox(rowW, rowH, row.x, row.y)
        if (replacePin) savePlacement("row", row.x, row.y)
        else if (!ov) pinPlacement(rowW, rowH, row.x, row.y)
    }

    onLayoutChanged: Qt.callLater(choosePlacement)
    onWidthChanged: Qt.callLater(choosePlacement)
    onHeightChanged: Qt.callLater(choosePlacement)
    // A pin or mode loaded after the sidecar already placed the clock has to
    // win, otherwise the stored position only applies from the next reload.
    onCfgOverridesChanged: Qt.callLater(choosePlacement)
    onCfgLayoutChanged: Qt.callLater(choosePlacement)

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
        visible: root.clockVisible && root.showDigits
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
        blurSource: root.blurFile
        frost: root.blurFile !== ""
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
                root.blurFile = f[2] === "1"
                    ? root.cacheDir + "/" + root.nameFor(f[0]) + "-blur.jpg"
                    : ""
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
            root.sat = null
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
                root.rebuildSat()
                root.choosePlacement()
            } catch (e) {
                root.cutBBox = null
                root.cutGrid = null
                root.gridW = 0
                root.gridH = 0
                root.sat = null
                root.choosePlacement()
            }
        }
    }

    Process { id: cfgProc }

    FileView {
        id: cfgView
        path: Quickshell.env("HOME") + "/.config/quickshell/desktopclock.json"
        printErrors: false
        onLoaded: {
            var o = null
            try { o = JSON.parse(text()) } catch (e) { o = null }
            if (o === null) return
            root.cfgLayout = typeof o.layout === "string" ? o.layout : "auto"
            root.cfgOverrides = (o.overrides && typeof o.overrides === "object") ? o.overrides : ({})
        }
    }

    onWallpaperPathChanged: {
        cutBBox = null
        cutGrid = null
        gridW = 0
        gridH = 0
        sat = null
        pinnedFor = ""
        manualPinnedFor = ""
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
        function collapse(): void { root.showDigits = !root.showDigits }
        function moveStart(): void { root.startMove() }
        function toggleMove(): void { root.moveMode ? root.endMove(true) : root.startMove() }
        function moveEnd(): void { root.endMove(true) }
        function moveCancel(): void { root.endMove(false) }
        function nudge(dx: int, dy: int): void { root.nudgeClock(dx, dy) }
        function rotate(delta: int): void { root.rotateClock(delta) }
        function layout(mode: string): void { root.setMode(mode) }
        function unpin(): void { root.unpin() }
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
                blurStatus: clock2.blurStatus,
                blurUrl: clock2.blurUrl,
                glassOn: clock2.glassOn,
                showClock: root.showClock,
                showDigits: root.showDigits,
                moveMode: root.moveMode,
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
