import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// QuickNotes: small floating idea capture window.
// Opens from the PluginMenu tile (`ipc call notes toggle`).
// LocalStorage backed (qs_ideas). Pinned notes get a pastel colour and
// double as reminders (one digest notification per day).
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string searchQuery: ""
    property string editId: ""      // id of the note being edited, "" when adding

    title: "QuickNotes"
    implicitWidth: 440
    implicitHeight: 580
    minimumSize: Qt.size(400, 520)
    maximumSize: Qt.size(460, 600)
    color: "transparent"
    visible: root.open || closeAnim.running

    readonly property var noteColors: ["#f3d877", "#f2a7b5", "#a8d8b9", "#a7c7f0", "#c9b6ee"]
    readonly property string ink: "#241f12"
    readonly property color fill: colors.alpha(colors.foreground, 0.06)
    readonly property color fill2: colors.alpha(colors.foreground, 0.11)
    readonly property bool canSave: titleField.text.trim() !== "" || bodyField.text.trim() !== ""

    // ---- storage ----
    property var notes: []

    function db() { return LocalStorage.openDatabaseSync("qs_ideas", "1.0", "quick ideas", 100000) }

    function loadNotes() {
        db().transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, pinned INTEGER, created INTEGER)')
            var rs = tx.executeSql('SELECT * FROM notes ORDER BY pinned DESC, created DESC')
            var arr = []
            for (var i = 0; i < rs.rows.length; i++) {
                var r = rs.rows.item(i)
                arr.push({ id: r.id, title: r.title, body: r.body, pinned: r.pinned === 1, created: r.created })
            }
            notes = arr
        })
    }
    function saveNote(title, body) {
        if (!title.trim() && !body.trim()) return
        db().transaction(function(tx) {
            tx.executeSql('INSERT INTO notes(title,body,pinned,created) VALUES(?,?,0,?)', [title.trim(), body.trim(), Date.now()])
        })
        loadNotes()
    }
    function deleteNote(id) {
        db().transaction(function(tx) { tx.executeSql('DELETE FROM notes WHERE id=?', [id]) })
        if (String(id) === root.editId) cancelEdit()
        loadNotes()
    }
    function togglePin(id, pinned) {
        db().transaction(function(tx) { tx.executeSql('UPDATE notes SET pinned=? WHERE id=?', [pinned ? 1 : 0, id]) })
        loadNotes()
    }
    function updateNote(id, title, body) {
        db().transaction(function(tx) { tx.executeSql('UPDATE notes SET title=?, body=? WHERE id=?', [title, body, id]) })
        loadNotes()
    }

    // ---- composer ----
    function startEdit(note) {
        root.editId = String(note.id)
        titleField.text = note.title
        bodyField.text = note.body
        titleField.forceActiveFocus()
    }
    function cancelEdit() {
        root.editId = ""
        titleField.text = ""
        bodyField.text = ""
    }
    // Add a new note, or write the edit back when editId is set.
    function submit() {
        if (!canSave) return
        var t = titleField.text.trim(), b = bodyField.text.trim()
        if (root.editId !== "") updateNote(parseInt(root.editId), t, b)
        else saveNote(t, b)
        cancelEdit()
        titleField.forceActiveFocus()
    }
    // Esc cancels an edit first, then closes the window.
    function handleEscape() {
        if (root.editId !== "") cancelEdit()
        else root.open = false
    }

    Component.onCompleted: loadNotes()
    onOpenChanged: {
        if (open) { loadNotes(); Qt.callLater(function() { titleField.forceActiveFocus() }); openAnim.restart() }
        else closeAnim.restart()
    }

    readonly property var filtered: {
        if (searchQuery.trim() === "") return notes
        var q = searchQuery.toLowerCase()
        return notes.filter(function(n) { return (n.title + " " + n.body).toLowerCase().includes(q) })
    }

    function timeAgo(ts) {
        var d = Date.now() - ts
        if (d < 60000) return "now"
        if (d < 3600000) return Math.floor(d / 60000) + "m"
        if (d < 86400000) return Math.floor(d / 3600000) + "h"
        if (d < 604800000) return Math.floor(d / 86400000) + "d"
        return new Date(ts).toLocaleDateString()
    }

    // ---- daily reminder for pinned notes ----
    function metaGet(k) {
        var v = ""
        db().transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)')
            var rs = tx.executeSql('SELECT value FROM meta WHERE key=?', [k])
            if (rs.rows.length > 0) v = rs.rows.item(0).value
        })
        return v
    }
    function metaSet(k, v) {
        db().transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)')
            tx.executeSql('INSERT OR REPLACE INTO meta VALUES(?,?)', [k, v])
        })
    }
    function maybeRemind() {
        var today = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (root.metaGet("last_remind") === today) return
        var pinned = notes.filter(function(n) { return n.pinned })
        if (pinned.length === 0) return
        var names = pinned.slice(0, 3).map(function(n) { return n.title || "(no title)" })
        var body = names.join(" · ")
        if (pinned.length > 3) body += " · +" + (pinned.length - 3) + " more"
        Quickshell.execDetached(["notify-send", "-a", "QuickNotes", "Pinned ideas (" + pinned.length + ")", body])
        root.metaSet("last_remind", today)
    }
    Timer { id: remindTimer; interval: 3600000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.maybeRemind() }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 22
        color: colors.alpha(colors.surface, 0.62)
        focus: root.open
        Keys.onEscapePressed: root.handleEscape()

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Quick notes"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 16; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true
                    text: root.notes.length + (root.notes.length === 1 ? " idea" : " ideas")
                    color: colors.alpha(colors.foreground, 0.5)
                    font.family: colors.fontSans; font.pixelSize: 10
                }
                Rectangle {
                    implicitWidth: closeLabel.implicitWidth + 24; implicitHeight: 28; radius: 14
                    color: closeMa.containsMouse ? root.fill2 : root.fill
                    Text { id: closeLabel; anchors.centerIn: parent; text: "Close"; color: colors.alpha(colors.foreground, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            // search
            TextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 40
                leftPadding: 16; rightPadding: 16
                placeholderText: "Search ideas"
                placeholderTextColor: colors.alpha(colors.foreground, 0.4)
                color: colors.foreground
                font.family: colors.fontSans; font.pixelSize: 11
                selectByMouse: true
                background: Rectangle { radius: 20; color: searchField.activeFocus ? root.fill2 : root.fill }
                onTextChanged: root.searchQuery = text
            }

            // notes: pinned first, then the rest (the model is already sorted)
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index
                    // "Pinned" / "Ideas" label above the first note of each group, hidden while searching
                    readonly property bool showLabel: root.searchQuery.trim() === "" && (index === 0 || root.filtered[index - 1].pinned !== modelData.pinned)
                    readonly property color textColor: modelData.pinned ? root.ink : colors.foreground

                    width: list.width
                    height: (showLabel ? groupLabel.implicitHeight + 8 : 0) + noteCard.height

                    Text {
                        id: groupLabel
                        visible: item.showLabel
                        text: item.modelData.pinned ? "Pinned" : "Ideas"
                        color: colors.alpha(colors.foreground, 0.5)
                        font.family: colors.fontSans; font.pixelSize: 10
                    }

                    Rectangle {
                        id: noteCard
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: contentCol.implicitHeight + 24
                        radius: 16
                        color: item.modelData.pinned ? root.noteColors[item.modelData.id % 5] : (hover.hovered ? root.fill2 : root.fill)

                        HoverHandler { id: hover }
                        MouseArea {
                            anchors.fill: parent
                            onDoubleClicked: root.startEdit(item.modelData)
                        }

                        ColumnLayout {
                            id: contentCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 12 }
                            spacing: 4

                            // title row: time normally, actions on hover (fixed height, no jumping)
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                spacing: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: item.modelData.title || "(no title)"
                                    color: item.textColor
                                    font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    elide: Text.ElideRight; maximumLineCount: 1
                                }
                                Text {
                                    visible: !hover.hovered
                                    text: root.timeAgo(item.modelData.created)
                                    color: item.textColor; opacity: 0.55
                                    font.family: colors.fontSans; font.pixelSize: 9
                                }
                                Row {
                                    visible: hover.hovered
                                    spacing: 4
                                    Repeater {
                                        model: [
                                            { label: item.modelData.pinned ? "Unpin" : "Pin", act: "pin" },
                                            { label: "Edit", act: "edit" },
                                            { label: "Delete", act: "del" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: actLabel.implicitWidth + 18; height: 22; radius: 11
                                            color: actMa.containsMouse
                                                ? colors.alpha(item.modelData.pinned ? "#000000" : colors.foreground, 0.22)
                                                : colors.alpha(item.modelData.pinned ? "#000000" : colors.foreground, 0.12)
                                            Text { id: actLabel; anchors.centerIn: parent; text: parent.modelData.label; color: item.textColor; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Medium }
                                            MouseArea {
                                                id: actMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: {
                                                    if (parent.modelData.act === "pin") root.togglePin(item.modelData.id, !item.modelData.pinned)
                                                    else if (parent.modelData.act === "edit") root.startEdit(item.modelData)
                                                    else root.deleteNote(item.modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: item.modelData.body && item.modelData.body.length > 0
                                Layout.fillWidth: true
                                text: item.modelData.body
                                color: item.textColor; opacity: 0.78
                                font.family: colors.fontSans; font.pixelSize: 10
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.filtered.length === 0
                text: root.searchQuery === "" ? "No ideas yet. Capture one below." : "No matches"
                color: colors.alpha(colors.foreground, 0.5)
                font.family: colors.fontSans; font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }

            // composer: adds a note, or saves the one being edited
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    implicitHeight: 38
                    leftPadding: 14; rightPadding: 14
                    placeholderText: "Title, the idea in one line"
                    placeholderTextColor: colors.alpha(colors.foreground, 0.4)
                    color: colors.foreground
                    font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                    selectByMouse: true
                    background: Rectangle { radius: 14; color: titleField.activeFocus ? root.fill2 : root.fill }
                    onAccepted: bodyField.forceActiveFocus()
                }
                TextArea {
                    id: bodyField
                    Layout.fillWidth: true
                    implicitHeight: 64
                    leftPadding: 14; rightPadding: 14; topPadding: 10
                    placeholderText: "Details (optional)"
                    placeholderTextColor: colors.alpha(colors.foreground, 0.4)
                    color: colors.foreground
                    font.family: colors.fontSans; font.pixelSize: 10
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    background: Rectangle { radius: 14; color: bodyField.activeFocus ? root.fill2 : root.fill }
                    Keys.onPressed: function(event) {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                            root.submit()
                            event.accepted = true
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        visible: root.editId !== ""
                        implicitWidth: cancelLabel.implicitWidth + 36; implicitHeight: 40; radius: 20
                        color: cancelMa.containsMouse ? colors.alpha(colors.foreground, 0.18) : root.fill2
                        Text { id: cancelLabel; anchors.centerIn: parent; text: "Cancel"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11 }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.cancelEdit() }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40; radius: 20
                        color: root.canSave ? colors.primary : root.fill
                        opacity: root.canSave && addMa.containsMouse ? 0.9 : 1
                        Text {
                            anchors.centerIn: parent
                            text: root.editId !== "" ? "Save changes" : "Add idea"
                            color: root.canSave ? colors.background : colors.alpha(colors.foreground, 0.4)
                            font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        MouseArea { id: addMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.submit() }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Enter next field    CTRL Enter save    Esc close    double-click to edit"
                color: colors.alpha(colors.foreground, 0.4)
                font.family: colors.fontSans; font.pixelSize: 9
            }
        }
    }
}
