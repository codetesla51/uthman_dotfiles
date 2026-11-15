import QtQuick

// Weather — place, current conditions and the day's range on one line.
// Right aligned in the column; every part is optional and every failure
// leaves a quiet empty string behind.
Item {
    id: root

    property var theme
    property var source

    implicitWidth: row.implicitWidth
    implicitHeight: 24
    visible: root.source && root.source.configured

    readonly property string conditionGlyph: {
        if (!root.source) return ""
        var c = root.source.code
        if (c === 0 || c === 1)
            return root.source.isDay ? "" : ""
        if (c === 2 || c === 3) return ""
        if (c === 45 || c === 48) return ""
        if (c >= 51 && c <= 67) return ""
        if (c >= 71 && c <= 77) return ""
        if (c >= 80 && c <= 82) return ""
        if (c >= 85 && c <= 86) return ""
        if (c >= 95) return ""
        return ""
    }

    Row {
        id: row
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Row {
            spacing: 6

            Icon {
                height: 24
                theme: root.theme
                glyph: ""
                size: 12
                tint: root.theme ? root.theme.alpha(root.theme.primary, 0.75) : "#ffffff"
            }

            Text {
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.source ? root.source.place : ""
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize : 11
                font.letterSpacing: 0.4
            }
        }

        Row {
            spacing: 7

            Icon {
                height: 24
                theme: root.theme
                glyph: root.conditionGlyph
                size: 16
                tint: root.theme ? root.theme.tertiary : "#72d2fa"
            }

            Text {
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.source && !isNaN(root.source.temperature)
                    ? Math.round(root.source.temperature) + "°" : "—"
                color: root.theme ? root.theme.foreground : "#e2e2e2"
                font.family: root.theme ? root.theme.clockFamily : "Iceberg"
                font.pixelSize: root.theme ? root.theme.dateSize + 4 : 21
            }

            Text {
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.source ? root.source.condition : ""
                color: root.theme
                    ? root.theme.alpha(root.theme.tertiary, 0.92) : "#c6c6c6"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize : 11
                font.letterSpacing: 0.2
            }
        }

        Row {
            spacing: 6
            visible: root.source && !isNaN(root.source.high) && !isNaN(root.source.low)

            Icon {
                height: 24
                theme: root.theme
                glyph: ""
                size: 10
                tint: root.theme ? root.theme.quiet : "#565656"
            }

            Text {
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.source && !isNaN(root.source.high)
                    ? Math.round(root.source.high) + "°" : ""
                color: root.theme ? root.theme.quiet : "#565656"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 10
            }

            Item { width: 3; height: 1 }

            Icon {
                height: 24
                theme: root.theme
                glyph: ""
                size: 10
                tint: root.theme ? root.theme.quiet : "#565656"
            }

            Text {
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: root.source && !isNaN(root.source.low)
                    ? Math.round(root.source.low) + "°" : ""
                color: root.theme ? root.theme.quiet : "#565656"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 10
            }
        }
    }
}
