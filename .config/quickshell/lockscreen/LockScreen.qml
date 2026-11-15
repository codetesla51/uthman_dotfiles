import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// LockScreen — the real session lock. Installed into shell.qml only as an
// inert object; nothing locks until IPC calls lock()/lockTimed().
//
// Unlock contract: PAM success (or lockTimed expiry) starts the surface
// animation and starts a hard timer. `locked = false` happens only after the
// animation duration + 200ms, so the fade always completes or times out.
Scope {
    id: root

    property var palette: null
    property var theme: LockTheme { palette: root.palette }
    property var config: LockConfig {}
    property var notifications: []

    property bool locked: false
    property bool unlocking: false
    property int secondsLeft: -1

    property var auth: PamAuth {
        config: root.config
        onSucceeded: root.beginUnlock()
    }

    function lock() {
        if (root.locked) return
        console.log("[lockscreen] lock")
        root.unlocking = false
        root.secondsLeft = -1
        root.auth.reset()
        root.locked = true
    }

    function lockTimed(seconds) {
        if (root.locked) return
        var s = Math.max(1, Math.round(seconds))
        console.log("[lockscreen] lockTimed", s)
        root.lock()
        root.secondsLeft = s
        countdown.start()
    }

    function beginUnlock() {
        if (!root.locked || root.unlocking) return
        console.log("[lockscreen] begin unlock")
        root.unlocking = true
        unlockTimer.restart()
    }

    function unlock() {
        root.beginUnlock()
    }

    function finishUnlock() {
        console.log("[lockscreen] finish unlock")
        countdown.stop()
        unlockTimer.stop()
        root.secondsLeft = -1
        root.unlocking = false
        root.locked = false
        root.auth.reset()
    }

    function submit(password) {
        root.auth.authenticate(password)
    }

    onLockedChanged: {
        if (!root.locked) {
            countdown.stop()
            unlockTimer.stop()
            root.secondsLeft = -1
            root.unlocking = false
        }
    }

    Timer {
        id: unlockTimer
        interval: (root.theme ? root.theme.lockOutMs : 220) + 200
        repeat: false
        onTriggered: root.finishUnlock()
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (!root.locked || root.unlocking) return
            root.secondsLeft -= 1
            if (root.secondsLeft <= 0) {
                root.secondsLeft = 0
                root.beginUnlock()
            }
        }
    }

    IpcHandler {
        target: "lockscreen"
        function lock(): void { root.lock() }
        function unlock(): void { root.unlock() }
        function lockTimed(seconds: int): void { root.lockTimed(seconds) }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.locked

        surface: Component {
            WlSessionLockSurface {
                color: root.theme ? root.theme.background : "#0d1011"

                LockSurface {
                    anchors.fill: parent
                    theme: root.theme
                    config: root.config
                    authState: root.auth.state
                    authAttempts: root.auth.attempts
                    authMessage: root.auth.message
                    notifications: root.notifications
                    autoUnlockIn: root.secondsLeft
                    unlocking: root.unlocking
                    onSubmitted: function (pw) { root.submit(pw) }
                    // The timer below is the ceiling; this is the normal path.
                    onUnlockAnimationFinished: root.finishUnlock()
                }
            }
        }
    }
}