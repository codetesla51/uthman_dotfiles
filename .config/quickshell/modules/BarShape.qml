import QtQuick
import QtQuick.Shapes

// Bar silhouette: two "ears" joined by a thin bottom strip, with a rounded
// cavity between them that is open at the top (the island hangs in it).
// Radii are real circles: everything scales with height.
//
// earL / earR are the widths of the left and right ear. Bind them to the
// content you put inside each ear so the shape hugs it.
Item {
    id: root

    property color colorA: "#dd2238"
    property color colorB: "#c2203d"
    property color colorC: "#a21f48"
    property color colorD: "#991d47"
    // hairline around the whole silhouette; transparent = no edge
    property color edge: "transparent"

    // 1 unit = height / 318 (the reference proportions)
    property real u: height / 318

    property real earL: 190 * u
    property real earR: earL
    // old name, kept so existing placement code keeps working
    readonly property real earWidth: earL
    readonly property real earTop: 38 * u

    // ears resize smoothly when the content inside them changes
    Behavior on earL { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on earR { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    readonly property string shapePath: {
        const W = width, H = height
        const t = earTop, rT = 70 * u, rB = 50 * u, rS = 60 * u, rC = 80 * u
        // an ear can never be narrower than its own corner radius
        const L = Math.max(earL, rS + 4), R = Math.max(earR, rS + 4)
        const cb = H - 28 * u
        return "M " + rT + " " + t
            + " H " + (L - rS)
            + " A " + rS + " " + rS + " 0 0 1 " + L + " " + (t + rS)
            + " V " + (cb - rC)
            + " A " + rC + " " + rC + " 0 0 0 " + (L + rC) + " " + cb
            + " H " + (W - R - rC)
            + " A " + rC + " " + rC + " 0 0 0 " + (W - R) + " " + (cb - rC)
            + " V " + (t + rS)
            + " A " + rS + " " + rS + " 0 0 1 " + (W - R + rS) + " " + t
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
        layer.samples: 4

        ShapePath {
            strokeWidth: root.edge.a > 0 ? 1 : -1
            strokeColor: root.edge
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
