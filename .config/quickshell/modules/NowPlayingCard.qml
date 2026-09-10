import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

// NowPlaying hover card — the island expanded: track art as the background under
// dark glass, title/artist/progress floating over it, DI-style rounded corners.
// Display-only: it opens on island hover and leaves on unhover, nothing to click.
PanelWindow {
    id: root

    property var colors
    property bool hovered: false

    property var player: Mpris.players.values.find(function(p){ return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property bool hasPlayer: player !== null
    readonly property bool open: root.hovered && root.hasPlayer
    readonly property string artUrl: root.hasPlayer ? (player.trackArtUrl || "") : ""
    readonly property real position: root.hasPlayer ? (player.position || 0) : 0
    readonly property real length: root.hasPlayer ? (player.length || 0) : 0
    readonly property real progress: root.length > 0 ? Math.min(1, root.position / root.length) : 0

    // position only moves while open; the island already owns the always-on state
    Timer {
        interval: 500
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.positionChanged()
    }

    anchors { top: true }
    margins { top: 88 }
    implicitWidth: 340
    implicitHeight: 128
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    WlrLayershell.namespace: "qs-nowplaying"

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        // glass base the blur bites on; the art floats over it, dimmed into the frost
        color: colors.alpha(colors.background, 0.45)
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: card.width; height: card.height; radius: 20 }
        }

        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }

        // track art fills the card, sunk into the glass so the frost owns it
        Image {
            visible: root.artUrl !== ""
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: 0.55
        }

        // overlay: top sheen for the glass read, then the scrim the text sits on
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
            }
        }

        // hairline glass edge + inner top highlight catching the light
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.18)
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors { leftMargin: 14; rightMargin: 14; topMargin: 1 }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.12)
        }

        ColumnLayout {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors { leftMargin: 16; rightMargin: 16; bottomMargin: 13 }
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.hasPlayer ? (player.trackTitle || "Unknown") : ""
                color: "white"
                font.family: colors.fontSans
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: {
                    if (!root.hasPlayer) return ""
                    var a = player.trackArtist
                    return (a && a.length > 0 ? a : "Unknown artist") + "  ·  " + (root.isPlaying ? "Playing" : "Paused")
                }
                color: Qt.rgba(1, 1, 1, 0.65)
                font.family: colors.fontSans
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            Rectangle {
                visible: root.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 5
                height: 3
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.22)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.progress
                    radius: 1.5
                    color: "white"
                }
            }
        }
    }

    readonly property bool isPlaying: root.hasPlayer && player.playbackState === MprisPlaybackState.Playing
}
