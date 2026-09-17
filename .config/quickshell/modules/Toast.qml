import QtQuick
import QtQuick.Layouts

// Toast — one-line bottom flash shared by panels (copied, saved, sent).
// Owns its hold timer: call flash("Copied") and forget. Restarts cleanly
// when flashed again mid-show.
Rectangle {
    id: root

    QtObject {
        id: fallback
        property color foreground: "#ebe1da"
        property color tertiary: "#9bcee3"
        property color surfaceVariant: "#50453b"
        property color outline: "#a39487"
        property string fontSans: "FiraCode Nerd Font"
        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    }
    property var colors: fallback
    property string text: ""
    property string glyph: ""
    property string iconFont: "Phosphor"
    property int hold: 1200

    function flash(msg) {
        if ((msg || "") !== "") root.text = msg
        holdLife.stop()
        hideLife.stop()
        root.visible = true
        root.opacity = 1
        holdLife.restart()
    }

    visible: false
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 90
    implicitWidth: toastRow.implicitWidth + 28
    implicitHeight: 32
    radius: 16
    color: colors.alpha(colors.surfaceVariant, 0.55)
    border.width: 1
    border.color: colors.alpha(colors.outline, 0.14)
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    Timer { id: holdLife; interval: root.hold; onTriggered: { root.opacity = 0; hideLife.restart() } }
    Timer { id: hideLife; interval: 170; onTriggered: root.visible = false }

    RowLayout {
        id: toastRow
        anchors.centerIn: parent
        spacing: 6
        Text {
            visible: root.glyph !== ""
            text: root.glyph
            color: colors.tertiary
            font.family: root.iconFont
            font.pixelSize: 13
        }
        Text {
            text: root.text
            color: colors.foreground
            font.family: colors.fontSans
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
}
