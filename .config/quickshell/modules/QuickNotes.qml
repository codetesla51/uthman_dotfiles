import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// QuickNotes — small draggable idea capture window
// SUPER+I to toggle. Drag via header. LocalStorage backed (qs_ideas).
// Glassmorphic, matches bar: surface@0.55, primary accents, 14-18 radii.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string searchQuery: ""
    property string editId: "" // id of note being edited
    property string draftTitle: ""
    property string draftBody: ""

    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-notes"

    IpcHandler { target: "notes"; function toggle(): void { root.open = !root.open } }

    // ---- storage ----
    property var notes: []

    function db() { return LocalStorage.openDatabaseSync("qs_ideas", "1.0", "quick ideas", 100000) }

    function loadNotes() {
        var d = db()
        d.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, pinned INTEGER, created INTEGER)')
            var rs = tx.executeSql('SELECT * FROM notes ORDER BY pinned DESC, created DESC')
            var arr = []
            for (var i=0;i<rs.rows.length;i++) {
                var r = rs.rows.item(i)
                arr.push({id: r.id, title: r.title, body: r.body, pinned: r.pinned===1, created: r.created})
            }
            notes = arr
        })
    }
    function saveNote(title, body) {
        if (!title.trim() && !body.trim()) return
        var d = db()
        var now = Date.now()
        d.transaction(function(tx){
            tx.executeSql('INSERT INTO notes(title,body,pinned,created) VALUES(?,?,0,?)', [title.trim(), body.trim(), now])
        })
        loadNotes()
    }
    function deleteNote(id) {
        var d=db(); d.transaction(function(tx){ tx.executeSql('DELETE FROM notes WHERE id=?', [id]) })
        loadNotes()
    }
    function togglePin(id, pinned) {
        var d=db(); d.transaction(function(tx){ tx.executeSql('UPDATE notes SET pinned=? WHERE id=?', [pinned?1:0, id]) })
        loadNotes()
    }
    function updateNote(id, title, body) {
        var d=db(); d.transaction(function(tx){ tx.executeSql('UPDATE notes SET title=?, body=? WHERE id=?', [title, body, id]) })
        loadNotes()
    }

    Component.onCompleted: loadNotes()
    onOpenChanged: if (open) { loadNotes(); Qt.callLater(function(){ titleField.forceActiveFocus() }) }

    // filtered by search
    readonly property var filtered: {
        if (searchQuery.trim()==="") return notes
        var q = searchQuery.toLowerCase()
        return notes.filter(function(n){ return (n.title+" "+n.body).toLowerCase().includes(q) })
    }

    function timeAgo(ts) {
        var d = Date.now()-ts
        if (d<60000) return "now"
        if (d<3600000) return Math.floor(d/60000)+"m"
        if (d<86400000) return Math.floor(d/3600000)+"h"
        if (d<604800000) return Math.floor(d/86400000)+"d"
        return new Date(ts).toLocaleDateString()
    }

    // backdrop
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open?0.35:0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open=false }
    }

    // draggable card — centered, glass, small
    Rectangle {
        id: card
        width: 440
        height: 560
        radius: 18
        color: colors.alpha(colors.background, 0.94)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.22)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: dragArea.drag.active ? 0 : 0
        opacity: root.open?1:0
        scale: root.open?1:0.96
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        focus: root.open
        Keys.onEscapePressed: root.open=false

        // subtle shadow
        layer.enabled: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ---- header (drag handle) ----
            Item {
                id: header
                Layout.fillWidth: true
                height: 36
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    Text {
                        text: "󰎚 ideas"
                        color: colors.foreground
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 0.5
                    }
                    Rectangle {
                        width: countText.implicitWidth+12
                        height: 20
                        radius: 10
                        color: colors.alpha(colors.primary, 0.14)
                        border.width: 1
                        border.color: colors.alpha(colors.primary, 0.25)
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: notes.length+""
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // pin filter hint
                    Text {
                        text: "drag header to move"
                        color: colors.alpha(colors.outline, 0.45)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 8
                        visible: !dragArea.drag.active
                    }
                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: closeMa.containsMouse ? colors.alpha(colors.error, 0.12) : "transparent"
                        Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.error:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize:13 }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                    }
                }
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    drag.target: card
                    drag.axis: Drag.XAndYAxis
                    drag.threshold: 4
                    // keep within window bounds
                    onPressed: card.anchors.horizontalCenter = undefined, card.anchors.verticalCenter = undefined
                    // reset on release? keep position
                }
            }

            // search
            TextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 34
                leftPadding: 12; rightPadding: 12
                placeholderText: "Search ideas…"
                placeholderTextColor: colors.alpha(colors.outline,0.5)
                color: colors.foreground
                font.family: "FiraCode Nerd Font"; font.pixelSize: 11
                background: Rectangle {
                    radius: 10
                    color: colors.alpha(colors.surface,0.7)
                    border.width: 1; border.color: searchField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                }
                onTextChanged: root.searchQuery = text
            }

            // list
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width
                    height: contentCol.implicitHeight+20
                    radius: 12
                    color: delMa.containsMouse ? colors.alpha(colors.surfaceVariant,0.35) : colors.alpha(colors.surface,0.45)
                    border.width: 1
                    border.color: modelData.pinned ? colors.alpha(colors.primary,0.35) : delMa.containsMouse?colors.alpha(colors.primary,0.18):colors.alpha(colors.outline,0.12)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // left accent
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: 0 }
                        width: 3; radius: 12
                        color: modelData.pinned ? colors.primary : colors.alpha(colors.primary, delMa.containsMouse?0.5:0.0)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    ColumnLayout {
                        id: contentCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        anchors.leftMargin: 14
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: modelData.title || "(no title)"
                                color: colors.foreground
                                font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold
                                elide: Text.ElideRight; Layout.fillWidth: true
                                maximumLineCount: 1
                            }
                            Text {
                                text: root.timeAgo(modelData.created)
                                color: colors.alpha(colors.outline,0.55)
                                font.family: "FiraCode Nerd Font"; font.pixelSize: 8
                            }
                        }
                        Text {
                            visible: modelData.body && modelData.body.length>0
                            text: modelData.body
                            color: colors.alpha(colors.foreground,0.75)
                            font.family: "FiraCode Nerd Font"; font.pixelSize: 10
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // hover actions
                    Row {
                        visible: delMa.containsMouse
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        spacing: 4
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: pinMa.containsMouse?colors.alpha(colors.primary,0.2):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: modelData.pinned ? "" : ""; color: modelData.pinned?colors.primary:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize:10; rotation: modelData.pinned?0:45 }
                            MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.togglePin(modelData.id, !modelData.pinned) }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: editMa.containsMouse?colors.alpha(colors.primary,0.15):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: "󰉁"; color: colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize:10 }
                            MouseArea { id: editMa; anchors.fill: parent; hoverEnabled:true; onClicked: {
                                root.editId = modelData.id; titleField.text = modelData.title; bodyField.text = modelData.body; titleField.forceActiveFocus()
                            } }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: trashMa.containsMouse?colors.alpha(colors.error,0.18):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: "󰆴"; color: trashMa.containsMouse?colors.error:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize:10 }
                            MouseArea { id: trashMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.deleteNote(modelData.id) }
                        }
                    }

                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onDoubleClicked: { root.editId = modelData.id; titleField.text = modelData.title; bodyField.text = modelData.body }
                    }
                }
            }

            Text {
                visible: root.filtered.length===0
                text: searchQuery==="" ? "No ideas yet — capture one below" : "No matches"
                color: colors.alpha(colors.outline,0.55)
                font.family: "FiraCode Nerd Font"; font.pixelSize: 10
                Layout.alignment: Qt.AlignHCenter
            }

            // divider
            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline,0.12) }

            // add / edit area
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextField {
                        id: titleField
                        Layout.fillWidth: true
                        implicitHeight: 36
                        leftPadding: 12; rightPadding: 12
                        placeholderText: "Title (idea in one line)…"
                        placeholderTextColor: colors.alpha(colors.outline,0.5)
                        color: colors.foreground
                        font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold
                        background: Rectangle {
                            radius: 10
                            color: colors.alpha(colors.surface,0.7)
                            border.width: 1; border.color: titleField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                        }
                        onAccepted: bodyField.forceActiveFocus()
                    }
                    Rectangle {
                        visible: root.editId!==""
                        width: 60; height: 36; radius: 10
                        color: cancelMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                        border.width: 1; border.color: colors.alpha(colors.outline,0.15)
                        Text { anchors.centerIn: parent; text: "Cancel"; color: colors.alpha(colors.foreground,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize:9; font.weight: Font.Bold }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled:true; onClicked: { root.editId=""; titleField.text=""; bodyField.text="" } }
                    }
                }
                TextArea {
                    id: bodyField
                    Layout.fillWidth: true
                    implicitHeight: 56
                    placeholderText: "Details… (optional)"
                    placeholderTextColor: colors.alpha(colors.outline,0.5)
                    color: colors.foreground
                    font.family:"FiraCode Nerd Font"; font.pixelSize: 10
                    wrapMode: TextArea.Wrap
                    background: Rectangle {
                        radius: 10
                        color: colors.alpha(colors.surface,0.7)
                        border.width: 1; border.color: bodyField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 36; radius: 10
                    color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.primary : colors.alpha(colors.surfaceVariant,0.35)
                    border.width: 1; border.color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.primary : colors.alpha(colors.outline,0.12)
                    opacity: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? 1 : 0.6
                    Text {
                        anchors.centerIn: parent
                        text: root.editId!=="" ? "Save changes" : "Add idea  ↵"
                        color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.background : colors.alpha(colors.outline,0.7)
                        font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var t=titleField.text.trim(), b=bodyField.text.trim()
                            if (t==="" && b==="") return
                            if (root.editId!=="") { root.updateNote(root.editId, t, b); root.editId="" }
                            else root.saveNote(t,b)
                            titleField.text=""; bodyField.text=""; titleField.forceActiveFocus()
                        }
                    }
                }
            }

            Text {
                text: "↵ save  •  esc close  •  drag header to move  •  double-click note to edit"
                color: colors.alpha(colors.outline,0.4)
                font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.letterSpacing: 0.3
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
