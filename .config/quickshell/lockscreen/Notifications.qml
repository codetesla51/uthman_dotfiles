import QtQuick

// Notifications — the bar's archive, right bottom. Three at most, no cards:
// app and time on one quiet line, summary under it. The heading pins to the
// top of the block and the rows to the bottom, so it lines up with the music
// block on the other side.
Item {
    id: root

    property var theme
    property var items: []
    property int maxItems: 3

    readonly property int visibleCount: root.items
        ? Math.min(root.items.length, root.maxItems) : 0

    Item {
        id: headingRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 18

        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            spacing: 7

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                glyph: ""
                size: 12
                tint: root.theme
                    ? root.theme.alpha(root.theme.primary, 0.8) : "#8c8c8c"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Recent"
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.headingSize : 10
                font.letterSpacing: root.theme ? root.theme.headingTracking : 1.4
                font.weight: Font.DemiBold
            }
        }

        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            visible: root.items && root.items.length > root.maxItems
            text: root.items
                ? "+" + (root.items.length - root.maxItems) + " earlier" : ""
            color: root.theme ? root.theme.quiet : "#565656"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.tinySize : 9
        }
    }

    Column {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 10

        Repeater {
            model: root.visibleCount

            delegate: Item {
                id: entryRow
                width: parent.width
                height: root.theme ? root.theme.notificationRowHeight : 40
                property var entry: root.items && index < root.items.length
                    ? root.items[index] : ({})

                Text {
                    id: app
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: entryRow.entry.appName || "app"
                    color: entryRow.entry.urgent
                        ? (root.theme ? root.theme.error : "#ffb4ab")
                        : (root.theme ? root.theme.muted : "#8c8c8c")
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.tinySize : 9
                    font.letterSpacing: 0.3
                }

                Text {
                    anchors.right: parent.right
                    anchors.baseline: app.baseline
                    text: entryRow.entry.time || ""
                    color: root.theme ? root.theme.quiet : "#565656"
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.tinySize : 9
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: app.bottom
                    anchors.topMargin: 5
                    text: entryRow.entry.summary || entryRow.entry.body || ""
                    color: root.theme ? root.theme.foreground : "#e2e2e2"
                    font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                    font.pixelSize: root.theme ? root.theme.bodySize - 1 : 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Row {
            visible: root.visibleCount === 0
            spacing: 8

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                glyph: ""
                size: 13
                tint: root.theme ? root.theme.quiet : "#565656"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Nothing new"
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.bodySize : 13
            }
        }
    }
}