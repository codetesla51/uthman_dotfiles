import QtQuick

// LockSurface — one full-output lock composition. The wallpaper stays put;
// the plate fades and lifts in on lock, then fades and lifts out on unlock.
// The unlock signal fires only when the out animation has actually finished;
// LockScreen keeps its own timeout as the hard ceiling.
Item {
    id: root

    property var theme
    property var config
    property string authState: "idle"
    property int authAttempts: 0
    property string authMessage: ""
    property var notifications: []
    property int autoUnlockIn: -1
    property bool unlocking: false
    // Intro bookkeeping: ready() waits for both the plate and its content,
    // so the dead-man switch is only satisfied by a fully built screen.
    property bool introDone: false
    property bool boxIntroDone: false

    function tryReady() {
        if (!root.introDone || !root.boxIntroDone) return
        if (!isNaN(fit.scale) && fit.scale > 0.1 && box.opacity > 0.9)
            root.ready()
    }

    signal submitted(string password)
    signal unlockAnimationFinished()
    // Emitted once the plate has actually faded in and has a sane transform.
    // LockScreen uses it as a dead-man switch for blank lock surfaces.
    signal ready()

    Backdrop {
        id: backdrop
        anchors.fill: parent
        theme: root.theme
        config: root.config
        glassRect: Qt.rect(
            fit.x + fit.width * (1 - fit.scale) / 2,
            fit.y + fit.height * (1 - fit.scale) / 2,
            fit.width * fit.scale,
            fit.height * fit.scale)
        glassRadius: (root.theme ? root.theme.boxRadius : 18) * fit.scale
        glassOpacity: box.opacity
    }

    Item {
        id: fit
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: fit.lift
        width: root.theme ? root.theme.boxWidth : 1120
        height: root.theme ? root.theme.boxHeight : 740
        readonly property real fitScale: Math.max(0.5, Math.min(1,
            (root.width - 64) / width,
            (root.height - 64) / height))
        // Extra zoom the intro and outro animate on top of the fit scale.
        property real zoom: 1
        // Vertical travel for the intro and outro. Starts at zero because
        // the plate is invisible until the intro sets the opening offset.
        property real lift: 0
        scale: fit.fitScale * fit.zoom

        LockBox {
            id: box
            anchors.fill: parent
            theme: root.theme
            config: root.config
            authState: root.authState
            authAttempts: root.authAttempts
            authMessage: root.authMessage
            notifications: root.notifications
            autoUnlockIn: root.autoUnlockIn
            opacity: 0
            onSubmitted: function (pw) { root.submitted(pw) }
            onIntroFinished: {
                root.boxIntroDone = true
                root.tryReady()
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        visible: root.autoUnlockIn > 0
        text: "auto-unlock in " + root.autoUnlockIn + "s"
        color: root.theme ? root.theme.quiet : "#565656"
        font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
        font.pixelSize: root.theme ? root.theme.tinySize : 9
        font.letterSpacing: 0.4
    }

    onUnlockingChanged: {
        if (root.unlocking) {
            introAnim.stop()
            outAnim.start()
        }
    }

    Component.onCompleted: {
        introAnim.start()
        focusTimer.start()
    }

    Timer {
        id: focusTimer
        interval: root.theme ? root.theme.refocusDelayMs + 180 : 260
        repeat: false
        onTriggered: box.focusPassword()
    }

    // Lock in: the wallpaper pushes in slowly, the scrim sinks, and the
    // plate rises through it from 0.90 with one soft overshoot. The content
    // then assembles on its own cascade inside the plate.
    ParallelAnimation {
        id: introAnim
        NumberAnimation {
            target: box
            property: "opacity"
            from: 0
            to: 1
            duration: root.theme ? root.theme.lockInMs * 0.50 : 360
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.33, 0, 0.2, 1]
        }
        NumberAnimation {
            target: fit
            property: "lift"
            from: root.theme ? root.theme.introShift : 44
            to: 0
            duration: root.theme ? root.theme.lockInMs : 720
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.16, 1, 0.3, 1]
        }
        NumberAnimation {
            target: fit
            property: "zoom"
            from: root.theme ? root.theme.lockInScale : 0.90
            to: 1
            duration: root.theme ? root.theme.lockInMs : 720
            easing.type: Easing.Bezier
            // P2 above 1 gives a small, deliberate settle at the end.
            easing.bezierCurve: [0.18, 1.24, 0.30, 1]
        }
        NumberAnimation {
            target: backdrop
            property: "dim"
            from: 0
            to: root.theme ? root.theme.backdropDim : 0.26
            duration: root.theme ? root.theme.lockInMs * 0.9 : 650
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.33, 0, 0.2, 1]
        }
        NumberAnimation {
            target: backdrop
            property: "zoom"
            from: 1
            to: root.theme ? root.theme.backdropZoom : 1.035
            duration: root.theme ? root.theme.lockRevealMs + 200 : 1350
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.22, 0.61, 0.36, 1]
        }
        onFinished: {
            root.introDone = true
            root.tryReady()
        }
    }

    // Unlock: the input lets go first, then the plate accelerates upward
    // and toward the viewer while the scrim lifts and the wallpaper settles
    // back to its true scale, so the last frame matches the real desktop.
    ParallelAnimation {
        id: outAnim
        SequentialAnimation {
            PauseAnimation { duration: root.theme ? root.theme.lockOutMs * 0.12 : 60 }
            NumberAnimation {
                target: box
                property: "opacity"
                from: box.opacity
                to: 0
                duration: root.theme ? root.theme.lockOutMs * 0.68 : 320
                easing.type: Easing.Bezier
                easing.bezierCurve: [0.4, 0, 1, 1]
            }
        }
        NumberAnimation {
            target: fit
            property: "lift"
            from: fit.lift
            to: root.theme ? -root.theme.outroShift : -44
            duration: root.theme ? root.theme.lockOutMs : 480
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.32, 0, 0.67, 0]
        }
        NumberAnimation {
            target: fit
            property: "zoom"
            from: fit.zoom
            to: root.theme ? root.theme.lockOutScale : 1.022
            duration: root.theme ? root.theme.lockOutMs : 480
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.32, 0, 0.67, 0]
        }
        NumberAnimation {
            target: backdrop
            property: "dim"
            from: backdrop.dim
            to: 0
            duration: root.theme ? root.theme.lockOutMs : 480
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.2, 0, 0.5, 1]
        }
        NumberAnimation {
            target: backdrop
            property: "zoom"
            from: backdrop.zoom
            to: 1
            duration: root.theme ? root.theme.lockOutMs : 480
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.3, 0, 0.5, 1]
        }
        onFinished: root.unlockAnimationFinished()
    }
}