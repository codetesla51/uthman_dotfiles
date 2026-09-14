import Quickshell
import QtQuick
import QtQuick.Effects

// WeatherIcon — basmilius/meteocons artwork (static SVG) + QML "life" motion.
// Meteocons' own animations are SMIL, which Qt's SVG renderer ignores, so we
// play the static art and add movement in QML: drift, bob, pulse, rain jitter,
// storm flicker.
// kind: "clear" | "partly" | "cloud" | "rain" | "snow" | "storm" | "fog"
Item {
    id: root

    property string kind: "cloud"
    property bool animate: true
    property color tint: "#9cc8ff"       // blend meticons artwork toward theme
    property real tintStrength: 0.0       // 0 = original meticons colors; 0.25 ≈ subtle

    readonly property string baseDir: Quickshell.env("HOME") + "/.config/quickshell/assets/meteocons/fill/"
    property string iconSource: {
        switch (kind) {
        case "clear":  return baseDir + "clear-day.svg"
        case "partly": return baseDir + "partly-cloudy-day.svg"
        case "rain":   return baseDir + "overcast.svg"
        case "snow":   return baseDir + "overcast.svg"
        case "storm":  return baseDir + "thunderstorms.svg"
        case "fog":    return baseDir + "fog.svg"
        default:       return baseDir + "overcast.svg"
        }
    }

    // everything that moves is nested so per-kind motion can't collide
    // with the shared float (one animation per property target)
    Item {
        id: mover
        anchors.fill: parent

        Image {
            id: art
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            source: root.iconSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
            smooth: true
            sourceSize: Qt.size(512, 512)
            visible: status === Image.Ready
            layer.enabled: root.tintStrength > 0
            layer.effect: MultiEffect {
                saturation: 0.55
                colorization: root.tintStrength
                colorizationColor: root.tint
            }
        }
        // loading placeholder so the tile never flashes empty
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.5; height: parent.width * 0.5; radius: width / 2
            color: Qt.rgba(0.55, 0.8, 1, 0.3)
            opacity: art.status === Image.Ready ? 0 : 1
        }

        // ── snow — slow flake overlay on top of the cloud art ──
        Repeater {
            model: root.kind === "snow" ? 3 : 0
            delegate: Rectangle {
                required property int index
                width: 3.5; height: 3.5; radius: 1.75
                color: "#cfe9ff"
                x: root.width * (0.24 + index * 0.14)
                y: root.height * 0.55
                visible: root.kind === "snow"
                SequentialAnimation on y {
                    running: root.animate; loops: Animation.Infinite
                    PauseAnimation { duration: [0, 600, 1200][index] }
                    NumberAnimation { from: root.height * 0.55; to: root.height * 0.96; duration: [1500, 1700, 1600][index]; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on opacity {
                    running: root.animate; loops: Animation.Infinite
                    PauseAnimation { duration: [0, 600, 1200][index] }
                    NumberAnimation { from: 0; to: 1; duration: 350 }
                    NumberAnimation { from: 1; to: 0; duration: [1150, 1350, 1250][index] }
                }
                SequentialAnimation on x {
                    running: root.animate; loops: Animation.Infinite
                    NumberAnimation { from: x; to: x + 4; duration: 800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: x + 4; to: x; duration: 800; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // shared life: slow float — all kinds
    SequentialAnimation on y {
        running: root.animate
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: -2.5; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { from: -2.5; to: 0;   duration: 1400; easing.type: Easing.InOutSine }
    }

    // drift side to side — partly / cloud / rain / fog
    SequentialAnimation on x {
        running: root.animate && (root.kind === "partly" || root.kind === "cloud" || root.kind === "rain" || root.kind === "fog")
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 2.5; duration: 1900; easing.type: Easing.InOutSine }
        NumberAnimation { from: 2.5; to: -2.5; duration: 3800; easing.type: Easing.InOutSine }
        NumberAnimation { from: -2.5; to: 0; duration: 1900; easing.type: Easing.InOutSine }
    }
    // warm pulse — clear / partly
    SequentialAnimation on scale {
        running: root.animate && (root.kind === "clear" || root.kind === "partly")
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 1.07; duration: 1300; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.07; to: 1; duration: 1300; easing.type: Easing.InOutSine }
    }
    // rain jitter — fast vibration for falling feel
    SequentialAnimation on y {
        running: root.animate && root.kind === "rain"
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: -0.8; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { from: -0.8; to: 0.8; duration: 130; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 0.8; to: 0; duration: 130; easing.type: Easing.InQuad }
    }
    // storm flicker — lightning flash feel over the whole art
    SequentialAnimation on opacity {
        running: root.animate && root.kind === "storm"
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.62; duration: 90 }
        NumberAnimation { from: 0.62; to: 1; duration: 130 }
        PauseAnimation { duration: 900 }
        NumberAnimation { from: 1; to: 0.78; duration: 70 }
        NumberAnimation { from: 0.78; to: 1; duration: 110 }
        PauseAnimation { duration: 2400 }
    }
}