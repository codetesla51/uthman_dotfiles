import Quickshell
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

    implicitHeight: root.theme ? root.theme.musicHeight : 158

    function refreshPosition() {
        var p = root.player
        root.position = p ? (p.position || 0) : 0
    }

    onPlayerChanged: refreshPosition()

    Timer {
        interval: 500
        repeat: true
        running: root.playing
        onTriggered: root.refreshPosition()
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

        Column {
            width: parent.width - (root.theme ? root.theme.artSize : 52) - 14
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