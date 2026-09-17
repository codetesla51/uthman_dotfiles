import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// NowPlaying - flat cluster inside the center trapezium (separated by | in Bar.qml):
// rounded art / two-line title+artist / live visualizer / circular transport buttons.
// Color backdrop: dominant hue from album art, applied as a soft pill glow.
Item {
    id: root
    property var colors
    signal hoverChanged(bool hovered)
    property var player: Mpris.players.values.find(function(p){ return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.playbackState === MprisPlaybackState.Playing
    readonly property string artUrl: hasPlayer ? (player.trackArtUrl || "") : ""
    property color trackColor: colors.primary

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 30

    // extract dominant color from album art (1x1 canvas sample)
    Canvas {
        id: artCanvas
        width: 1; height: 1
        visible: false
        property string pendingUrl: ""
        onImageLoaded: {
            var ctx = getContext("2d")
            ctx.drawImage(pendingUrl, 0, 0, 1, 1)
            requestPaint()
        }
        onPaint: {
            var ctx = getContext("2d")
            var px = ctx.getImageData(0, 0, 1, 1).data
            var r = px[0] / 255, g = px[1] / 255, b = px[2] / 255
            // boost saturation slightly so the tint reads as a color, not mud
            var max = Math.max(r, g, b), min = Math.min(r, g, b)
            var avg = (r + g + b) / 3
            var boost = 1.35
            var nr = avg + (r - avg) * boost, ng = avg + (g - avg) * boost, nb = avg + (b - avg) * boost
            root.trackColor = Qt.rgba(
                Math.min(1, Math.max(0, nr)),
                Math.min(1, Math.max(0, ng)),
                Math.min(1, Math.max(0, nb)), 1)
        }
    }
    Image {
        id: artExtractor
        width: 32; height: 32
        visible: false
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        source: root.artUrl
        onStatusChanged: {
            if (status === Image.Ready) {
                artCanvas.pendingUrl = source
                artCanvas.loadImage(source)
            }
        }
    }

    // pill backdrop tinted by track color — no border, no visible edges
    Rectangle {
        anchors.fill: row
        anchors.leftMargin: -12; anchors.rightMargin: -12
        anchors.topMargin: -8; anchors.bottomMargin: -4
        radius: 16
        color: root.hasPlayer ? colors.alpha(root.trackColor, 0.09) : "transparent"
        Behavior on color { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 9
        // -- album art: 26px, near-circular, hairline ring; mask rounds the corners
        // (Rectangle.clip is unreliable for rounding — same OpacityMask trick as the card)
        Rectangle {
            id: artFrame
            visible: root.hasPlayer && player.trackArtUrl !== ""
            width: 26; height: 26; radius: 12
            color: colors.alpha(colors.surface, 0.5)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle { width: artFrame.width; height: artFrame.height; radius: artFrame.radius }
            }
            Image {
                anchors.fill: parent
                source: root.hasPlayer ? player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        Rectangle {
            visible: !root.hasPlayer || player.trackArtUrl === ""
            width: 26; height: 26; radius: 12
            color: colors.alpha(colors.surface, 0.5)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)
            Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11 }
        }

        // -- title over artist, two tight lines --
        ColumnLayout {
            visible: root.hasPlayer
            spacing: 1
            Text {
                text: root.hasPlayer ? (player.trackTitle || "Unknown") : "Nothing playing"
                color: root.hasPlayer ? colors.foreground : colors.alpha(colors.foreground, 0.45)
                font.family: colors.fontSans
                font.pixelSize: 10
                font.weight: Font.Bold
                font.italic: !root.hasPlayer
                elide: Text.ElideRight
                Layout.maximumWidth: 118
            }
            Text {
                visible: root.hasPlayer
                text: {
                    if (!root.hasPlayer) return ""
                    var a = player.trackArtist
                    return a && a.length > 0 ? a : "Unknown artist"
                }
                color: colors.alpha(colors.foreground, 0.55)
                font.family: colors.fontSans
                font.pixelSize: 8
                font.weight: Font.Medium
                elide: Text.ElideRight
                Layout.maximumWidth: 118
            }
        }

        // -- visualizer: five dancing bars, staggered timers --
        // one Matugen accent per bar, cycling primary / secondary / tertiary
        Row {
            id: visRow
            opacity: root.hasPlayer ? 1 : 0.5
            spacing: 2
            readonly property var barColors: [colors.primary, colors.secondary, colors.tertiary]
            Repeater {
                model: 5
                delegate: Rectangle {
                    id: bar
                    required property int index
                    width: 2
                    radius: 1
                    color: visRow.barColors[index % visRow.barColors.length]
                    opacity: 0.72 + index * 0.06
                    height: root.isPlaying ? 8 : 3
                    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Timer {
                        interval: 120 + bar.index * 23
                        running: root.isPlaying
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: bar.height = 4 + Math.random() * 10
                    }
                }
            }
        }

        // -- transport: ghost prev/next, filled play, hover lift --
        // always visible; dims when idle so the bar never feels dead
        RowLayout {
            opacity: root.hasPlayer ? 1 : 0.45
            spacing: 3
            Rectangle {
                id: prevBtn
                property bool fresh: true
                width: 20; height: 20; radius: 10
                color: (prevMa.containsMouse && prevBtn.fresh) ? colors.alpha(colors.primary, 0.15) : "transparent"
                scale: (prevMa.containsMouse && prevBtn.fresh) ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: "󰒮"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10 }
                MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onContainsMouseChanged: if(!containsMouse) prevBtn.fresh = true; onClicked: { if(root.hasPlayer && root.player.canGoPrevious) root.player.previous(); prevBtn.fresh = false } }
            }
            Rectangle {
                id: playBtn
                property bool fresh: true
                width: 22; height: 22; radius: 11
                color: (playMa.containsMouse && playBtn.fresh) ? colors.primary : colors.alpha(colors.primary, 0.18)
                border.width: 1
                border.color: (playMa.containsMouse && playBtn.fresh) ? colors.primary : colors.alpha(colors.primary, 0.35)
                scale: (playMa.containsMouse && playBtn.fresh) ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; color: (playMa.containsMouse && playBtn.fresh) ? colors.background : colors.primary; font.family: colors.fontSans; font.pixelSize: 10 }
                MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; onContainsMouseChanged: if(!containsMouse) playBtn.fresh = true; onClicked: { if(root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying(); playBtn.fresh = false } }
            }
            Rectangle {
                id: nextBtn
                property bool fresh: true
                width: 20; height: 20; radius: 10
                color: (nextMa.containsMouse && nextBtn.fresh) ? colors.alpha(colors.primary, 0.15) : "transparent"
                scale: (nextMa.containsMouse && nextBtn.fresh) ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: "󰒭"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10 }
                MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onContainsMouseChanged: if(!containsMouse) nextBtn.fresh = true; onClicked: { if(root.hasPlayer && root.player.canGoNext) root.player.next(); nextBtn.fresh = false } }
            }
        }
    }

    // hover-only catcher behind everything: acceptedButtons none, so transport
    // clicks pass straight through while hover still tracks
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: root.hoverChanged(containsMouse)
    }
}
