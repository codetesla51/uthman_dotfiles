import QtQuick

// Lyrics — a three-line window around the active synced line. A short accent
// rail marks the line being sung; the neighbours sit back so the eye lands on
// the right words without a card or a box. Loading and "no lyrics" are quiet
// single rows instead of holes, and every change fades rather than snapping.
Item {
    id: root

    property var theme
    property var source
    property real position: 0

    implicitHeight: root.theme ? root.theme.lyricsHeight : 56

    readonly property var lines: root.source ? root.source.lines : []
    readonly property bool ready: root.lines !== null && root.lines !== undefined
        && root.lines.length > 0
    readonly property string state: root.source ? root.source.state : "idle"

    // First line whose timestamp has passed. -1 before the song starts; the
    // window clamps that to the first line so something is always readable.
    readonly property int index: {
        var list = root.lines
        if (!list || list.length === 0) return -1
        var p = Math.max(0, root.position || 0)
        var idx = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].t <= p + 0.12) idx = i
            else break
        }
        return idx
    }

    readonly property int activeIndex: root.ready ? Math.max(0, root.index) : -1

    function lineAt(i) {
        if (!root.lines || i < 0 || i >= root.lines.length) return ""
        return root.lines[i].x
    }

    readonly property string activeText: {
        var text = root.lineAt(root.activeIndex)
        return text === "" ? "♪" : text
    }

    function pulse() {
        if (!root.ready) return
        activeLine.opacity = 1
        activePulse.restart()
    }

    onActiveIndexChanged: root.pulse()

    // ── the lyric window ─────────────────────────────────────────────────
    Item {
        id: window
        anchors.fill: parent
        opacity: root.ready ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Rectangle {
            id: rail
            x: 0
            y: 16
            width: root.theme ? root.theme.lyricsRailWidth : 2
            height: 24
            radius: width / 2
            color: root.theme ? root.theme.primary : "#ffffff"
            opacity: 0.8
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            Text {
                width: parent.width
                height: 16
                verticalAlignment: Text.AlignVCenter
                text: root.lineAt(root.activeIndex - 1)
                color: root.theme ? root.theme.muted : "#8c8c8c"
                opacity: 0.42
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize + 0.5 : 11.5
                font.letterSpacing: 0.2
                elide: Text.ElideRight
            }

            Text {
                id: activeLine
                width: parent.width
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.activeText
                color: root.theme ? root.theme.foreground : "#e2e2e2"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.bodySize + 1 : 15
                font.weight: Font.DemiBold
                font.letterSpacing: 0.1
                elide: Text.ElideRight
                transform: Translate { id: activeShift }

                ParallelAnimation {
                    id: activePulse
                    NumberAnimation {
                        target: activeLine
                        property: "opacity"
                        from: 0.35
                        to: 1
                        duration: 240
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: activeShift
                        property: "y"
                        from: 4
                        to: 0
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                width: parent.width
                height: 16
                verticalAlignment: Text.AlignVCenter
                text: root.lineAt(root.activeIndex + 1)
                color: root.theme ? root.theme.muted : "#8c8c8c"
                opacity: 0.26
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize + 0.5 : 11.5
                font.letterSpacing: 0.2
                elide: Text.ElideRight
            }
        }
    }

    // ── loading / none: one quiet line where the lyrics would be ─────────
    Row {
        id: emptyRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 13
        spacing: 9
        opacity: root.ready || root.state === "idle" ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Icon {
            id: emptyGlyph
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            glyph: root.state === "loading" ? "" : ""
            size: 12
            tint: root.theme ? root.theme.quiet : "#565656"

            RotationAnimation on rotation {
                running: root.state === "loading"
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1600
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.state === "loading" ? "finding lyrics" : "no synced lyrics"
            color: root.theme ? root.theme.quiet : "#565656"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.tinySize : 10
            font.letterSpacing: 0.4
        }
    }

    Component.onCompleted: root.pulse()
}
