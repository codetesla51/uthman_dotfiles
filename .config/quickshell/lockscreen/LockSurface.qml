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

    signal submitted(string password)
    signal unlockAnimationFinished()

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
        scale: root.fitScale * root.zoom

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

    // Lock in: the plate rises, settles from a slight zoom with one soft
    // overshoot, fades up, and the scrim darkens the desktop behind it.
    ParallelAnimation {
        id: introAnim
        NumberAnimation {
            target: box
            property: "opacity"
            from: 0
            to: 1
            duration: root.theme ? root.theme.lockInMs * 0.55 : 340
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.33, 0, 0.2, 1]
        }
        NumberAnimation {
            target: fit
            property: "lift"
            from: root.theme ? root.theme.introShift : 28
            to: 0
            duration: root.theme ? root.theme.lockInMs : 620
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.16, 1, 0.3, 1]
        }
        NumberAnimation {
            target: fit
            property: "zoom"
            from: root.theme ? root.theme.lockInScale : 0.94
            to: 1
            duration: root.theme ? root.theme.lockInMs : 620
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.16, 1.22, 0.32, 1]
        }
        NumberAnimation {
            target: backdrop
            property: "dim"
            from: 0
            to: root.theme ? root.theme.backdropDim : 0.26
            duration: root.theme ? root.theme.lockInMs * 0.85 : 520
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.33, 0, 0.2, 1]
        }
    }

    // Unlock: the scrim lifts first, then the plate drifts up, shrinks a
    // touch and fades away on a matching ease.
    ParallelAnimation {
        id: outAnim
        NumberAnimation {
            target: box
            property: "opacity"
            from: box.opacity
            to: 0
            duration: root.theme ? root.theme.lockOutMs * 0.78 : 330
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.4, 0, 1, 1]
        }
        NumberAnimation {
            target: fit
            property: "lift"
            from: fit.lift
            to: root.theme ? -root.theme.outroShift : -22
            duration: root.theme ? root.theme.lockOutMs : 420
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.45, 0, 0.55, 1]
        }
        NumberAnimation {
            target: fit
            property: "zoom"
            from: fit.zoom
            to: root.theme ? root.theme.lockOutScale : 0.97
            duration: root.theme ? root.theme.lockOutMs : 420
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.45, 0, 0.55, 1]
        }
        NumberAnimation {
            target: backdrop
            property: "dim"
            from: backdrop.dim
            to: 0
            duration: root.theme ? root.theme.lockOutMs : 420
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.4, 0, 1, 1]
        }
        onFinished: root.unlockAnimationFinished()
    }
}