import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

// NowPlaying - flat cluster inside the center trapezium (separated by | in Bar.qml):
// rounded art / two-line title+artist / live visualizer / circular transport buttons.
Item {
    id: root
    property var colors
    property var player: Mpris.players.values.find(function(p){ return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.playbackState === MprisPlaybackState.Playing

    implicitWidth: row.implicitWidth + 8
    implicitHeight: 30

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 9

        // -- album art: 26px, radius 8, hairline ring --
        Rectangle {
            visible: root.hasPlayer && player.trackArtUrl !== ""
            width: 26; height: 26; radius: 8
            color: colors.alpha(colors.surface, 0.5)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)
            clip: true
            Image {
                anchors.fill: parent
                source: root.hasPlayer ? player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        Rectangle {
            visible: !root.hasPlayer || player.trackArtUrl === ""
            width: 26; height: 26; radius: 8
            color: colors.alpha(colors.surface, 0.5)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)
            Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 11 }
        }

        // -- title over artist, two tight lines --
        ColumnLayout {
            visible: root.hasPlayer
            spacing: 1
            Text {
                text: root.hasPlayer ? (player.trackTitle || "Unknown") : "Nothing playing"
                color: root.hasPlayer ? colors.foreground : colors.alpha(colors.foreground, 0.45)
                font.family: "FiraCode Nerd Font"
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
                font.family: "FiraCode Nerd Font"
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
                width: 20; height: 20; radius: 10
                color: prevMa.containsMouse ? colors.alpha(colors.primary, 0.15) : "transparent"
                scale: prevMa.containsMouse ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: "󰒮"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10 }
                MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: if(root.hasPlayer && root.player.canGoPrevious) root.player.previous() }
            }
            Rectangle {
                width: 22; height: 22; radius: 11
                color: playMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.18)
                border.width: 1
                border.color: playMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.35)
                scale: playMa.containsMouse ? 1.1 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; color: playMa.containsMouse ? colors.background : colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 10 }
                MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; onClicked: if(root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying() }
            }
            Rectangle {
                width: 20; height: 20; radius: 10
                color: nextMa.containsMouse ? colors.alpha(colors.primary, 0.15) : "transparent"
                scale: nextMa.containsMouse ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Text { anchors.centerIn: parent; text: "󰒭"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10 }
                MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: if(root.hasPlayer && root.player.canGoNext) root.player.next() }
            }
        }
    }
}
