import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects

// Theme Selector — slideshow, octagon-shaped, with preview. Replaces the grid.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string currentWall: ""
    property int currentIndex: 0
    property var walls: []
    property bool applying: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open || closeAnim.running
    focusable: true
    WlrLayershell.namespace: "qs-theme"
    // NOTE: no IpcHandler here — Bar.qml owns target "theme" and lazy-loads this.

    property double lastScan: 0
    readonly property string cachePath: Quickshell.env("HOME") + "/.cache/quickshell/theme-walls.cache"
    function parseList(text){
        var lines=text.trim().split("\n")
        var arr=[]
        for(var i=0;i<lines.length;i++){
            var parts=lines[i].trim().split("|")
            var p=(parts.length>1 ? parts[1] : parts[0]).trim()
            if(!p) continue
            arr.push({name:p.split("/").pop(), path:p, thumb:(parts.length>2 && parts[2]) ? parts[2] : p})
        }
        if(arr.length>0) root.walls=arr
    }
    Component.onCompleted: cacheProc.running = true
    function refresh(){
        currentProc.running = true
        // cached list already paints instantly; heavy scan refreshes behind it
        var now = Date.now()
        if (walls.length === 0 || now - lastScan > 30000) { lastScan = now; listProc.running = true }
    }
    function setWall(path){
        applying = true
        Quickshell.execDetached(["sh","-c","$HOME/.local/bin/set-wallpaper '"+path.replace(/'/g,"'\\''")+"' & disown"])
        currentWall = path
        // find index
        for(var i=0;i<walls.length;i++) if(walls[i].path===path) { currentIndex=i; break }
        applyTimer.restart()
    }
    function next(){ if(walls.length===0) return; currentIndex = (currentIndex+1)%walls.length; userMoved() }
    function prev(){ if(walls.length===0) return; currentIndex = (currentIndex-1+walls.length)%walls.length; userMoved() }
    // auto-apply: moving the highlight applies the wallpaper once you stop
    // (650ms debounce — matugen recolor is too heavy to fire per tick).
    // Only user moves arm it; list reloads and programmatic sets never do.
    property bool autoArmed: false
    function userMoved(){ autoArmed = true; autoTimer.restart() }
    Timer { id: autoTimer; interval: 650; onTriggered: {
        if(!root.open || !root.autoArmed) return
        root.autoArmed = false
        if(root.walls.length===0) return
        var w = root.walls[root.currentIndex]
        if(w && w.path !== root.currentWall) root.setWall(w.path)
    } }

    // ---- orbital ring ----
    readonly property int slots: Math.min(walls.length, 12)
    readonly property real step: slots > 0 ? 360/slots : 360
    property real ringRot: 0                      // degrees, unbounded
    function imod(a, n){ return n > 0 ? ((a % n) + n) % n : 0 }
    function rotateTo(idx){
        if (slots === 0) return
        var target = -idx * step
        var delta = ((target - ringRot) % 360 + 540) % 360 - 180   // shortest path
        rotAnim.to = ringRot + delta
        rotAnim.restart()
    }
    NumberAnimation { id: rotAnim; target: root; property: "ringRot"; duration: 380; easing.type: Easing.OutCubic }
    onCurrentIndexChanged: rotateTo(currentIndex)

    Timer { id: applyTimer; interval: 900; onTriggered: root.applying = false }


    // card motion lives in openAnim/closeAnim below (bezier pair).
    // Close plays out before the window hides (visible binds running).
    onOpenChanged: if (open) { refresh(); openAnim.restart() } else closeAnim.restart()
    onWallsChanged: {
        // sync currentIndex to currentWall
        for(var i=0;i<walls.length;i++) if(walls[i].path===currentWall) { currentIndex=i; return }
        if(walls.length>0) currentIndex=0
    }

    Process {
        id: currentProc
        command: ["sh","-c","readlink -f ~/.config/theme/current/background 2>/dev/null || readlink -f ~/.config/omarchy/current/background 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentWall = text.trim() }
    }
    Process {
        id: cacheProc
        command: ["sh","-c","cat \"$HOME/.cache/quickshell/theme-walls.cache\" 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if(text.trim() !== "") root.parseList(text)
                // pre-warm: refresh thumbs in background even before first open
                root.lastScan = Date.now(); listProc.running = true
            }
        }
    }
    Process {
        id: listProc
        command: ["sh","-c","mkdir -p \"$HOME/.cache/quickshell\"; (find ~/dotfiles/wallpapers \\( -type f -o -type l \\) \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/theme/current -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/theme/themes/snow_black/backgrounds -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/omarchy/themes/snow_black/backgrounds -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/omarchy/backgrounds -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.png' \\) 2>/dev/null) | head -n 300 | $HOME/.local/bin/mkthumbs | tee \"$HOME/.cache/quickshell/theme-walls.cache\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseList(text)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: root.open=false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 720
        height: 640
        radius: 20
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        // frosted glass — blurred current wallpaper INSIDE the card.
        // Capped source: blur hides detail anyway, full-res was pure GPU tax.
        Image {
            id: wallSrc
            anchors.fill: parent
            source: root.currentWall !== "" ? "file://" + root.currentWall : ""
            sourceSize: Qt.size(480, 270)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        FastBlur {
            anchors.fill: parent
            source: wallSrc
            radius: 48
            visible: wallSrc.status === Image.Ready
        }
        Rectangle {
            anchors.fill: parent
            color: colors.alpha(colors.background, 0.42)
        }
        // clip all children to the card radius
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: card.width; height: card.height; radius: 20 }
        }
        focus: root.open
        Keys.onEscapePressed: root.open=false
        Keys.onLeftPressed: root.prev()
        Keys.onRightPressed: root.next()
        Keys.onSpacePressed: root.setWall(walls[currentIndex].path)
        Keys.onReturnPressed: root.setWall(walls[currentIndex].path)
        Keys.onEnterPressed: root.setWall(walls[currentIndex].path)
        transform: Translate { id: slide }
        Component.onCompleted: slide.y=20
        // bezier pair — rise settles with overshoot bounce on open, hurries
        // out plain on close. Card is centered so scale uses the card
        // property (transformOrigin center) instead of an edge Scale.
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: slide; property: "y"; from: 20; to: 0; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.96; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: slide; property: "y"; to: 20; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.96; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }
        // preview transition
        ParallelAnimation {
            id: previewTransition
            NumberAnimation { target: previewItem; property: "scale"; from:0.96; to:1; duration:220; easing.type: Easing.OutCubic }
            NumberAnimation { target: previewItem; property: "opacity"; from:0.7; to:1; duration:220 }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "THEME"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5 }
                Text { text: walls.length > 0 ? walls.length + " walls" : ""; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9 }
                Item { Layout.fillWidth: true }
                Text { visible: root.applying; text: "Applying…"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                Rectangle {
                    visible: root.applying
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10; RotationAnimation on rotation { running: root.applying; loops: Animation.Infinite; from:0; to:360; duration:700 } }
                }
                Item { Layout.fillWidth: true }
            }

            // main octagon + orbiting thumbs around it
            Item {
                id: previewItem
                Layout.fillWidth: true
                Layout.preferredHeight: 484
                Text { visible: root.walls.length === 0; anchors.centerIn: parent; text: "scanning wallpapers…"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                WheelHandler { acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad; onWheel: (wheel) => { if (wheel.angleDelta.y < 0) root.next(); else root.prev() } }
                // octagon mask via Shape + OpacityMask
                Item {
                    id: octagon
                    anchors.centerIn: parent
                    width: 300
                    height: 300
                    // Use a Canvas to draw octagon clip + image

                    // Use Image with layer mask for actual octagon image
                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Shape {
                                anchors.fill: parent
                                ShapePath {
                                    fillColor: "white"
                                    strokeColor: "transparent"
                                    PathSvg { path: "M 88 0 L 212 0 L 300 88 L 300 212 L 212 300 L 88 300 L 0 212 L 0 88 Z" }
                                    // Approx octagon, will be scaled to 300x300
                                }
                            }
                        }
                        Image {
                            anchors.fill: parent
                            property bool thumbFailed: false
                            source: walls.length>0 ? ("file://" + (thumbFailed ? walls[currentIndex].path : (walls[currentIndex].thumb || walls[currentIndex].path))) : ""
                            onStatusChanged: if (status === Image.Error && !thumbFailed) thumbFailed = true
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(600, 600)
                        }
                    }
                    // border
                    Shape {
                        anchors.fill: parent
                        ShapePath {
                            strokeColor: colors.alpha(colors.primary,0.5)
                            fillColor: "transparent"
                            strokeWidth: 2
                            PathSvg { path: "M 88 0 L 212 0 L 300 88 L 300 212 L 212 300 L 88 300 L 0 212 L 0 88 Z" }
                        }
                    }
                }

                // ---- orbital satellites: 12 octagon thumbs on a ring around the main one ----
                Repeater {
                    model: root.slots
                    delegate: Item {
                        id: sat
                        required property int index
                        readonly property real phi: (root.ringRot + index * root.step) * Math.PI / 180
                        readonly property real ang: phi - Math.PI / 2                       // slot 0 rests at 12 o'clock
                        readonly property int wIdx: root.imod(Math.round(-root.ringRot / root.step) + index, root.walls.length)
                        readonly property bool isApplied: root.walls.length > 0 && root.walls[wIdx].path === root.currentWall
                        readonly property bool isSelected: root.walls.length > 0 && wIdx === root.currentIndex
                        readonly property real front: 0.5 + 0.5 * Math.cos(phi)             // 1 at top, 0 at bottom

                        width: 62; height: 62
                        x: parent.width / 2 - 31 + Math.cos(ang) * 204
                        y: parent.height / 2 - 31 + Math.sin(ang) * 204
                        opacity: 0.55 + 0.45 * front
                        scale: (0.92 + 0.14 * front) * (maS.containsMouse ? 1.08 : 1) * (sat.isSelected ? 1.12 : 1)
                        z: isSelected ? 2 : 1
                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        Item {
                            anchors.fill: parent
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Shape {
                                    anchors.fill: parent
                                    ShapePath {
                                        fillColor: "white"
                                        strokeColor: "transparent"
                                        PathSvg { path: "M 19 0 L 45 0 L 64 19 L 64 45 L 45 64 L 19 64 L 0 45 L 0 19 Z" }
                                    }
                                }
                            }
                            // frosted glass base so the thumb reads on any wallpaper
                            Shape {
                                anchors.fill: parent
                                ShapePath {
                                    fillColor: colors.alpha(colors.background, 0.62)
                                    strokeColor: "transparent"
                                    PathSvg { path: "M 19 0 L 45 0 L 64 19 L 64 45 L 45 64 L 19 64 L 0 45 L 0 19 Z" }
                                }
                            }
                            Image {
                                anchors.fill: parent
                                opacity: 0.87
                                property bool thumbFailed: false
                                source: root.walls.length > 0 ? ("file://" + (thumbFailed ? root.walls[sat.wIdx].path : (root.walls[sat.wIdx].thumb || root.walls[sat.wIdx].path))) : ""
                                onStatusChanged: if (status === Image.Error && !thumbFailed) thumbFailed = true
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                sourceSize: Qt.size(128, 128)
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            ShapePath {
                                strokeColor: (sat.isSelected || sat.isApplied) ? colors.primary
                                           : maS.containsMouse ? colors.alpha(colors.primary, 0.45)
                                           : colors.alpha(colors.outline, 0.18)
                                fillColor: "transparent"
                                strokeWidth: sat.isSelected ? 2.5 : sat.isApplied ? 2 : maS.containsMouse ? 1.5 : 1
                                PathSvg { path: "M 19 0 L 45 0 L 64 19 L 64 45 L 45 64 L 19 64 L 0 45 L 0 19 Z" }
                            }
                        }
                        MouseArea {
                            id: maS
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.currentIndex = sat.wIdx; root.userMoved() }
                            onDoubleClicked: root.setWall(root.walls[sat.wIdx].path)
                        }
                    }
                }

                // caption — docked inside the octagon's lower edge
                Rectangle {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 129
                    width: Math.min(capText.implicitWidth+16, 420)
                    height: 22
                    radius: 11
                    color: colors.alpha(colors.background,0.85)
                    Text {
                        id: capText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 388)
                        horizontalAlignment: Text.AlignHCenter
                        text: walls.length>0 ? ((currentIndex+1) + " / " + walls.length + "  •  " + walls[currentIndex].name) : ""
                        color: colors.foreground
                        font.family: colors.fontSans; font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }
                }

            }

            // palette preview
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: [colors.primary, colors.secondary, colors.tertiary, colors.error, colors.surface, colors.outline]
                    delegate: Rectangle {
                        required property var modelData
                        width: 32; height: 14; radius: 7
                        color: modelData
                        border.width:1; border.color: colors.alpha(colors.outline,0.15)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "scroll or ←→ to browse  •  enter applies  •  double-click jumps  •  esc closes"
                    color: colors.alpha(colors.outline,0.5)
                    font.family: colors.fontSans; font.pixelSize: 9
                    Layout.fillWidth: true
                }

            }
        }
    }
}
