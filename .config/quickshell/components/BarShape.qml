import QtQuick
import QtQuick.Shapes

// Static bar shape: two tall "ears" joined by a thin bottom strip,
// with a rounded cavity between them. Open at the top between the ears.
// Radii are real circles (not stretched): everything scales with height.
Item {
    id: root

    property color colorA: "#dd2238"
    property color colorB: "#c2203d"
    property color colorC: "#a21f48"
    property color colorD: "#991d47"

    // 1 unit = height / 318 (the reference proportions). Override to resize the curves.
    property real u: height / 318

    // Handy for placing content: put widgets in the cavity between earWidth and width - earWidth.
    readonly property real earWidth: 190 * u
    readonly property real earTop: 38 * u

    readonly property string shapePath: {
        const W = width, H = height
        const t = earTop, rT = 70 * u, rB = 50 * u, rS = 60 * u, rC = 80 * u
        const L = earWidth, cb = H - 28 * u
        return "M " + rT + " " + t
            + " H " + (L - rS)
            + " A " + rS + " " + rS + " 0 0 1 " + L + " " + (t + rS)
            + " V " + (cb - rC)
            + " A " + rC + " " + rC + " 0 0 0 " + (L + rC) + " " + cb
            + " H " + (W - L - rC)
            + " A " + rC + " " + rC + " 0 0 0 " + (W - L) + " " + (cb - rC)
            + " V " + (t + rS)
            + " A " + rS + " " + rS + " 0 0 1 " + (W - L + rS) + " " + t
            + " H " + (W - rT)
            + " A " + rT + " " + rT + " 0 0 1 " + W + " " + (t + rT)
            + " V " + (H - rB)
            + " A " + rB + " " + rB + " 0 0 1 " + (W - rB) + " " + H
            + " H " + rB
            + " A " + rB + " " + rB + " 0 0 1 0 " + (H - rB)
            + " V " + (t + rT)
            + " A " + rT + " " + rT + " 0 0 1 " + rT + " " + t
            + " Z"
    }

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4          // smooth edges

        ShapePath {
            strokeWidth: -1       // fill only, no outline
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: 0
                GradientStop { position: 0.00; color: root.colorA }
                GradientStop { position: 0.45; color: root.colorB }
                GradientStop { position: 0.72; color: root.colorC }
                GradientStop { position: 1.00; color: root.colorD }
            }
            PathSvg { path: root.shapePath }
        }
    }
}
