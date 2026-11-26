import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import "../components/Bloom.js" as Bloom
import "DripKind.js" as Drip

// Drip toast. Fixed 320px capsule so it never grows or shifts; text elides
// instead of wrapping. Empty fields collapse, app name substitutes for a
// missing summary, and images get a thumbnail. Radius is height/2 so it is
// always a perfect capsule.
//
// The item is one stack slot tall (card + gap) so the gap collapses with the
// card on exit. That removes the 26px jump the old Column spacing left behind
// when a finished toast was destroyed.
Item {
    id: root

    required property var notification
    required property var colors
    required property int stackIndex
    required property int railWidth

    signal expired()

    readonly property bool alive: notification !== null
    readonly property bool critical: alive && notification.urgency === NotificationUrgency.Critical
    readonly property var info: Drip.classify(root.alive ? notification : null, root.critical)
    readonly property color kindColor: Drip.color(root.info.kind)
    readonly property string glyph: (root.info.glyph && root.info.glyph !== "")
                                    ? root.info.glyph
                                    : Drip.glyphForApp(root.alive ? notification.appName : "")

    property string state_: "open"

    readonly property string summary: root.alive ? String(notification.summary || "").replace(/<[^>]*>/g, "") : ""
    readonly property string bodyText: root.alive ? String(notification.body || "").replace(/<[^>]*>/g, "") : ""
    readonly property string appText: root.alive ? String(notification.appName || "").replace(/<[^>]*>/g, "") : ""
    readonly property string displayTitle: root.summary !== "" ? root.summary : (root.appText !== "" ? root.appText : "Notification")
    readonly property string displayBody: root.bodyText !== "" ? root.bodyText : (root.summary !== "" ? root.appText : "")
    readonly property bool hasImage: root.alive && notification.image !== undefined && notification.image !== ""

    // Single-line only: text elides instead of wrapping, so height is constant.
    readonly property int targetH: root.hasImage ? 64 : 56
    // Fixed width. Long text elides; the capsule never grows or shifts.
    readonly property int targetW: 320
    // The 10px side margins are headroom for the entrance overshoot.
    readonly property int gap: 26

    // Geometry from DripCore/Island.swift / Card.swift, widened for legibility.
    readonly property int centerX: railWidth / 2
    readonly property int rowStep: root.targetH + root.gap
    property int originY: -(stackIndex * rowStep)

    // DripCore/Card.swift:187 — fixed 4.5s drain, ignoring sender expiry.
    property int durationMs: 4500
    property int leftMs: durationMs
    readonly property real progress: durationMs > 0 ? Math.max(0, leftMs / durationMs) : 1

    width: railWidth          // window is exactly this wide, so the card is centred
    height: targetH + gap

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: originY
        width: targetW                // fixed geometry; scale animates growth
        height: targetH
        scale: 0.08
        radius: height / 2            // always a perfect circle / capsule
        color: "#0a0a0a"
        border.width: 1
        border.color: root.colors.alpha(root.kindColor, 0.22)
        clip: true

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            opacity: 0
            transform: Translate { id: contentLift; y: 6 }

            Image {
                visible: root.hasImage
                Layout.preferredWidth: visible ? 40 : 0
                Layout.preferredHeight: visible ? 40 : 0
                Layout.alignment: Qt.AlignVCenter
                source: root.alive ? notification.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                clip: true
            }

            Text {
                Layout.preferredWidth: 24
                text: root.glyph
                color: root.kindColor
                font.family: "Phosphor"
                font.pixelSize: 20
                Layout.alignment: Qt.AlignVCenter
                transformOrigin: Item.Center

                // Running jobs get a slow turn; everything else stays still.
                RotationAnimator on rotation {
                    running: root.info.kind === "run"
                    from: 0; to: 360; duration: 2400
                    loops: Animation.Infinite
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: root.displayTitle
                    color: root.kindColor
                    font.family: colors.fontSans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: root.displayBody
                    color: "#f5f5f0"
                    opacity: 0.66
                    font.family: colors.fontSans
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: text !== ""
                }
            }

            Canvas {
                id: ring
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                antialiasing: true

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.lineWidth = 2.4
                    ctx.strokeStyle = Qt.rgba(0.96, 0.96, 0.94, 0.28)
                    ctx.beginPath()
                    ctx.arc(10, 10, 8.6, 0, 2 * Math.PI)
                    ctx.stroke()
                    ctx.strokeStyle = root.kindColor
                    ctx.beginPath()
                    ctx.arc(10, 10, 8.6, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * root.progress)
                    ctx.stroke()
                }

                Connections {
                    target: root
                    function onProgressChanged() { ring.requestPaint() }
                }
                Component.onCompleted: ring.requestPaint()
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 5
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dismiss()
        }
    }

    Timer {
        id: countdown
        interval: 80
        running: root.state_ === "open" && !root.critical
        repeat: true
        onTriggered: {
            root.leftMs -= 80
            if (root.leftMs <= 0) root.dismiss()
        }
    }

    // Island.swift: fall Spring(0.62,0.2), grow Spring(0.5,0.15).
    // Long spring for the drop, softer overshoot for the capsule, then the
    // text lifts the last few pixels instead of popping in.
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: card; property: "y"
            from: root.originY; to: 0; duration: 620
            easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring
        }
        NumberAnimation {
            target: card; property: "scale"
            from: 0.08; to: 1; duration: 640
            easing.type: Easing.Bezier; easing.bezierCurve: [0.22, 1.18, 0.36, 1]
        }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            ParallelAnimation {
                NumberAnimation {
                    target: content; property: "opacity"
                    from: 0; to: 1; duration: 260
                    easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out
                }
                NumberAnimation {
                    target: contentLift; property: "y"
                    from: 6; to: 0; duration: 300
                    easing.type: Easing.Bezier; easing.bezierCurve: Bloom.soft
                }
            }
        }
    }

    // Retract in one motion: shrink, fade the text, rise into the island and
    // collapse the slot together. The old version paused between steps.
    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: card; property: "scale"
            to: 0.08; duration: 220
            easing.type: Easing.Bezier; easing.bezierCurve: Bloom.soft
        }
        NumberAnimation {
            target: content; property: "opacity"
            to: 0; duration: 120
            easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out
        }
        NumberAnimation {
            target: contentLift; property: "y"
            to: 4; duration: 160
            easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out
        }
        NumberAnimation {
            target: card; property: "y"
            to: root.originY; duration: 320
            easing.type: Easing.Bezier; easing.bezierCurve: [0.4, 0, 0.2, 1]
        }
        NumberAnimation {
            target: root; property: "height"
            to: 0; duration: 320
            easing.type: Easing.Bezier; easing.bezierCurve: [0.4, 0, 0.2, 1]
        }
        onFinished: {
            root.expired()
            root.destroy()
        }
    }

    function dismiss() {
        if (root.state_ !== "open") return
        root.state_ = "closing"
        if (alive) notification.tracked = false
        countdown.stop()
        exitAnim.start()
    }

    Component.onCompleted: {
        root.leftMs = root.durationMs
        enterAnim.start()
    }
}
