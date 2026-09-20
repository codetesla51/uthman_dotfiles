import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PluginMenu — launcher for quickshell extras.
// One fullscreen window + backdrop (PowerMenu pattern). Click a tile →
// ipc call <target> toggle via execDetached (canonical path, AGENTS §0).
PanelWindow {
    id: root

    property var colors
    property bool open: false
    property int selected: 0
    property bool allowHover: false

    // PLUGINS ONLY — native shell modules (launcher, wifi, battery, notifications,
    // power menu, theme, keybinds, calendar, sysmon, clipboard, fastfetch) do NOT
    // belong here; they have their own binds/pills. Add real extras below:
    // { name: "Example", desc: "what it does", target: "ipcTarget", glyph: "X" },
    readonly property var plugins: [
        { name: "Pomodoro",      desc: "focus timer · stats",         target: "pomodoro",    glyph: "󰅐" },
        { name: "GitHub",        desc: "notifs · PRs · heatmap",      target: "github",      glyph: "󰊤" },
        { name: "Quick Notes",   desc: "idea capture · draggable",    target: "notes",       glyph: "󰎚" },
        { name: "Screen Time",   desc: "usage heatmaps · app ranks",  target: "screentime",  glyph: "󰓅" },
        { name: "PhoneBridge",   desc: "send & pull files over ADB",  target: "phonebridge", glyph: "" },
        { name: "Drive Health",  desc: "SMART + RAM + speed test",    target: "drives",      glyph: "󰍛" },
        { name: "FailWatch",     desc: "failed units · journal errors", target: "failwatch", glyph: "!" },
        { name: "Dictionary",    desc: "definitions · synonyms · audio", target: "dict", glyph: "" },
        { name: "Grap",          desc: "instant file search · grep", target: "grap", glyph: "" }
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
        Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell",
                                 "ipc", "call", target, "toggle"])
        root.open = false
        query = ""
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-plugins"

    IpcHandler { target: "plugins"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: {
        if (open) {
            query = ""
            selected = 0
            allowHover = false
            searchField.text = ""
            Qt.callLater(function(){ searchField.forceActiveFocus() })
        }
    }
    onFilteredChanged: selected = 0

    // dim backdrop — same window as the card (single-window rule)
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.45 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: { root.open = false; root.query = "" } }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 580
        height: 560
        radius: 20
        color: colors.alpha(colors.background, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // header — chip + label + count + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "PLUGINS"
                    color: colors.primary
                    font.family: colors.fontSans
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 2
                    Layout.alignment: Qt.AlignVCenter
                }
                Rectangle {
                    Layout.preferredWidth: countTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.primary, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { id: countTxt; anchors.centerIn: parent; text: root.filtered.length + " plugins"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.open = false; root.query = "" } }
                }
            }

            Text {
                text: "EXTRAS & UTILITIES"
                color: colors.alpha(colors.outline, 0.55)
                font.family: colors.fontSans
                font.pixelSize: 7
                font.weight: Font.Bold
                font.letterSpacing: 1.3
            }

            // search
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                radius: 12
                color: colors.alpha(colors.surface, 0.6)
                border.width: 1
                border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.15)
                Behavior on border.color { ColorAnimation { duration: 150 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 10
                    Text { text: ""; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: "Search plugins…"
                        placeholderTextColor: colors.alpha(colors.outline, 0.5)
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 13
                        background: null
                        selectByMouse: true
                        onTextChanged: root.query = text
                        Keys.onPressed: function(e){
                            if (e.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 2, root.filtered.length - 1); e.accepted = true }
                            else if (e.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 2, 0); e.accepted = true }
                            else if (e.key === Qt.Key_Escape) { root.open = false; root.query = ""; e.accepted = true }
                            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                var it = root.filtered[root.selected]
                                if (it) root.launch(it.target)
                                e.accepted = true
                            }
                        }
                    }
                    Text {
                        visible: searchField.text !== ""
                        text: "󰅖"
                        color: clearMa.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 13
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: { searchField.text = ""; root.query = "" } }
                    }
                }
            }

            // grid — 2-col bento cards with glyph + name + desc + arrow
            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filtered
                currentIndex: root.selected
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / 2)
                cellHeight: 112
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: tile
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: 14
                        y: (index === root.selected || tileMa.containsMouse) ? -2 : 0
                        scale: (index === root.selected || tileMa.containsMouse) ? 1.03 : 1
                        color: (index === root.selected || tileMa.containsMouse) ? colors.alpha(colors.primary, 0.14)
                                            : colors.alpha(colors.surfaceVariant, 0.18)
                        border.width: 1
                        border.color: (index === root.selected || tileMa.containsMouse) ? colors.alpha(colors.primary, 0.35)
                                                               : colors.alpha(colors.outline, 0.08)
                        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 140 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12
                            Rectangle {
                                width: 38; height: 38; radius: 19
                                color: colors.alpha(root.accents(index), 0.16)
                                border.width: 1
                                border.color: colors.alpha(root.accents(index), 0.45)
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.glyph
                                    color: root.accents(index)
                                    font.family: colors.fontSans
                                    font.pixelSize: 15
                                    font.weight: Font.ExtraBold
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Text {
                                    text: modelData.name
                                    color: colors.foreground
                                    font.family: colors.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.desc
                                    color: colors.alpha(colors.outline, 0.7)
                                    font.family: colors.fontSans
                                    font.pixelSize: 8
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            Text {
                                text: "→"
                                color: (index === root.selected || tileMa.containsMouse) ? colors.primary : colors.alpha(colors.outline, 0.5)
                                font.family: colors.fontSans
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    MouseArea {
                        id: tileMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (root.allowHover) root.selected = index
                        onPositionChanged: if (!root.allowHover) root.allowHover = true
                        onClicked: root.launch(modelData.target)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: grid.count === 0
                    text: root.plugins.length === 0 ? "no plugins installed yet" : "no match"
                    color: colors.alpha(colors.outline, 0.5)
                    font.family: colors.fontSans
                    font.pixelSize: 10
                }
            }

            // footer hint
            Text {
                text: "↑↓←→ navigate  •  ↵ open  •  esc close"
                color: colors.alpha(colors.outline, 0.45)
                font.family: colors.fontSans
                font.pixelSize: 8
                Layout.alignment: Qt.AlignHCenter
            }
        }

        Keys.onPressed: function(e){
            if (e.key === Qt.Key_Escape) { root.open = false; root.query = ""; e.accepted = true }
            else if (e.key === Qt.Key_Left) { root.selected = Math.max(root.selected - 1, 0); grid.positionViewAtIndex(root.selected, GridView.Contain); e.accepted = true }
            else if (e.key === Qt.Key_Right) { root.selected = Math.min(root.selected + 1, root.filtered.length - 1); grid.positionViewAtIndex(root.selected, GridView.Contain); e.accepted = true }
            else if (e.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 2, 0); grid.positionViewAtIndex(root.selected, GridView.Contain); e.accepted = true }
            else if (e.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 2, root.filtered.length - 1); grid.positionViewAtIndex(root.selected, GridView.Contain); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                var it = root.filtered[root.selected]
                if (it) root.launch(it.target)
                e.accepted = true
            }
        }
        focus: root.open
    }
}
