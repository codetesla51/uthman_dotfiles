import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// QuickNotes — small floating idea capture window.
// Opens from the PluginMenu tile (`ipc call notes toggle`).
// LocalStorage backed (qs_ideas). Glass Amber Bento card.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string searchQuery: ""
    property string editId: "" // id of note being edited

    title: "QuickNotes"
    implicitWidth: 440
    implicitHeight: 580
    minimumSize: Qt.size(400, 520)
    maximumSize: Qt.size(460, 600)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "notes"
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
    }

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
    function startEdit(modelData) {
        root.editId = modelData.id
        titleField.text = modelData.title
        bodyField.text = modelData.body
        titleField.forceActiveFocus()
    }
    function metaGet(k) {
        var v = ""
        db().transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)')
            var rs = tx.executeSql('SELECT value FROM meta WHERE key=?', [k])
            if(rs.rows.length > 0) v = rs.rows.item(0).value
        })
        return v
    }
    function metaSet(k, v) {
        db().transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)')
            tx.executeSql('INSERT OR REPLACE INTO meta VALUES(?,?)', [k, v])
        })
    }
    // pinned notes act as reminders: one digest notification per day
    function maybeRemind() {
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if(root.metaGet("last_remind") === today) return
        var pinned = notes.filter(function(n){ return n.pinned })
        if(pinned.length === 0) return
        var names = pinned.slice(0, 3).map(function(n){ return n.title || "(no title)" })
        var body = names.join(" · ")
        if(pinned.length > 3) body += " · +" + (pinned.length - 3) + " more"
        Quickshell.execDetached(["notify-send", "-a", "QuickNotes", "Pinned ideas (" + pinned.length + ")", body])
        root.metaSet("last_remind", today)
    }
    Timer { id: remindTimer; interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.maybeRemind() }

    // window glass
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        color: colors.alpha(colors.background, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ---- header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: "󰎚"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "QUICK NOTES"
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.3
                    Layout.alignment: Qt.AlignVCenter
                }
                Rectangle {
                    width: countText.implicitWidth+12
                    height: 20
                    radius: 10
                    color: colors.alpha(colors.primary, 0.14)
                    border.width: 1
                    border.color: colors.alpha(colors.primary, 0.25)
                    Layout.alignment: Qt.AlignVCenter
                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: notes.length+""
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            // search
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 12
                color: colors.alpha(colors.surface, 0.6)
                border.width: 1
                border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.15)
                Behavior on border.color { ColorAnimation { duration: 150 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    Text { text: ""; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 12; Layout.alignment: Qt.AlignVCenter }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: "Search ideas…"
                        placeholderTextColor: colors.alpha(colors.outline,0.5)
                        color: colors.foreground
                        font.family: colors.fontSans; font.pixelSize: 11
                        background: null
                        selectByMouse: true
                        onTextChanged: root.searchQuery = text
                    }
                }
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
                    color: modelData.pinned ? colors.alpha(colors.primary, 0.10) : delMa.containsMouse ? colors.alpha(colors.surfaceVariant,0.35) : colors.alpha(colors.surface,0.45)
                    border.width: 1
                    border.color: modelData.pinned ? colors.alpha(colors.primary, 0.5) : delMa.containsMouse?colors.alpha(colors.primary,0.18):colors.alpha(colors.outline,0.12)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // click-catcher FIRST (bottom) so the action buttons on top receive clicks
                    MouseArea {
                        id: delMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onDoubleClicked: root.startEdit(modelData)
                    }

                    ColumnLayout {
                        id: contentCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        anchors.leftMargin: 14
                        anchors.rightMargin: 92
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: modelData.title || "(no title)"
                                color: colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                elide: Text.ElideRight; Layout.fillWidth: true
                                maximumLineCount: 1
                            }
                            Text {
                                visible: modelData.pinned
                                text: "PINNED"
                                color: colors.primary
                                font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.0
                            }
                            Text {
                                text: root.timeAgo(modelData.created)
                                color: colors.alpha(colors.outline,0.55)
                                font.family: colors.fontSans; font.pixelSize: 8
                            }
                        }
                        Text {
                            visible: modelData.body && modelData.body.length>0
                            text: modelData.body
                            color: colors.alpha(colors.foreground,0.75)
                            font.family: colors.fontSans; font.pixelSize: 10
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // hover actions — declared LAST (top) so clicks land on the buttons
                    Row {
                        visible: delMa.containsMouse || pinMa.containsMouse || editMa.containsMouse || trashMa.containsMouse
                        anchors { right: parent.right; top: parent.top; margins: 6 }
                        spacing: 4
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: pinMa.containsMouse?colors.alpha(colors.primary,0.2):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: ""; color: modelData.pinned?colors.primary:colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize:10; rotation: modelData.pinned?0:45 }
                            MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.togglePin(modelData.id, !modelData.pinned) }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: editMa.containsMouse?colors.alpha(colors.primary,0.15):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: ""; color: colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize:10 }
                            MouseArea { id: editMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.startEdit(modelData) }
                        }
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: trashMa.containsMouse?colors.alpha(colors.error,0.18):colors.alpha(colors.surfaceVariant,0.3)
                            Text { anchors.centerIn: parent; text: "󰆴"; color: trashMa.containsMouse?colors.error:colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize:10 }
                            MouseArea { id: trashMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.deleteNote(modelData.id) }
                        }
                    }
                }
            }

            Text {
                visible: root.filtered.length===0
                text: searchQuery==="" ? "No ideas yet — capture one below" : "No matches"
                color: colors.alpha(colors.outline,0.55)
                font.family: colors.fontSans; font.pixelSize: 10
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
                        font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
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
                        Text { anchors.centerIn: parent; text: "Cancel"; color: colors.alpha(colors.foreground,0.8); font.family: colors.fontSans; font.pixelSize:9; font.weight: Font.Bold }
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
                    font.family: colors.fontSans; font.pixelSize: 10
                    wrapMode: TextArea.Wrap
                    background: Rectangle {
                        radius: 10
                        color: colors.alpha(colors.surface,0.7)
                        border.width: 1; border.color: bodyField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                    }
                }
                Rectangle {
                    id: addBtn
                    Layout.fillWidth: true
                    height: 36; radius: 10
                    scale: addMa.containsMouse ? 1.02 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.primary : colors.alpha(colors.surfaceVariant,0.35)
                    border.width: 1; border.color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.primary : colors.alpha(colors.outline,0.12)
                    opacity: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? 1 : 0.6
                    Text {
                        anchors.centerIn: parent
                        text: root.editId!=="" ? "Save changes" : "Add idea  ↵"
                        color: (titleField.text.trim()!=="" || bodyField.text.trim()!=="") ? colors.background : colors.alpha(colors.outline,0.7)
                        font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5
                    }
                    MouseArea {
                        id: addMa
                        anchors.fill: parent
                        hoverEnabled: true
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
                text: "↵ save  •  esc close  •  double-click note to edit"
                color: colors.alpha(colors.outline,0.4)
                font.family: colors.fontSans; font.pixelSize: 7; font.letterSpacing: 0.3
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
