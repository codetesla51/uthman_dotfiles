import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import "sources"

// Music — the current MPRIS track, its artwork and synced lyrics. The local
// 500ms tick only runs while something is playing; paused players keep the
// last position and cost nothing.
Item {
    id: root

    property var theme
    property var config

    readonly property var player: {
        var list = Mpris.players.values
        for (var i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i]
        return list.length > 0 ? list[0] : null
    }
    readonly property bool hasPlayer: player !== null
    readonly property bool playing: hasPlayer
        && player.playbackState === MprisPlaybackState.Playing
    readonly property string title: hasPlayer ? (player.trackTitle || "") : ""
    readonly property string artist: hasPlayer ? (player.trackArtist || "") : ""
    readonly property string album: hasPlayer ? (player.trackAlbum || "") : ""
    readonly property string art: hasPlayer ? (player.trackArtUrl || "") : ""
    readonly property real length: hasPlayer ? (player.length || 0) : 0

    property real position: 0

    // Small equalizer beside the artwork. The lock only needs four bars, so
    // cava runs a light 8-bar / 30fps config and the values are averaged into
    // the four bars here.
    readonly property int vizBars: 4
    property var vizLevels: []

    implicitHeight: root.theme ? root.theme.musicHeight : 158

    function refreshPosition() {
        var p = root.player
        root.position = p ? (p.position || 0) : 0
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t, 1)
    }

    function vizApply(line) {
        var parts = line.trim().split(";")
        if (parts.length < 8) return
        var out = []
        for (var i = 0; i < root.vizBars; i++) {
            var a = Math.floor(i * 8 / root.vizBars)
            var b = Math.max(a + 1, Math.floor((i + 1) * 8 / root.vizBars))
            var sum = 0
            for (var j = a; j < b; j++) sum += parseInt(parts[j]) || 0
            out.push(Math.max(0, Math.min(1, sum / (b - a) / 100)))
        }
        root.vizLevels = out
    }

    function vizLevel(i) {
        return i >= 0 && i < root.vizLevels.length ? root.vizLevels[i] : 0
    }

    onPlayerChanged: refreshPosition()

    Timer {
        interval: 500
        repeat: true
        running: root.playing
        onTriggered: root.refreshPosition()
    }

    Process {
        id: vizProc
        command: ["cava", "-p", Quickshell.env("HOME")
            + "/.config/quickshell/scripts/cava-lock.conf"]
        running: root.playing
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root.vizApply(line) }
        }
    }

    LyricsSource {
        id: lyrics
        config: root.config
        artist: root.artist
        title: root.title
        duration: root.length
        active: root.title !== ""
    }

    Row {
        id: label
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: 7

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: ""
            size: 12
            tint: root.theme
                ? root.theme.alpha(root.theme.primary, 0.8) : "#8c8c8c"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Now playing"
            color: root.theme ? root.theme.muted : "#8c8c8c"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.headingSize : 10
            font.letterSpacing: root.theme ? root.theme.headingTracking : 1.4
            font.weight: Font.DemiBold
        }
    }

    Row {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: label.bottom
        anchors.topMargin: 10
        height: root.theme ? root.theme.artSize : 52
        spacing: 14
        visible: root.hasPlayer

        Artwork {
            width: root.theme ? root.theme.artSize : 60
            height: width
            theme: root.theme
            source: root.art
        }

        // Four live bars, sitting right beside the cover. Paused players
        // leave a dim row of dots instead of a frozen spectrum.
        Item {
            id: artViz
            width: 16
            height: root.theme ? root.theme.artSize : 60
            anchors.verticalCenter: parent.verticalCenter

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 2

                Repeater {
                    model: root.vizBars

                    delegate: Rectangle {
                        required property int index
                        width: 2.5
                        radius: width / 2
                        height: Math.max(3, artViz.height
                            * (root.playing ? root.vizLevel(index) : 0.05))
                        anchors.bottom: parent.bottom
                        color: root.theme
                            ? root.mix(root.theme.primary, root.theme.tertiary,
                                index / Math.max(1, root.vizBars - 1))
                            : "#ffffff"
                        opacity: root.playing ? 0.95 : 0.32
                        Behavior on height {
                            NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }

        Column {
            width: Math.max(0, parent.width
                - (root.theme ? root.theme.artSize : 60) - artViz.width - 28)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.title !== "" ? root.title : "Untitled"
                color: root.theme ? root.theme.foreground : "#e2e2e2"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.bodySize + 0.5 : 13.5
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.artist !== "" ? root.artist : "Unknown artist"
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize + 1 : 11
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.album !== ""
                text: root.album
                color: root.theme ? root.theme.quiet : "#565656"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 9
                elide: Text.ElideRight
            }
        }
    }

    Lyrics {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: track.bottom
        anchors.topMargin: 6
        height: root.theme ? root.theme.lyricsHeight : 56
        theme: root.theme
        source: lyrics
        position: root.position
        visible: root.hasPlayer
    }

    Row {
        id: controls
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: 18
        spacing: 20
        visible: root.hasPlayer

        Text {
            text: "󰒮"
            color: prevMouse.containsMouse
                ? (root.theme ? root.theme.primary : "#ffffff")
                : (root.theme ? root.theme.alpha(root.theme.foreground, 0.72)
                    : "#b8b8b8")
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: 18
            MouseArea {
                id: prevMouse
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                enabled: root.hasPlayer && root.player.canGoPrevious
                onClicked: if (root.hasPlayer && root.player.canGoPrevious) root.player.previous()
            }
        }

        Text {
            text: root.playing ? "" : ""
            color: root.theme ? root.theme.primary : "#ffffff"
            opacity: playMouse.containsMouse ? 1.0 : 0.85
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: 18
            MouseArea {
                id: playMouse
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                enabled: root.hasPlayer && root.player.canTogglePlaying
                onClicked: if (root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying()
            }
        }

        Text {
            text: "󰒭"
            color: nextMouse.containsMouse
                ? (root.theme ? root.theme.primary : "#ffffff")
                : (root.theme ? root.theme.alpha(root.theme.foreground, 0.72)
                    : "#b8b8b8")
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: 18
            MouseArea {
                id: nextMouse
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                enabled: root.hasPlayer && root.player.canGoNext
                onClicked: if (root.hasPlayer && root.player.canGoNext) root.player.next()
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.hasPlayer
        spacing: 8

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: ""
            size: 14
            tint: root.theme ? root.theme.quiet : "#565656"
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Nothing playing"
            color: root.theme ? root.theme.muted : "#8c8c8c"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.bodySize : 13
        }
    }
}