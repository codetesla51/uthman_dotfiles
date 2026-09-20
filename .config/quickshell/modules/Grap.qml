import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Grap — instant content search across your files (ripgrep wrapper).
// Small floating card (FastFetch size class). Type → debounced rg over the
// scope dir → icon rows. Enter/click opens the match in Zed at exact line.
// Hub-only (no bind). PdfViewer glass language.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    property string query: ""
    // home only — no scope switching UI; use @path prefix to scope:
    // "@dotfiles foo" → ~/dotfiles, "@~/.config/hypr foo" → that dir,
    // "@/etc/foo bar" → absolute. Bare query always greps $HOME.
    property string scopeLabel: ""
    function parseScope(q) {
        var m = /^@(\S+)\s+([\s\S]*)$/.exec(q.trim())
        if (!m) return { dir: Quickshell.env("HOME"), pattern: q, label: "" }
        var raw = m[1]
        var dir = raw.charAt(0) === "~" ? Quickshell.env("HOME") + raw.slice(1)
            : raw.charAt(0) !== "/" ? Quickshell.env("HOME") + "/" + raw : raw
        return { dir: dir, pattern: m[2], label: shortPath(dir) }
    }
    function scopeDir() { return Quickshell.env("HOME") }
    property var results: []
    property bool searching: false
    property string status: ""
    property int selected: 0
    property int hovered: -1 // mouse highlight, kept OFF currentIndex so hover never scroll-jumps the list
    property bool truncated: false
    // search-while-loading race guard: queue the latest query, drain on finish
    property bool queued: false
    property string queuedQuery: ""
    property double searchStart: 0

    title: "Grap"
    implicitWidth: 600
    implicitHeight: 470
    minimumSize: Qt.size(560, 420)
    maximumSize: Qt.size(640, 520)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "grap"
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
    }

    // ---------- verified Nerd Font glyphs (AGENTS section 2) ----------
    readonly property var glyphs: ({
        search: "", close: "󰅖", spin: "",
        home: "", folder: "", gear: "",
        file: "", text: "", code: ""
    })
    readonly property var accents: [colors.primary, colors.secondary, colors.tertiary]

    function shortPath(p) {
        var h = Quickshell.env("HOME")
        if (p.indexOf(h) === 0) return "~" + p.slice(h.length)
        return p
    }
    function baseName(p) {
        var i = p.lastIndexOf("/")
        return i === -1 ? p : p.slice(i + 1)
    }
    function fileGlyph(p) {
        var dot = p.lastIndexOf(".")
        var ext = dot === -1 ? "" : p.slice(dot + 1).toLowerCase()
        if (["qml","js","ts","jsx","tsx","go","py","rs","c","h","cpp","java","lua","sh","css","scss"].indexOf(ext) !== -1) return glyphs.code
        if (["conf","toml","yaml","yml","ini","rasi","json","xml"].indexOf(ext) !== -1) return glyphs.gear
        if (["md","txt","org","tex"].indexOf(ext) !== -1) return glyphs.text
        return glyphs.file
    }

    function queueSearch(text) {
        root.query = text
        root.selected = 0
        var p = root.parseScope(text)
        root.scopeLabel = p.label
        if (p.pattern.trim().length < 2) {
            root.results = []
            root.truncated = false
            root.status = p.label !== "" ? "in " + p.label + " — keep typing" : ""
            return
        }
        debounce.restart()
    }

    function startSearch(text) {
        var p = root.parseScope(text)
        if (p.pattern.trim().length < 2) return
        if (root.searching) {
            root.queued = true
            root.queuedQuery = text
            return
        }
        root.searching = true
        root.status = "searching" + (p.label !== "" ? " " + p.label : "") + "…"
        root.searchStart = Date.now()
        searchProc.command = ["rg", "--vimgrep", "--no-heading", "--no-messages",
            "--smart-case", "--hidden", "-M", "300", "--max-count", "5",
            "--glob", "!.git/", "--glob", "!.cache/", "--glob", "!node_modules/",
            "--glob", "!.mozilla/", "--glob", "!.local/share/Trash/",
            "-e", p.pattern, p.dir]
        searchProc.running = true
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var elapsed = ((Date.now() - root.searchStart) / 1000).toFixed(2)
                var out = []
                var cut = false
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i]
                    if (ln === "") continue
                    var m = /^(.+?):(\d+):(\d+):(.*)$/.exec(ln)
                    if (!m) continue
                    if (out.length >= 150) { cut = true; break }
                    out.push({ file: m[1], line: parseInt(m[2], 10), col: parseInt(m[3], 10), snippet: m[4].trim() })
                }
                // drain-then-apply: a queued query always wins over these results
                var hasQueued = root.queued
                var next = root.queuedQuery
                root.queued = false
                root.searching = false
                if (hasQueued) {
                    root.startSearch(next)
                    return
                }
                root.results = out
                root.truncated = cut
                root.selected = 0
                root.hovered = -1
                var where = root.scopeLabel !== "" ? "in " + root.scopeLabel + " · " : ""
                root.status = out.length === 0 ? where + "no matches · " + elapsed + "s"
                    : where + out.length + (cut ? "+" : "") + " matches · " + elapsed + "s"
            }
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.results.length === 0 && text.trim() !== "")
                    root.status = text.trim().split("\n")[0]
            }
        }
    }
    Timer { id: debounce; interval: 300; onTriggered: root.startSearch(root.query) }

    function openResult(r) {
        if (!r) return
        Quickshell.execDetached(["uwsm-app", "--", "kitty", "-e", "nano", "+" + r.line, r.file])
        root.open = false
    }

    onOpenChanged: {
        if (open) {
            root.query = ""
            searchField.text = ""
            root.results = []
            root.status = ""
            root.scopeLabel = ""
            root.selected = 0
            root.hovered = -1
            root.truncated = false
            root.queued = false
            Qt.callLater(function(){ searchField.forceActiveFocus() })
        }
    }

    // window glass — PdfViewer recipe
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.14)
        focus: true
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // header — chip + title + status + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: root.glyphs.search; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "GRAP"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                Text { text: root.status; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignVCenter }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: root.glyphs.close; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // search field
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 12
                    color: colors.alpha(colors.surface, 0.6)
                    border.width: 1
                    border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.15)
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 8
                        Text { text: root.glyphs.search; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: "Grep home…  (@path to scope)"
                            placeholderTextColor: colors.alpha(colors.outline, 0.5)
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            background: null
                            selectByMouse: true
                            onTextChanged: root.queueSearch(text)
                            Keys.onPressed: function(e){
                                if (e.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
                                else if (e.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 1, 0); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
                                else if (e.key === Qt.Key_Escape) { root.open = false; e.accepted = true }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.openResult(root.results[root.selected]); e.accepted = true }
                            }
                        }
                        Text {
                            visible: root.searching
                            text: root.glyphs.spin
                            color: colors.primary
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignVCenter
                            RotationAnimation on rotation { running: root.searching; loops: Animation.Infinite; duration: 900; from: 0; to: 360 }
                        }
                        Text {
                            visible: searchField.text !== "" && !root.searching
                            text: root.glyphs.close
                            color: clearMa.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.6)
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignVCenter
                            MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled: true; onClicked: { searchField.text = ""; root.queueSearch("") } }
                        }
                    }
                }
            }

            // results — 5 rows visible, rest scrolls
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.preferredHeight: 294
                clip: true
                spacing: 6
                model: root.results
                currentIndex: root.selected
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: resultList.width
                    height: 54
                    radius: 10
                    clip: true
                    color: (index === root.selected || index === root.hovered) ? colors.alpha(colors.primary, 0.14) : colors.alpha(colors.surfaceVariant, 0.18)
                    border.width: 1
                    border.color: (index === root.selected || index === root.hovered) ? colors.alpha(colors.primary, 0.35) : colors.alpha(colors.outline, 0.08)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: colors.alpha(root.accents[index % 3], 0.16)
                            border.width: 1
                            border.color: colors.alpha(root.accents[index % 3], 0.45)
                            Layout.alignment: Qt.AlignVCenter
                            Text {
                                anchors.centerIn: parent
                                text: root.fileGlyph(modelData.file)
                                color: root.accents[index % 3]
                                font.family: colors.fontSans
                                font.pixelSize: 12
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1
                            Text {
                                text: root.baseName(modelData.file)
                                color: colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.snippet
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: ":" + modelData.line
                            color: (index === root.selected || index === root.hovered) ? colors.primary : colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "→"
                            color: (index === root.selected || index === root.hovered) ? colors.primary : colors.alpha(colors.outline, 0.4)
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.hovered = index
                        onExited: root.hovered = -1
                        onClicked: root.openResult(modelData)
                    }
                }
            }

            Text {
                visible: root.results.length === 0 && !root.searching
                text: root.query.trim().length < 2 ? "type 2+ chars · @folder to scope" : root.status
                color: colors.alpha(colors.outline, 0.5)
                font.family: colors.fontSans
                font.pixelSize: 9
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "↑↓ navigate  •  ↵ nano  •  @path scope  •  esc close"
                color: colors.alpha(colors.outline, 0.4)
                font.family: colors.fontSans
                font.pixelSize: 7
                font.letterSpacing: 0.3
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
