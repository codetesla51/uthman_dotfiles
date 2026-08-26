import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PluginMenu — grid launcher for quickshell plugins.
// One fullscreen window + backdrop (PowerMenu pattern). Click a tile →
// ipc call <target> toggle via execDetached (canonical path, AGENTS §0).
PanelWindow {
    id: root

    property var colors
    property bool open: false

    // PLUGINS ONLY — native shell modules (launcher, wifi, battery, notifications,
    // power menu, theme, keybinds, calendar, sysmon, clipboard, fastfetch) do NOT
    // belong here; they have their own binds/pills. Add real extras below:
    // { name: "Example", desc: "what it does", target: "ipcTarget" },
    readonly property var plugins: [
        { name: "Quick Notes",   desc: "idea capture · draggable",    target: "notes" },
        { name: "Screen Time",   desc: "usage heatmaps · app ranks",  target: "screentime" },
        { name: "Phone Link",    desc: "send files · clipboard sync", target: "phonelink" }
    ]

    property string query: ""
    readonly property var filtered: {
        if (!query) return plugins
        var q = query.toLowerCase()
        var out = []
        for (var i = 0; i < plugins.length; i++)
            if (plugins[i].name.toLowerCase().indexOf(q) !== -1 || plugins[i].desc.toLowerCase().indexOf(q) !== -1)
                out.push(plugins[i])
        return out
    }
    function accents(i) {
        var a = [colors.primary, colors.secondary, colors.tertiary]
        return a[i % 3]
    }

    function launch(target) {
        Quickshell.execDetached(["quickshell", "-p", "/home/uthman/.config/quickshell",
                                 "ipc", "call", target, "toggle"])
        root.open = false
        query = ""
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true

    IpcHandler { target: "plugins"; function toggle(): void { root.open = !root.open } }

    // dim backdrop — same window as the card (single-window rule)
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.35 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: { root.open = false; root.query = "" } }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 468
        height: 560
        radius: 20
        color: colors.alpha(colors.background, 0.94)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // header
            Text {
                text: "PLUGINS"
                color: colors.primary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 13
                font.weight: Font.ExtraBold
                font.letterSpacing: 2
                Layout.alignment: Qt.AlignHCenter
            }

            // search
            TextField {
                visible: root.plugins.length > 0
                Layout.preferredHeight: visible ? implicitHeight : 0
                id: searchField
                Layout.fillWidth: true
                placeholderText: " type to filter…"
                placeholderTextColor: colors.alpha(colors.outline, 0.6)
                color: colors.foreground
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                background: Rectangle {
                    radius: 10
                    color: colors.alpha(colors.surfaceVariant, 0.30)
                    border.width: 1
                    border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.12)
                }
                onTextChanged: root.query = text
            }

            // grid — fixed viewport, scrolls when it overflows
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                GridView {
                    id: grid
                    model: root.filtered
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor(width / 3)
                    cellHeight: 104

                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 5
                            radius: 14
                            color: tileMa.containsMouse ? colors.alpha(colors.primary, 0.14)
                                                        : colors.alpha(colors.surfaceVariant, 0.18)
                            border.width: 1
                            border.color: tileMa.containsMouse ? colors.alpha(colors.primary, 0.35)
                                                               : colors.alpha(colors.outline, 0.08)

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 7
                                width: parent.width - 16

                                Rectangle {
                                    width: 30; height: 30; radius: 15
                                    color: colors.alpha(root.accents(index), 0.16)
                                    border.width: 1
                                    border.color: colors.alpha(root.accents(index), 0.45)
                                    Layout.alignment: Qt.AlignHCenter
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.name.charAt(0)
                                        color: root.accents(index)
                                        font.family: "FiraCode Nerd Font"
                                        font.pixelSize: 13
                                        font.weight: Font.ExtraBold
                                    }
                                }
                                Text {
                                    text: modelData.name
                                    color: colors.foreground
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    Layout.alignment: Qt.AlignHCenter
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: parent.width
                                }
                            }
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.launch(modelData.target)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: grid.count === 0
                        text: root.plugins.length === 0 ? "no plugins installed yet" : "no match"
                        color: colors.alpha(colors.outline, 0.5)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                    }
                }
            }
        }

        Keys.onEscapePressed: { root.open = false; root.query = "" }
        focus: root.open
    }
}
