import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.LocalStorage 2.0
import Quickshell
import Quickshell.Io

// Clipboard Manager: history from cliphist plus 9 pinned notes.
//   SUPER CTRL V   open the window
//   SUPER CTRL P   pin whatever is on the clipboard right now
// Click any pinned note to copy it. There are no global paste shortcuts.
// In the window: type to filter, Up/Down move, Enter copies, CTRL P pins
// the selected clip, Delete drops it, Esc clears the search then closes.
// Drag a text clip or a note onto another note to pin/swap it there.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string filter: ""
    property var entries: []                  // {id, preview, isImage}
    property var pins: ["","","","","","","","",""]   // index 0 = slot 1, "" = empty

    title: "Clipboard"
    implicitWidth: 620
    implicitHeight: 680
    minimumSize: Qt.size(560, 600)
    maximumSize: Qt.size(660, 730)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here, Bar.qml owns targets "clipboard" and "sticky".

    readonly property var noteColors: ["#f3d877", "#f2a7b5", "#a8d8b9", "#a7c7f0", "#c9b6ee"]
    readonly property color fill: colors.alpha(colors.foreground, 0.06)
    readonly property color fill2: colors.alpha(colors.foreground, 0.11)

    // ---- cursor: pinned notes first (in slot order), then history ----
    property int cursor: 0
    property bool allowHover: false

    readonly property var filtered: {
        if (filter.trim() === "") return entries
        var q = filter.trim().toLowerCase()
        return entries.filter(function(e) { return e.preview.toLowerCase().includes(q) })
    }
    // only the filled slots, as {slot, text}
    readonly property var pinnedList: {
        var list = []
        for (var i = 0; i < 9; i++)
            if (pins[i] !== "") list.push({ slot: i + 1, text: pins[i] })
        return list
    }
    // the pinned board hides while searching so matches are not buried
    readonly property bool boardVisible: filter.trim() === ""
    readonly property int pinnedCount: boardVisible ? pinnedList.length : 0
    readonly property int total: pinnedCount + filtered.length

    function pinnedIndex(slot) {
        for (var i = 0; i < pinnedList.length; i++)
            if (pinnedList[i].slot === slot) return i
        return -1
    }
    function moveCursor(step) {
        cursor = Math.max(0, Math.min(total - 1, cursor + step))
        if (cursor < pinnedCount) pinList.positionViewAtIndex(cursor, ListView.Contain)
        else clipList.positionViewAtIndex(cursor - pinnedCount, ListView.Contain)
    }
    function entryAtCursor() { return cursor >= pinnedCount ? filtered[cursor - pinnedCount] : null }
    function copyCursor() {
        if (cursor < pinnedCount) copyPin(pinnedList[cursor].slot)
        else if (entryAtCursor()) copyEntry(entryAtCursor().id)
    }
    function pinCursor() { if (entryAtCursor()) pinEntry(entryAtCursor()) }
    function deleteCursor() {
        if (cursor < pinnedCount) setPin(pinnedList[cursor].slot, "")
        else if (entryAtCursor()) deleteEntry(entryAtCursor().id)
    }

    // ---- history ----
    function refresh() { listProc.running = true }
    function notify(msg) { Quickshell.execDetached(["notify-send", "-u", "low", "-a", "Clipboard", "Clipboard", msg]) }
    function copyEntry(id) {
        Quickshell.execDetached(["sh", "-c", "cliphist decode " + id + " | wl-copy && notify-send -u low -a 'Clipboard' 'Clipboard' 'Copied'"])
        root.open = false
    }
    function deleteEntry(id) {
        Quickshell.execDetached(["sh", "-c", "cliphist delete " + id + " 2>/dev/null"])
        entries = entries.filter(function(e) { return e.id !== id })
    }
    function clearAll() {
        Quickshell.execDetached(["sh", "-c", "cliphist wipe 2>/dev/null; notify-send -u low -a 'Clipboard' 'Clipboard' 'Cleared'"])
        entries = []
    }

    // ---- pins (LocalStorage, table pins(slot, text); survives cliphist wipes) ----
    function db() { return LocalStorage.openDatabaseSync("qs_stickies", "1.0", "clipboard stickies", 200000) }

    function loadPins() {
        db().transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pins(slot INTEGER PRIMARY KEY, text TEXT)")
            var rs = tx.executeSql("SELECT slot, text FROM pins")
            var arr = ["","","","","","","","",""]
            for (var i = 0; i < rs.rows.length; i++) arr[rs.rows.item(i).slot - 1] = rs.rows.item(i).text
            root.pins = arr
        })
    }
    // text "" empties the slot
    function savePin(slot, text) {
        db().transaction(function(tx) {
            if (text === "") tx.executeSql("DELETE FROM pins WHERE slot=?", [slot])
            else tx.executeSql("INSERT OR REPLACE INTO pins(slot, text) VALUES(?,?)", [slot, text])
        })
    }
    function setPin(slot, text) { savePin(slot, text); loadPins() }
    function swapPins(a, b) {
        var ta = pins[a - 1], tb = pins[b - 1]
        savePin(a, tb); savePin(b, ta); loadPins()
    }
    // pin into a chosen slot (drag) or the first free one (button, CTRL P)
    function pinText(text, slot) {
        var t = text.trim()
        if (!t) return
        if (pins.indexOf(t) >= 0) { notify("Already pinned"); return }
        var target = slot > 0 ? slot : pins.indexOf("") + 1
        if (target < 1) { notify("All 9 slots are full"); return }
        setPin(target, t)
    }
    function pinEntry(e) {
        if (e.isImage) notify("Images can't be pinned yet")
        else pinEntryById(e.id, 0)
    }
    function pinEntryById(id, slot) {
        if (pinDecodeProc.running) return
        pinDecodeProc.targetSlot = slot
        pinDecodeProc.command = ["sh", "-c", "cliphist decode " + id]
        pinDecodeProc.running = true
    }
    function addStickyFromClipboard() { captureProc.running = true }
    function clearStickies() { db().transaction(function(tx) { tx.executeSql("DELETE FROM pins") }); loadPins() }

    function copyText(text, label) {
        var esc = text.replace(/'/g, "'\\''")
        Quickshell.execDetached(["sh", "-c", "printf '%s' '" + esc + "' | wl-copy && notify-send -u low -a 'Clipboard' '" + label + "' 'Copied'"])
        if (root.open) root.open = false
    }
    function copyPin(slot) { if (pins[slot - 1] !== "") copyText(pins[slot - 1], "Note " + slot) }
    function copyStickyBySlot(slot) {
        var n = parseInt(slot)
        if (!isNaN(n) && n >= 1 && n <= 9) copyPin(n)
    }

    // ---- drag and drop (one ghost for every source) ----
    property bool dragging: false
    property string dragText: ""
    property int dragFromSlot: 0              // 0 = dragged from history
    property string dragClipId: ""            // history drag: decode the full clip on drop
    property point dragPos: Qt.point(0, 0)    // in card coordinates
    property int hoverSlot: 0

    function slotAt(x, y) {
        if (!boardVisible) return 0
        for (var i = 0; i < root.pinnedList.length; i++) {
            var cell = pinList.itemAtIndex(i)
            if (!cell) continue
            var p = cell.mapFromItem(card, x, y)
            if (p.x >= 0 && p.y >= 0 && p.x <= cell.width && p.y <= cell.height)
                return root.pinnedList[i].slot
        }
        return 0
    }
    function beginDrag(text, fromSlot, clipId) {
        dragText = text
        dragFromSlot = fromSlot
        dragClipId = clipId || ""
        dragging = true
    }
    function moveDrag(scenePos) {
        dragPos = card.mapFromItem(null, scenePos.x, scenePos.y)
        hoverSlot = slotAt(dragPos.x, dragPos.y)
    }
    function endDrag() {
        if (hoverSlot > 0) {
            if (dragFromSlot > 0) {
                if (dragFromSlot !== hoverSlot) swapPins(dragFromSlot, hoverSlot)
            } else if (dragClipId !== "") {
                pinEntryById(dragClipId, hoverSlot)
            } else {
                pinText(dragText, hoverSlot)
            }
        }
        dragging = false
        dragClipId = ""
        hoverSlot = 0
    }
    component DragSource: DragHandler {
        required property string payload
        property int fromSlot: 0
        property string clipId: ""
        target: null
        onActiveChanged: active ? root.beginDrag(payload, fromSlot, clipId) : root.endDrag()
        onCentroidChanged: if (active) root.moveDrag(centroid.scenePosition)
    }

    onOpenChanged: {
        if (open) {
            filter = ""; filterField.text = ""; cursor = 0; allowHover = false
            refresh(); loadPins()
            Qt.callLater(function() { filterField.forceActiveFocus() })
            openAnim.restart()
        } else closeAnim.restart()
    }
    onFilterChanged: cursor = 0
    onEntriesChanged: cursor = 0
    onPinsChanged: cursor = 0
    Component.onCompleted: loadPins()

    Process {
        id: listProc
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -n 50"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var arr = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    var tab = line.indexOf("\t")
                    if (!line.trim() || tab < 0) continue
                    var preview = line.substring(tab + 1).trim()
                    arr.push({ id: line.substring(0, tab).trim(), preview: preview, isImage: preview.startsWith("[[ binary data") })
                }
                root.entries = arr
            }
        }
    }

    // pin whatever is on the live clipboard (single process, no temp file)
    Process {
        id: captureProc
        command: ["sh", "-c", "wl-paste --no-newline 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var body = text.replace(/\s+$/, "")
                if (body.trim()) root.pinText(body, 0)
                else root.notify("Clipboard is empty")
            }
        }
    }

    // `cliphist list` only gives a preview. Pin the decoded clip so long text
    // is stored and copied in full instead of being cut at the preview.
    Process {
        id: pinDecodeProc
        property int targetSlot: 0
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var body = text.replace(/\s+$/, "")
                if (body.trim()) root.pinText(body, pinDecodeProc.targetSlot)
                else root.notify("Clipboard is empty")
                pinDecodeProc.targetSlot = 0
            }
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 22
        color: colors.alpha(colors.surface, 0.62)
        focus: root.open

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
            anchors.margins: 20
            spacing: 14

            // header
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Clipboard"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: clearLabel.implicitWidth + 24; implicitHeight: 28; radius: 14
                    color: clearMa.containsMouse ? root.fill2 : root.fill
                    Text { id: clearLabel; anchors.centerIn: parent; text: "Clear history"; color: colors.alpha(colors.foreground, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                    MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearAll() }
                }
            }

            // search
            TextField {
                id: filterField
                Layout.fillWidth: true
                implicitHeight: 42
                leftPadding: 18; rightPadding: 18
                placeholderText: "Search clipboard"
                placeholderTextColor: colors.alpha(colors.foreground, 0.4)
                color: colors.foreground
                font.family: colors.fontSans; font.pixelSize: 11
                background: Rectangle { radius: 21; color: filterField.activeFocus ? root.fill2 : root.fill }
                onTextChanged: root.filter = text
                Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) { root.pinCursor(); event.accepted = true }
                    else if (event.key === Qt.Key_Delete) { root.deleteCursor(); event.accepted = true }
                    else if (event.key === Qt.Key_Down) { root.moveCursor(1); event.accepted = true }
                    else if (event.key === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.copyCursor(); event.accepted = true }
                    else if (event.key === Qt.Key_Escape) {
                        if (text !== "") text = ""
                        else root.open = false
                        event.accepted = true
                    }
                }
            }

            // pinned notes: one full-width row per note, wrapped so nothing
            // is elided. The list scrolls when the notes are taller than the
            // shelf. Clicking a row copies the complete note.
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.boardVisible
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Pinned, " + root.pinnedList.length + " of 9"
                        color: colors.alpha(colors.foreground, 0.5)
                        font.family: colors.fontSans; font.pixelSize: 10
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: root.pinnedList.length > 0
                        text: "click a note to copy"
                        color: colors.alpha(colors.foreground, 0.32)
                        font.family: colors.fontSans; font.pixelSize: 9
                    }
                }
                Text {
                    visible: root.pinnedList.length === 0
                    text: "No pinned notes yet — use Pin or CTRL P on a clip."
                    color: colors.alpha(colors.foreground, 0.42)
                    font.family: colors.fontSans; font.pixelSize: 10
                }
                ListView {
                    id: pinList
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.pinnedList.length === 0 ? 0 : Math.min(230, Math.max(96, pinList.contentHeight))
                    visible: root.pinnedList.length > 0
                    clip: true
                    spacing: 6
                    model: root.pinnedList
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: pinRow
                        required property int index
                        required property var modelData
                        readonly property int slot: modelData.slot
                        readonly property bool selected: root.pinnedIndex(slot) === root.cursor

                        width: pinList.width
                        height: Math.max(44, pinBody.implicitHeight + 20)
                        radius: 12
                        color: root.noteColors[(slot - 1) % 5]
                        border.width: root.hoverSlot === slot || selected ? 2 : 0
                        border.color: selected ? colors.alpha(colors.foreground, 0.62) : colors.alpha(colors.foreground, 0.8)
                        opacity: root.dragging && root.dragFromSlot === slot ? 0.3 : 1

                        Text {
                            id: pinSlot
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 11
                            text: pinRow.slot
                            color: "#241f12"; opacity: 0.55
                            font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold
                        }
                        Text {
                            id: pinBody
                            anchors.left: pinSlot.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 68
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            text: pinRow.modelData.text
                            color: "#241f12"
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Medium
                        }
                        Rectangle {
                            id: unpinBtn
                            z: 2
                            visible: pinRow.selected || pinMouse.containsMouse
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            implicitWidth: unpinLabel.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: colors.alpha(colors.foreground, 0.14)
                            Text {
                                id: unpinLabel
                                anchors.centerIn: parent
                                text: "Unpin"
                                color: "#241f12"; opacity: 0.68
                                font.family: colors.fontSans; font.pixelSize: 9
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.setPin(pinRow.slot, "")
                            }
                        }
                        MouseArea {
                            id: pinMouse
                            anchors.fill: parent
                            z: 1
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyPin(pinRow.slot)
                        }
                        DragSource {
                            payload: pinRow.modelData.text
                            fromSlot: pinRow.slot
                        }
                    }
                }
            }

            // history
            Text {
                text: root.filter.trim() === "" ? "History" : root.filtered.length + " found"
                color: colors.alpha(colors.foreground, 0.5)
                font.family: colors.fontSans; font.pixelSize: 10
            }

            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: rowItem
                    required property var modelData
                    required property int index
                    readonly property int cur: root.pinnedCount + index
                    readonly property bool selected: cur === root.cursor
                    readonly property bool pinned: !modelData.isImage && root.pins.indexOf(modelData.preview) >= 0
                    property string thumbPath: "/tmp/quickshell-cliphist/" + modelData.id + ".png"
                    property bool thumbReady: false

                    width: clipList.width
                    height: modelData.isImage ? 60 : 44
                    radius: 14
                    color: selected ? colors.alpha(colors.primary, 0.22) : rowMa.containsMouse ? root.fill2 : root.fill
                    Component.onCompleted: if (modelData.isImage) thumbProc.running = true

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: if (root.allowHover) root.cursor = rowItem.cur
                        onPositionChanged: if (!root.allowHover) root.allowHover = true
                        onClicked: root.copyEntry(rowItem.modelData.id)
                    }
                    // text clips can be dragged onto a pinned row; decode on drop
                    DragSource {
                        enabled: !rowItem.modelData.isImage
                        payload: rowItem.modelData.preview
                        clipId: rowItem.modelData.id
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: modelData.isImage ? 8 : 16
                        anchors.rightMargin: 8
                        spacing: 12

                        // small thumbnail for images
                        Rectangle {
                            visible: rowItem.modelData.isImage
                            Layout.preferredWidth: 64; Layout.preferredHeight: 44
                            color: colors.alpha(colors.foreground, 0.08)
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: rowItem.thumbReady ? "file://" + rowItem.thumbPath : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: rowItem.modelData.isImage ? "Image" : rowItem.modelData.preview
                            color: colors.foreground
                            elide: Text.ElideRight; maximumLineCount: 1
                            font.family: colors.fontSans; font.pixelSize: 11
                        }
                        Text {
                            visible: rowItem.modelData.isImage
                            text: { var m = rowItem.modelData.preview.match(/(\d+)\s*x\s*(\d+)/); return m ? m[1] + " x " + m[2] : "" }
                            color: colors.alpha(colors.foreground, 0.5)
                            font.family: colors.fontSans; font.pixelSize: 10
                        }
                        Rectangle {
                            visible: !rowItem.modelData.isImage && (rowItem.selected || rowMa.containsMouse)
                            implicitWidth: pinLabel.implicitWidth + 24; implicitHeight: 26; radius: 13
                            color: pinMa.containsMouse ? colors.alpha(colors.foreground, 0.18) : root.fill2
                            Text { id: pinLabel; anchors.centerIn: parent; text: rowItem.pinned ? "Pinned" : "Pin"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10 }
                            MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.pinEntry(rowItem.modelData) }
                        }
                    }

                    // decode image to /tmp for the thumbnail (cached, once per id)
                    Process {
                        id: thumbProc
                        command: ["sh", "-c", "mkdir -p /tmp/quickshell-cliphist; [ -f " + rowItem.thumbPath + " ] || cliphist decode " + rowItem.modelData.id + " > " + rowItem.thumbPath + " 2>/dev/null; echo done"]
                        stdout: StdioCollector { waitForEnd: true; onStreamFinished: rowItem.thumbReady = true }
                    }
                }
            }

            Text {
                visible: root.filtered.length === 0
                text: root.entries.length === 0 ? "No clipboard history" : "No matches"
                color: colors.alpha(colors.foreground, 0.5)
                font.family: colors.fontSans; font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                text: "Click a note to copy    ↑↓ move    Enter copy    CTRL P pin    Del remove    Drag notes to swap"
                color: colors.alpha(colors.foreground, 0.4)
                font.family: colors.fontSans; font.pixelSize: 9
                elide: Text.ElideRight
            }
        }

        // follows the pointer while dragging; lives on the card so the list can't clip it
        Rectangle {
            visible: root.dragging
            z: 100
            x: root.dragPos.x - width / 2
            y: root.dragPos.y - height / 2
            width: Math.min(220, ghostText.implicitWidth + 28); height: 32; radius: 11
            color: "#f3d877"
            opacity: 0.95
            Text { id: ghostText; anchors.centerIn: parent; width: parent.width - 28; text: root.dragText; color: "#241f12"; elide: Text.ElideRight; maximumLineCount: 1; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Medium }
        }
    }
}
