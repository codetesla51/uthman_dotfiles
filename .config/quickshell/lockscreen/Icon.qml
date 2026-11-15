import QtQuick

// Icon — one Nerd Font glyph with the lock's type ramp. Kept in one place so
// every icon shares family, size steps and baseline behaviour.
Text {
    id: root

    property var theme
    property string glyph: ""
    property int size: 11
    property color tint: root.theme ? root.theme.muted : "#8c8c8c"

    text: root.glyph
    color: root.tint
    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
    font.pixelSize: root.size
    verticalAlignment: Text.AlignVCenter
}