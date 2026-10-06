import QtQuick
import QtQuick.Shapes

// OsdChip — a circular lobe joined by fillets into a rounded tail. The lobe
// carries the icon, the tail carries everything else. `vertical` transposes
// the whole outline so the lobe points up and the tail hangs down.
//
// Geometry is a direct port of the reference SVG (verified by rendering
// both orientations and diffing one against the other's transpose):
//
//   lobeR     circle radius — the icon sits on it
//   filletR   fillet where the circle meets the tail's long edges
//   cornerR   corner radius at the far end of the tail
//   bandTop / bandBottom   tail band, measured out from the circle centre
//   tailLength             straight run of the tail
Item {
    id: chip

    property var colors
    property bool vertical: false

    property real lobeR: 28          // circle radius
    property real filletR: 9         // fillet at the circle/tail joint
    property real cornerR: 14        // tail corner radius
    property real bandTop: 23        // tail band, above circle centre
    property real bandBottom: 23     // tail band, below circle centre
    property real tailLength: 246    // straight run of the tail
    property real tailPad: 14        // padding before the far corners

    readonly property real spanW: lobeR * 2 + 2                 // circle across
    readonly property real spanH: spanW + tailLength            // circle + tail
    readonly property real bodyW: vertical ? spanW : spanH
    readonly property real bodyH: vertical ? spanH : spanW
    readonly property real lobe: lobeR + 1                      // circle centre
    readonly property real band: bandTop + bandBottom           // tail thickness
    readonly property real contentStart: lobeR * 2 + 8          // clear of the lobe
    readonly property real contentLen: (spanH - tailPad) - contentStart

    property color fill: colors ? colors.alpha(colors.surface, 0.78) : "#212323"
    property color stroke: colors ? colors.alpha(colors.primary, 0.35) : "#9bd0d2"

    implicitWidth: bodyW
    implicitHeight: bodyH

    // 0x0 holder parked on the circle centre, so `anchors.centerIn: parent`
    // lands the icon exactly on the lobe.
    Item {
        id: iconHolder
        x: chip.lobe
        y: chip.vertical ? chip.spanH - chip.lobe : chip.lobe
        width: 0; height: 0
    }
    Item {
        id: tailHolder
        x: chip.vertical ? chip.lobe - chip.band / 2 : chip.contentStart
        y: chip.vertical ? chip.tailPad : chip.bodyH / 2 - chip.band / 2
        width:  chip.vertical ? chip.band : chip.contentLen
        height: chip.vertical ? chip.spanH - chip.contentStart - chip.tailPad : chip.band
    }

    property alias iconSlot: iconHolder.data
    property alias tailSlot: tailHolder.data

    function _n(v) { return Math.round(v * 100) / 100 }

    function _segs() {
        var k = lobeR + filletR
        var w = spanW + tailLength
        var cx = lobe, cy = lobe
        var top = cy - bandTop, bot = cy + bandBottom, right = w - 1
        var dt = Math.sqrt(k * k - Math.pow(bandTop + filletR, 2))
        var db = Math.sqrt(k * k - Math.pow(bandBottom + filletR, 2))
        var up = cx + lobeR * dt / k, dn = cx + lobeR * db / k
        var rise = cy - lobeR * (bandTop + filletR) / k
        var fall = cy + lobeR * (bandBottom + filletR) / k
        return [
            { t: "M", p: [up, rise] },
            { t: "A", r: filletR, laf: 0, sf: 0, p: [cx + dt, top] },
            { t: "L", p: [right - cornerR, top] },
            { t: "A", r: cornerR, laf: 0, sf: 1, p: [right, top + cornerR] },
            { t: "L", p: [right, bot - cornerR] },
            { t: "A", r: cornerR, laf: 0, sf: 1, p: [right - cornerR, bot] },
            { t: "L", p: [cx + db, bot] },
            { t: "A", r: filletR, laf: 0, sf: 0, p: [dn, fall] },
            { t: "A", r: lobeR, laf: 1, sf: 1, p: [up, rise] }
        ]
    }

    function _path() {
        var segs = _segs(), out = []
        for (var i = 0; i < segs.length; i++) {
            var g = segs[i]
            // vertical stands the chip on end: a quarter turn maps
            // (x, y) -> (y, spanH - x), putting the lobe at the bottom and
            // the tail up top.  A rotation keeps orientation, so every arc
            // keeps its sweep flag untouched.
            var px = vertical ? g.p[1] : g.p[0]
            var py = vertical ? spanH - g.p[0] : g.p[1]
            var sf = g.sf
            if (g.t === "M") out.push("M" + _n(px) + " " + _n(py))
            else if (g.t === "L") out.push("L" + _n(px) + " " + _n(py))
            else out.push("A" + g.r + " " + g.r + " 0 " + g.laf + " " + sf + " " + _n(px) + " " + _n(py))
        }
        return out.join(" ") + " Z"
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        layer.enabled: true
        layer.samples: 4
        ShapePath {
            fillColor: chip.fill
            strokeColor: chip.stroke
            strokeWidth: 1
            PathSvg { path: chip._path() }
        }
    }
}