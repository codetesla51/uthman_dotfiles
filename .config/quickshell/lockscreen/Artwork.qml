import QtQuick
import Qt5Compat.GraphicalEffects

// Artwork — the album cover cropped to a rounded square. The mask is a layer
// effect, so the image's square corners cannot poke through the radius. When
// there is no art (or it is still decoding), the music glyph holds the slot.
Item {
    id: root

    property var theme
    property string source: ""
    property int radius: root.theme ? root.theme.artRadius : 12

    implicitWidth: root.theme ? root.theme.artSize : 60
    implicitHeight: implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.theme
            ? root.theme.alpha(root.theme.foreground, 0.05) : "#171717"
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        layer.enabled: source !== "" && status === Image.Ready
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: image.width
                height: image.height
                radius: root.radius
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: ""
        color: root.theme
            ? root.theme.alpha(root.theme.foreground, 0.20) : "#333333"
        font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
        font.pixelSize: Math.round(root.width * 0.38)
        visible: !root.source || image.status !== Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: root.theme ? root.theme.artBorder : "#2c2c2c"
    }
}
