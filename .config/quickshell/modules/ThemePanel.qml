import Quickshell
import Quickshell.Io
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
    visible: root.open
    focusable: true
    IpcHandler { target: "theme"; function toggle(): void { root.open = !root.open } }

    function refresh(){
        currentProc.running = true
        listProc.running = true
    }
    function setWall(path){
        applying = true
        Quickshell.execDetached(["sh","-c","/home/uthman/.local/bin/set-wallpaper '"+path.replace(/'/g,"'\\''")+"' & disown"])
        currentWall = path
        // find index
        for(var i=0;i<walls.length;i++) if(walls[i].path===path) { currentIndex=i; break }
        applyTimer.restart()
    }
    function next(){ if(walls.length===0) return; currentIndex = (currentIndex+1)%walls.length; previewTransition.restart() }
    function prev(){ if(walls.length===0) return; currentIndex = (currentIndex-1+walls.length)%walls.length; previewTransition.restart() }

    Timer { id: applyTimer; interval: 900; onTriggered: root.applying = false }


    onOpenChanged: if(open) refresh()
    onWallsChanged: {
        // sync currentIndex to currentWall
        for(var i=0;i<walls.length;i++) if(walls[i].path===currentWall) { currentIndex=i; return }
        if(walls.length>0) currentIndex=0
    }

    Process {
        id: currentProc
        command: ["sh","-c","readlink -f ~/.config/omarchy/current/background 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentWall = text.trim() }
    }
    Process {
        id: listProc
        command: ["sh","-c","(find ~/.config/omarchy/themes/snow_black/backgrounds -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/omarchy/backgrounds/snow_black -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' \\) 2>/dev/null; find ~/.config/omarchy/backgrounds -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.png' \\) 2>/dev/null) | head -n 300"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                var arr=[]
                for(var i=0;i<lines.length;i++){
                    var p=lines[i].trim()
                    if(!p) continue
                    arr.push({name:p.split("/").pop(), path:p})
                }
                root.walls=arr
            }
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
        height: 560
        radius: 20
        color: "transparent"
        border.width: 0
        focus: root.open
        Keys.onEscapePressed: root.open=false
        Keys.onLeftPressed: root.prev()
        Keys.onRightPressed: root.next()
        Keys.onSpacePressed: root.setWall(walls[currentIndex].path)
        Keys.onReturnPressed: root.setWall(walls[currentIndex].path)
        Keys.onEnterPressed: root.setWall(walls[currentIndex].path)
        transform: Translate { id: slide }
        Component.onCompleted: slide.y=20
        onVisibleChanged: if(visible){ slide.y=20; slideIn.restart() }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "y"; from:20; to:0; duration:260; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from:0; to:1; duration:200 }
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
                spacing: 10
                Item { Layout.fillWidth: true }
                Text { visible: root.applying; text: "Applying…"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                Rectangle {
                    visible: root.applying
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; RotationAnimation on rotation { running: root.applying; loops: Animation.Infinite; from:0; to:360; duration:700 } }
                }
                Item { Layout.fillWidth: true }
            }

            // main octagon + orbiting thumbs around it
            Item {
                id: previewItem
                Layout.fillWidth: true
                Layout.preferredHeight: 320
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
                            source: walls.length>0 ? "file://"+walls[currentIndex].path : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
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

                // caption
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 10
                    width: capText.implicitWidth+16
                    height: 22
                    radius: 11
                    color: colors.alpha(colors.background,0.85)
                    Text {
                        id: capText
                        anchors.centerIn: parent
                        text: walls.length>0 ? walls[currentIndex].name : ""
                        color: colors.foreground
                        font.family:"FiraCode Nerd Font"; font.pixelSize: 9
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

            // circular — pics around center, rotating

            // slider — horizontal, circular thumbs
            ListView {
                id: slider
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                orientation: ListView.Horizontal
                clip: true
                spacing: 8
                model: walls
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: 64; height: 64
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
                        Image {
                            anchors.fill: parent
                            source: "file://"+modelData.path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: modelData.path===root.currentWall ? 2 : 1
                            border.color: modelData.path===root.currentWall ? colors.primary : maS.containsMouse ? colors.alpha(colors.primary,0.4) : "transparent"
                            // octagon border via Shape
                            Shape {
                                anchors.fill: parent
                                ShapePath {
                                    strokeColor: modelData.path===root.currentWall ? colors.primary : maS.containsMouse ? colors.alpha(colors.primary,0.4) : "transparent"
                                    fillColor: "transparent"
                                    strokeWidth: modelData.path===root.currentWall ? 2 : 1
                                    PathSvg { path: "M 19 0 L 45 0 L 64 19 L 64 45 L 45 64 L 19 64 L 0 45 L 0 19 Z" }
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: maS
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { root.currentIndex=index; previewTransition.restart() }
                        onDoubleClicked: root.setWall(modelData.path)
                    }
                }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Center)
                Connections { target: root; function onCurrentIndexChanged(){ slider.currentIndex=root.currentIndex; slider.positionViewAtIndex(root.currentIndex, ListView.Center) } }
            }



            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Press Enter to apply  •  ← → to navigate"
                    color: colors.alpha(colors.outline,0.5)
                    font.family:"FiraCode Nerd Font"; font.pixelSize: 9
                    Layout.fillWidth: true
                }

            }
        }
    }
}
