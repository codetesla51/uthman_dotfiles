import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Hornet Shimeji pet — transparent PanelWindow, only PNG visible.
// - exclusiveZone: 0, click-through except sprite (mask)
// - sprite size exactly 128×128 (source implicit), no stretching
// - frame-swap via Timer over pet-actions.json file list
// - walks across bottom edge when Walk/Run/Dash, idles otherwise
// - dialogue bubble occasional (via StateMachine)
// - dragging → Pinched / Falling feedback
PanelWindow {
    id: root

    // ── window chrome ───────────────────────────────────────────────
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true
    focusable: false
    color: "transparent"
    WlrLayershell.namespace: "qs-pet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // only sprite receives input — everything else click-through
    mask: Region { item: petWrapper }

    // ── ipc ─────────────────────────────────────────────────────────
    IpcHandler {
        target: "pet"
        function toggle(): void { root.visible = !root.visible }
        function show(): void { root.visible = true }
        function hide(): void { root.visible = false }
        function pet(): void { stateMachine.trigger("PetAction") }
    }

    // ── actions file ────────────────────────────────────────────────
    property var actions: ({})
    property string actionsFile: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/config/pet-actions.json"
    property string assetsBase: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/assets/"

    FileView {
        id: actionsFileView
        path: root.actionsFile
        printErrors: true
        onLoaded: {
            try {
                var data = JSON.parse(text())
                root.actions = data
                console.log("[Pet] loaded " + Object.keys(data).length + " actions")
            } catch (e) {
                console.warn("[Pet] failed to parse pet-actions.json: " + e)
            }
        }
        onLoadFailed: function(err) {
            console.warn("[Pet] loadFailed " + path + " : " + err)
        }
    }
    Component.onCompleted: {
        // force load
        actionsFileView.path = ""
        actionsFileView.path = root.actionsFile
    }

    // ── state + frames ──────────────────────────────────────────────
    property string currentAction: "Stand"
    property var currentFrames: ["shime1.png", "shime1a.png"]
    property int currentFrameIndex: 0
    property int frameInterval: 180
    property string currentFile: currentFrames.length > 0 ? currentFrames[currentFrameIndex % currentFrames.length] : "shime1.png"
    property string currentFrameUrl: "file://" + assetsBase + currentFile
    property bool facingRight: false
    property string bubbleText: ""
    property bool isDragging: false
    property bool isFalling: false

    // position — floor-anchored, x slides
    property int petX: 120
    property int petY: 0 // computed
    property int spriteW: petWrapper.width > 0 ? petWrapper.width : 128
    // keep inside screen
    function clampX(x) {
        if (root.width <= 0) return x
        var w = spriteW
        return Math.max(2, Math.min(x, root.width - w - 2))
    }

    StateMachine {
        id: stateMachine
        actions: root.actions
        onActionChanged: function(name, frames, interval, bubble, kind) {
            root.currentAction = name
            root.currentFrames = frames
            root.frameInterval = interval
            root.currentFrameIndex = 0
            root.bubbleText = bubble
            if (bubble !== "") bubbleHideTimer.restart()
            frameTimer.interval = interval
            frameTimer.restart()
            // movement decision
            if (!root.isDragging && !root.isFalling) {
                if (kind === "walk") {
                    root.startWalk(name)
                } else {
                    root.stopWalk()
                }
            }
            // fade bubble if empty
            if (bubble === "") bubbleHideTimer.stop()
        }
    }

    // dialogue auto-hide
    Timer {
        id: bubbleHideTimer
        interval: 2200
        repeat: false
        onTriggered: root.bubbleText = ""
    }

    // frame swap — cycles through file list, no stretching
    Timer {
        id: frameTimer
        interval: root.frameInterval
        repeat: true
        running: true
        onTriggered: {
            if (root.currentFrames.length === 0) return
            root.currentFrameIndex = (root.currentFrameIndex + 1) % root.currentFrames.length
        }
    }

    // ── movement — x animated across bottom edge ─────────────────────
    function speedFor(action) {
        if (action === "Run" || action === "RunWithIe") return 145
        if (action === "Dash") return 225
        // Walk default
        return 68
    }

    function startWalk(action) {
        if (root.width <= 0) {
            // defer until window mapped
            Qt.callLater(function(){ startWalk(action) })
            return
        }
        var w = spriteW
        if (w <= 0) w = 128
        var maxX = Math.max(2, root.width - w - 2)
        // random target not too close
        var cur = root.petX
        var target = Math.floor(Math.random() * (maxX - 2 + 1)) + 2
        // avoid tiny moves < 120px (unless stuck)
        var tries = 0
        while (Math.abs(target - cur) < 120 && tries < 6) {
            target = Math.floor(Math.random() * (maxX - 2 + 1)) + 2
            tries++
        }
        var dist = Math.abs(target - cur)
        var spd = speedFor(action)
        var dur = Math.max(900, Math.min(9000, dist / spd * 1000))
        root.facingRight = target > cur
        xAnim.duration = dur
        root.petX = clampX(target)
        walkSettleTimer.restart()
    }

    function stopWalk() {
        // leave x where it is, cancel settle timer only if we were walking to idle we stay
        // no action needed — xAnim will finish its current move; interrupt with zero-duration stop
        // keep facing
    }

    // if walk interrupted by special/idle, gently stop without jump
    function cancelWalk() {
        xAnim.duration = 1
        // petX stays
    }

    // after walk completes, StateMachine will pick next via dwellTimer automatically

    Timer {
        id: walkSettleTimer
        interval: 80
        repeat: false
        // unused, placeholder if we want to chain walks
    }

    // ── drag handling — Pinched / Resisting / Falling ─────────────────
    property point dragPressGlobal: Qt.point(0,0)
    property int dragStartX: 0
    property int dragStartY: 0

    // sprite wrapper — exact PNG dimensions, no scaling
    Item {
        id: petWrapper
        // floor anchor: bottom of screen minus sprite height
        x: root.petX
        y: root.isDragging ? dragY : (root.height > 0 && height > 0 ? root.height - height - 6 : root.height - 128 - 6)
        property int dragY: root.height - height - 6
        width: sprite.implicitWidth > 0 ? sprite.implicitWidth : 128
        height: sprite.implicitHeight > 0 ? sprite.implicitHeight : 128

        Behavior on x {
            enabled: !root.isDragging
            NumberAnimation { id: xAnim; duration: 3200; easing.type: Easing.Linear }
        }
        Behavior on y {
            enabled: !root.isDragging
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // dialogue bubble — above head, centered, appears occasional
        Item {
            id: bubble
            visible: root.bubbleText !== ""
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            // center above sprite
            x: (parent.width - bubbleBg.width) / 2
            y: -bubbleBg.height - 10
            z: 2

            Rectangle {
                id: bubbleBg
                width: bubbleTextItem.implicitWidth + 20
                height: bubbleTextItem.implicitHeight + 14
                radius: 10
                color: Qt.rgba(0.09, 0.09, 0.09, 0.88)
                border.width: 1
                border.color: Qt.rgba(1,1,1,0.12)
                // small tail
                Rectangle {
                    width: 8; height: 8
                    rotation: 45
                    color: bubbleBg.color
                    border.width: 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: -5
                }

                Text {
                    id: bubbleTextItem
                    anchors.centerIn: parent
                    text: root.bubbleText
                    color: "white"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        Image {
            id: sprite
            anchors.centerIn: parent
            // no width/height set — implicitSize = source PNG dimensions (128×128 etc)
            // prevents stretching
            source: root.currentFrameUrl
            fillMode: Image.Pad
            asynchronous: true
            cache: true
            smooth: false
            mipmap: false
            // mirror when facing right: use scale transform, not Image.mirror (layoutDirection dependent)
            transform: Scale { xScale: root.facingRight ? -1 : 1; origin.x: sprite.width / 2; origin.y: sprite.height / 2 }
            onStatusChanged: if (status === Image.Error) console.warn("[Pet] image error " + source + " → " + currentFile)
        }

        // click + drag — manual so x binding stays intact
        MouseArea {
            id: spriteMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true

            onPressed: function(mouse) {
                root.isDragging = true
                root.dragPressGlobal = mapToItem(null, mouse.x, mouse.y)
                root.dragStartX = petWrapper.x
                root.dragStartY = petWrapper.y
                bubbleHideTimer.stop()
                root.bubbleText = ""
                // pause frame timer briefly then show Pinched
                frameTimer.stop()
                if (root.actions["Pinched"]) {
                    root.currentAction = "Pinched"
                    root.currentFrames = root.actions["Pinched"]
                    root.currentFrameIndex = 0
                    root.frameInterval = 90
                    frameTimer.interval = 90
                    frameTimer.restart()
                }
                stateMachine.pause()
            }
            onPositionChanged: function(mouse) {
                if (!root.isDragging) return
                var g = mapToItem(null, mouse.x, mouse.y)
                var dx = g.x - root.dragPressGlobal.x
                var dy = g.y - root.dragPressGlobal.y
                var nx = clampX(root.dragStartX + dx)
                var ny = Math.max(6, Math.min(root.height - petWrapper.height - 6, root.dragStartY + dy))
                // directly update wrapper while dragging (temporarily break binding via explicit set)
                // also keep root.petX in sync so facing logic stays correct
                petWrapper.x = nx
                petWrapper.dragY = ny
                root.petX = nx
                // update facing based on drag direction tiny hysteresis
                if (dx > 2) root.facingRight = true
                else if (dx < -2) root.facingRight = false
            }
            onReleased: function(mouse) {
                root.isDragging = false
                root.petX = clampX(petWrapper.x)
                // wrapper y will snap back to floor via binding
                root.isFalling = true
                if (root.actions["Falling"]) {
                    root.currentAction = "Falling"
                    root.currentFrames = root.actions["Falling"]
                    root.currentFrameIndex = 0
                    root.frameInterval = 90
                    frameTimer.interval = 90
                    frameTimer.restart()
                }
                fallTimer.restart()
            }
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    // right click → random special
                    var specials = ["PoseAction","ThrowNeedleAction","EatBerryAction"]
                    var avail = specials.filter(function(n){ return root.actions[n] })
                    if (avail.length) stateMachine.trigger(avail[Math.floor(Math.random()*avail.length)])
                    return
                }
                // left click quick pet -> PetAction if not dragging
                if (!root.isDragging && root.actions["PetAction"]) {
                    stateMachine.trigger("PetAction")
                }
            }
            onDoubleClicked: function(mouse) {
                // double click → dash across
                if (root.actions["Dash"]) stateMachine.trigger("Dash")
            }
        }
    }

    Timer {
        id: fallTimer
        interval: 520
        repeat: false
        onTriggered: {
            root.isFalling = false
            // bounce or stand
            if (root.actions["Bouncing"]) {
                root.currentAction = "Bouncing"
                root.currentFrames = root.actions["Bouncing"]
                root.currentFrameIndex = 0
                root.frameInterval = 85
                frameTimer.interval = 85
                frameTimer.restart()
                bounceTimer.restart()
            } else {
                stateMachine.trigger("Stand")
            }
        }
    }
    Timer {
        id: bounceTimer
        interval: 380
        repeat: false
        onTriggered: {
            var name = root.actions["Stand"] ? "Stand" : Object.keys(root.actions)[0]
            if (name) stateMachine.trigger(name)
        }
    }

    // floor sync — when window resizes, keep pet on floor and clamped
    onWidthChanged: {
        root.petX = clampX(root.petX)
    }
    onHeightChanged: {
        // petWrapper y auto-computes via binding, nothing else
    }

    // debug tick
    Timer {
        id: dbg
        interval: 8000
        running: false // set true for console spam
        repeat: true
        onTriggered: console.log("[Pet] " + currentAction + " x=" + petX + " facing=" + (facingRight?"R":"L") + " frame=" + currentFile)
    }
}
