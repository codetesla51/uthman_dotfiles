import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// Clipboard Manager — Hyprland floating window + a Sticky shelf for things
// you copy constantly. Stickies live in LocalStorage (qs_stickies) and
// survive cliphist wipes.
//   SUPER CTRL V  open the window
//   SUPER CTRL P  pin whatever is on the clipboard right now, from any app
//   SUPER ALT 1-9 fire a sticky straight to the clipboard, no window
// Inside the window: type to filter, arrows move, Enter copies,
// CTRL P pins the selected row, Delete drops it, / jumps back to search,
// Esc clears the search first, then closes.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string filter: ""
    property var entries: [] // {id, preview, isImage}

    title: "Clipboard"
    implicitWidth: 640
    implicitHeight: 700
    minimumSize: Qt.size(560, 600)
    maximumSize: Qt.size(660, 730)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
    }
    IpcHandler {
        target: "sticky"
        // fire a sticky by 1-based slot: `ipc call sticky copy 3`
        // (param must be typed — untyped params aren't callable over IPC)
        function copy(slot: string): void { root.copyStickyBySlot(slot) }
        // pin current clipboard content without opening the window
        function pin(): void { root.addStickyFromClipboard() }
        function clearAll(): void { root.clearStickies() }
    }

    function refresh(){
        listProc.running = true
    }
    function copyEntry(id){
        Quickshell.execDetached(["sh","-c","cliphist decode "+id+" | wl-copy && notify-send -u low -a 'Clipboard' 'Clipboard' 'Copied'"])
        root.open = false
    }
    function deleteEntry(id){
        Quickshell.execDetached(["sh","-c","cliphist delete "+id+" 2>/dev/null; "])
        var arr = entries.slice()
        for(var i=0;i<arr.length;i++) if(arr[i].id===id){ arr.splice(i,1); break }
        entries = arr
    }
    function clearAll(){
        Quickshell.execDetached(["sh","-c","cliphist wipe 2>/dev/null; notify-send -u low -a 'Clipboard' 'Clipboard' 'Cleared'"])
        entries = []
    }
    function pinSelected(){
        var e = filtered[navIndex]
        if(e) addSticky(e.id, null)
    }
    function deleteSelected(){
        if (root.shelfVisible && root.stickyNav > 0 && root.stickies[root.stickyNav-1]) {
            deleteSticky(root.stickies[root.stickyNav-1].id)
            return
        }
        var e = filtered[navIndex]
        if(e) deleteEntry(e.id)
    }

    // ---- stickies ----
    property var stickies: [] // {id, text, slot, created}

    function stickyDb() { return LocalStorage.openDatabaseSync("qs_stickies", "1.0", "clipboard stickies", 200000) }

    function loadStickies(){
        var d = stickyDb()
        d.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS stickies(id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT, created INTEGER)')
            var rs = tx.executeSql('SELECT * FROM stickies ORDER BY id ASC')
            var arr = []
            for (var i=0;i<rs.rows.length;i++) {
                var r = rs.rows.item(i)
                arr.push({id: r.id, text: r.text, slot: i+1, created: r.created})
            }
            root.stickies = arr
        })
    }
    // stick clipboard entry id, or raw text when id is null
    function addSticky(id, rawText){
        if (stickies.length >= 9) {
            Quickshell.execDetached(["notify-send","-u","low","-a","Clipboard","Clipboard","Sticky shelf full (9)"])
            return
        }
        var body = rawText
        if (id !== null && id !== undefined) {
            var src = entries.filter(function(e){ return e.id === id })[0]
            if (!src) return
            if (src.isImage) {
                Quickshell.execDetached(["notify-send","-u","low","-a","Clipboard","Clipboard","Can't stick images yet"])
                return
            }
            body = src.preview
        }
        if (!body || !body.trim()) return
        var dup = stickies.filter(function(s){ return s.text === body.trim() })[0]
        if (dup) {
            Quickshell.execDetached(["notify-send","-u","low","-a","Clipboard","Clipboard","Already on the shelf"])
            return
        }
        var d = stickyDb()
        d.transaction(function(tx){
            tx.executeSql('INSERT INTO stickies(text,created) VALUES(?,?)', [body.trim(), Date.now()])
        })
        loadStickies()
    }
    function addStickyFromClipboard(){
        captureProc.running = true
    }
    function deleteSticky(id){
        var d = stickyDb()
        d.transaction(function(tx){ tx.executeSql('DELETE FROM stickies WHERE id=?', [id]) })
        loadStickies()
    }
    function clearStickies(){
        var d = stickyDb()
        d.transaction(function(tx){ tx.executeSql('DELETE FROM stickies') })
        loadStickies()
    }
    function copySticky(s){
        if (!s || !s.text) return
        var esc = s.text.replace(/'/g, "'\\''")
        Quickshell.execDetached(["sh","-c","printf '%s' '"+esc+"' | wl-copy && notify-send -u low -a 'Clipboard' 'Sticky' 'Copied'"])
        if (root.open) root.open = false
    }
    function copyStickyBySlot(slot){
        var n = parseInt(slot)
        if (isNaN(n) || n < 1) return
        var s = stickies.filter(function(x){ return x.slot === n })[0]
        if (s) copySticky(s)
    }
    function preview(text){
        if (!text) return ""
        var one = text.replace(/\s+/g, " ").trim()
        return one.length > 90 ? one.substring(0, 90) + "…" : one
    }
    // true when this clipboard entry is already on the shelf
    function isSticky(preview){
        return stickies.some(function(s){ return s.text === preview })
    }

    property int navIndex: 0
    property int stickyNav: 0
    property bool allowHover: false
    onOpenChanged: { if(open){ filter=""; filterField.text=""; navIndex = 0; stickyNav = 0; allowHover = false; refresh(); loadStickies(); Qt.callLater(function(){ filterField.forceActiveFocus() }) } }
    onFilterChanged: navIndex = 0
    onEntriesChanged: navIndex = 0
    onStickiesChanged: stickyNav = 0

    readonly property var filtered: {
        if(filter.trim()==="") return entries
        var q=filter.trim().toLowerCase()
        return entries.filter(function(e){ return e.preview.toLowerCase().includes(q) })
    }
    // when searching, the shelf hides so matches aren't buried under stickies
    readonly property bool shelfVisible: root.filter.trim() === "" && root.stickies.length > 0

    Component.onCompleted: loadStickies()

    Process {
        id: listProc
        command: ["sh","-c","cliphist list 2>/dev/null | head -n 50"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                var arr=[]
                for(var i=0;i<lines.length;i++){
                    var line=lines[i]
                    if(!line.trim()) continue
                    var tab=line.indexOf("\t")
                    if(tab<0) continue
                    var id=line.substring(0,tab).trim()
                    var preview=line.substring(tab+1).trim()
                    var isImage=preview.startsWith("[[ binary data")
                    arr.push({id:id, preview:preview, isImage:isImage})
                }
                root.entries=arr
            }
        }
    }

    // captures the live system clipboard straight into a sticky.
    // single process (no temp file): the old two-step version raced
    // wl-paste against cat and almost always read an empty file.
    Process {
        id: captureProc
        running: false
        command: ["sh","-c","wl-paste --no-newline 2>/dev/null | head -c 2000"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var body = text.replace(/\s+$/,"")
                if (body.trim()) root.addSticky(null, body)
                else Quickshell.execDetached(["notify-send","-u","low","-a","Clipboard","Clipboard","Clipboard is empty"])
            }
        }
    }

    // window glass — transparent surface so Hyprland's decoration blur
    // shows through, same recipe as the other floating windows
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width:1; border.color: colors.alpha(colors.outline,0.14)
        focus: root.open
        Keys.onEscapePressed: root.open=false
        Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) { root.pinSelected(); event.accepted = true }
            else if (event.key === Qt.Key_Delete) { root.deleteSelected(); event.accepted = true }
            else if (event.key === Qt.Key_Slash && !filterField.activeFocus) { filterField.forceActiveFocus(); event.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Clipboard"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth:true }
                // stick whatever is currently on the clipboard
                Rectangle {
                    width: 30; height: 26; radius: 13
                    color: pinMa.containsMouse?colors.alpha(colors.primary,0.18):colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.outline,0.14)
                    Text {
                        anchors.centerIn: parent
                        text: "󰐃"
                        color: pinMa.containsMouse?colors.primary:colors.alpha(colors.outline,0.75)
                        font.family: colors.fontSans; font.pixelSize: 12
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.addStickyFromClipboard() }
                }
                Rectangle {
                    width: 68; height: 26; radius: 13
                    color: clearMa.containsMouse?colors.alpha(colors.error,0.15):colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.outline,0.14)
                    Text { anchors.centerIn: parent; text: "Clear"; color: clearMa.containsMouse?colors.error:colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.clearAll() }
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            TextField {
                id: filterField
                Layout.fillWidth: true
                implicitHeight: 36
                leftPadding: 14; rightPadding: 14
                placeholderText: "Search clipboard…  ( / focuses · CTRL P pins · DEL drops )"
                placeholderTextColor: colors.alpha(colors.outline,0.5)
                color: colors.foreground
                font.family: colors.fontSans; font.pixelSize: 11
                background: Rectangle {
                    radius: 10
                    color: colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: filterField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                }
                onTextChanged: { root.filter=text; root.navIndex = 0 }
                Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) { root.pinSelected(); event.accepted = true }
                    else if (event.key === Qt.Key_Delete) { root.deleteSelected(); event.accepted = true }
                    else if (event.key === Qt.Key_Tab) {
                        root.stickyNav = Math.min(root.stickyNav+1, Math.max(0, root.stickies.length-1))
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Backtab) {
                        root.stickyNav = Math.max(root.stickyNav-1, 0)
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Down) {
                        if (root.shelfVisible && root.stickies.length > 0) {
                            root.stickyNav = Math.min(root.stickyNav+1, root.stickies.length-1)
                            event.accepted = true
                        } else {
                            root.navIndex = Math.min(root.navIndex+1, root.filtered.length-1)
                            clipList.positionViewAtIndex(root.navIndex, ListView.Contain)
                            event.accepted = true
                        }
                    }
                    else if (event.key === Qt.Key_Up) {
                        if (root.shelfVisible && root.stickyNav > 0) {
                            root.stickyNav = root.stickyNav-1
                            event.accepted = true
                        } else {
                            root.navIndex = Math.max(root.navIndex-1, 0)
                            clipList.positionViewAtIndex(root.navIndex, ListView.Contain)
                            event.accepted = true
                        }
                    }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.shelfVisible && root.stickyNav > 0 && root.stickies[root.stickyNav-1]) {
                            root.copySticky(root.stickies[root.stickyNav-1])
                        } else {
                            var e = root.filtered[root.navIndex]
                            if(e) root.copyEntry(e.id)
                        }
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Escape) {
                        if (filterField.text !== "") { filterField.text = ""; event.accepted = true }
                        else { root.open = false; event.accepted = true }
                    }
                }
            }

            // ── Sticky shelf ──────────────────────────────────────────
            // Pinned snippets you copy constantly. SUPER ALT 1-9 fires one
            // without opening this panel, so they work from any app.
            ColumnLayout {
                id: shelf
                Layout.fillWidth: true
                visible: root.shelfVisible
                Layout.preferredHeight: root.shelfVisible ? implicitHeight : 0
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle { width:3; height:12; radius:1.5; color: colors.alpha(colors.primary,0.7) }
                    Text {
                        text: "STICKY"
                        color: colors.alpha(colors.outline,0.55)
                        font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                    }
                    Rectangle { width:1; height:8; color: colors.alpha(colors.outline,0.2) }
                    Text {
                        text: root.stickies.length + " of 9"
                        color: colors.alpha(colors.outline,0.45)
                        font.family: colors.fontSans; font.pixelSize: 7
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "SUPER ALT 1-9 fire · DEL removes"
                        color: colors.alpha(colors.outline,0.4)
                        font.family: colors.fontSans; font.pixelSize: 7
                    }
                }

                ListView {
                    id: stickyList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(3*46, count*46)
                    clip: true
                    interactive: true
                    model: root.stickies
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: stickyEntry
                        required property var modelData
                        required property int index
                        readonly property bool selected: modelData.slot === root.stickyNav
                        width: stickyList.width
                        height: 46
                        radius: 10
                        color: selected ? colors.alpha(colors.primary,0.18) : sma.containsMouse ? colors.alpha(colors.primary,0.10) : colors.alpha(colors.surface,0.5)
                        border.width: 1
                        border.color: selected ? colors.alpha(colors.primary,0.5) : sma.containsMouse ? colors.alpha(colors.primary,0.3) : colors.alpha(colors.outline,0.12)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            spacing: 8

                            // slot chip — the number you press
                            Rectangle {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: 12
                                color: colors.alpha(colors.primary,0.15)
                                border.width: 1; border.color: colors.alpha(colors.primary,0.3)
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.slot
                                    color: colors.primary
                                    font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.preview(modelData.text)
                                color: colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 10
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        MouseArea {
                            id: sma
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            onEntered: root.stickyNav = modelData.slot
                            onClicked: root.copySticky(modelData)
                        }
                    }
                }
            }

            // ── section split: shelf above, history below ─────────────
            // only exists when the shelf is showing — otherwise history
            // is the whole window and needs no introduction.
            RowLayout {
                Layout.fillWidth: true
                visible: root.shelfVisible
                Layout.preferredHeight: root.shelfVisible ? implicitHeight : 0
                spacing: 10
                Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline,0.18) }
                Text {
                    text: "HISTORY"
                    color: colors.alpha(colors.outline,0.55)
                    font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                }
                Text {
                    text: root.filtered.length + ""
                    color: colors.alpha(colors.outline,0.45)
                    font.family: colors.fontSans; font.pixelSize: 7
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline,0.18) }
            }

            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                interactive: true
                model: root.filtered
                currentIndex: root.navIndex
                onCurrentIndexChanged: root.navIndex = currentIndex
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: clipEntry
                    required property var modelData
                    required property int index
                    property string thumbPath: "/tmp/quickshell-cliphist/" + modelData.id + ".png"
                    property bool thumbReady: false
                    readonly property bool stickied: !modelData.isImage && root.isSticky(modelData.preview)
                    onThumbPathChanged: { thumbReady = false; if(modelData.isImage) thumbProc.running = true }
                    Component.onCompleted: if(modelData.isImage) thumbProc.running = true
                    width: clipList.width
                    height: modelData.isImage ? 72 : 48
                    radius: 12
                    color: index === root.navIndex ? colors.alpha(colors.primary,0.18) : ma.containsMouse ? colors.alpha(colors.primary,0.10) : colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: index === root.navIndex ? colors.alpha(colors.primary,0.5) : ma.containsMouse?colors.alpha(colors.primary,0.3):colors.alpha(colors.outline,0.12)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 8
                        spacing: 10
                        // image preview for binary data — actual thumbnail from cliphist decode
                        Rectangle {
                            visible: modelData.isImage
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: 8
                            color: colors.alpha(colors.surfaceVariant,0.3)
                            clip: true
                            Image {
                                id: thumbImg
                                anchors.fill: parent
                                anchors.margins: 2
                                source: clipEntry.thumbReady ? "file://" + clipEntry.thumbPath : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: thumbImg.status !== Image.Ready
                                text: ""
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 18
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: 2
                                visible: thumbImg.status !== Image.Ready
                                text: {
                                    var m=modelData.preview.match(/(\d+)\s*x\s*(\d+)/)
                                    return m ? m[1]+"×"+m[2] : "IMG"
                                }
                                color: colors.alpha(colors.outline,0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 7
                            }
                        }
                        Rectangle {
                            visible: !modelData.isImage
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 8
                            color: colors.alpha(colors.primary,0.12)
                            Text { anchors.centerIn: parent; text: "󰅍"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 14 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.preview
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        // pin this entry to the sticky shelf
                        Rectangle {
                            visible: !modelData.isImage
                            Layout.preferredWidth: 24; Layout.preferredHeight: 24; radius: 12
                            color: pma.containsMouse?colors.alpha(colors.primary,0.2):(clipEntry.stickied?colors.alpha(colors.primary,0.15):"transparent")
                            border.width: clipEntry.stickied?1:0
                            border.color: colors.alpha(colors.primary,0.3)
                            Text {
                                anchors.centerIn: parent
                                text: clipEntry.stickied ? "󰐃" : "󰤱"
                                color: clipEntry.stickied ? colors.primary : (pma.containsMouse?colors.primary:colors.alpha(colors.outline,0.4))
                                font.family: colors.fontSans; font.pixelSize: 11
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            MouseArea { id: pma; anchors.fill: parent; hoverEnabled:true; onClicked: root.addSticky(modelData.id, null) }
                        }
                    }
                    // decode image to /tmp for thumbnail (cached, only once per id)
                    Process {
                        id: thumbProc
                        running: false
                        command: ["sh","-c", "mkdir -p /tmp/quickshell-cliphist; [ -f " + clipEntry.thumbPath + " ] || cliphist decode " + modelData.id + " > " + clipEntry.thumbPath + " 2>/dev/null; echo done"]
                        stdout: StdioCollector {
                            waitForEnd: true
                            onStreamFinished: clipEntry.thumbReady = true
                        }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled:true; onEntered: if(root.allowHover) root.navIndex = index; onPositionChanged: if(!root.allowHover) root.allowHover = true; onClicked: root.copyEntry(modelData.id) }
                }
            }

            Text {
                visible: root.filtered.length===0 && !root.shelfVisible
                text: root.entries.length===0 ? "No clipboard history" : "No matches"
                color: colors.alpha(colors.outline,0.5)
                font.family: colors.fontSans; font.pixelSize: 10
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
