import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Grap — instant content search across your files (ripgrep wrapper).
// Small floating card (FastFetch size class). Type → debounced rg over the
// scope dir (chips or @path) → icon rows with the hit highlighted.
// Enter/click opens the match in nano at exact line; ^O opens Zed; ^Y copies
// path:line:col. Hub-only (no bind). PdfViewer glass language.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    property string query: ""
    // scope: chips (~ | dotfiles | .config) or an @path prefix in the query:
    // "@dotfiles foo" → ~/dotfiles, "@~/.config/hypr foo" → that dir,
    // "@/etc/foo bar" → absolute. Bare query greps the chip's dir.
    property string scopeLabel: ""
    function parseScope(q) {
        var m = /^@(\S+)\s+([\s\S]*)$/.exec(q.trim())
        if (!m) {
            root.explicitScope = false
            return { dir: scopeRoot(), pattern: q, label: scopeKey === "home" ? "" : shortPath(scopeRoot()) }
        }
        var raw = m[1]
        var dir = raw.charAt(0) === "~" ? Quickshell.env("HOME") + raw.slice(1)
            : raw.charAt(0) !== "/" ? Quickshell.env("HOME") + "/" + raw : raw
        root.explicitScope = true
        return { dir: dir, pattern: m[2], label: shortPath(dir) }
    }
    // scope chips → directory (an @path in the query always wins)
    function scopeRoot() {
        if (scopeKey === "dotfiles") return Quickshell.env("HOME") + "/dotfiles"
        if (scopeKey === "config") return Quickshell.env("HOME") + "/.config"
        return Quickshell.env("HOME")
    }
    function setScope(key) {
        root.scopeKey = key
        root.hovered = -1
        root.queueSearch(root.query)
    }
    // drop the @path prefix so the chips take over again
    function clearScopePrefix() {
        searchField.text = searchField.text.replace(/^@\S+\s+/, "")
        root.queueSearch(searchField.text)
    }
    function scopeDir() { return scopeRoot() }
    property var results: []
    property var contentResults: []
    property var fileResults: []
    property int findGen: 0
    property string lastElapsed: ""
    property bool searching: false
    property string status: ""
    property int selected: 0
    property int hovered: -1 // mouse highlight, kept OFF currentIndex so hover never scroll-jumps the list
    property bool truncated: false
    // search-while-loading race guard: queue the latest query, drain on finish
    property bool queued: false
    property string queuedQuery: ""
    property double searchStart: 0
    // ── search options (chips in the toolbar) ───────────────────────
    property string scopeKey: "home"     // home | dotfiles | config
    property bool explicitScope: false   // true while the query carries an @path
    property bool caseSensitive: false   // Aa  on → rg --case-sensitive
    property bool regexMode: true        // .*  on → regex, off → --fixed-strings
    readonly property int preCap: 28     // leading snippet chars kept before the hit

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
        function search(q: string): void { root.open = true; Qt.callLater(function(){ searchField.text = q; root.queueSearch(q) }) }
    }

    // ---------- verified Nerd Font glyphs (AGENTS section 2) ----------
    readonly property var glyphs: ({
        search: "", close: "󰅖", spin: "",
        home: "", folder: "", gear: "",
        file: "", text: "", code: ""
    })
    readonly property var accents: [colors.primary, colors.secondary, colors.tertiary]
    // the searchable text of the query with any @scope prefix stripped — computed
    // once per query so result delegates never re-parse it
    function patternOf(q) {
        var m = /^@(\S+)\s+([\s\S]*)$/.exec(q.trim())
        return m ? m[2] : q
    }
    readonly property string activePattern: root.patternOf(root.query)

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
    // row accent by file kind — amber-bento accents by purpose
    function fileAccent(p) {
        var dot = p.lastIndexOf(".")
        var ext = dot === -1 ? "" : p.slice(dot + 1).toLowerCase()
        if (["qml","js","ts","jsx","tsx","go","py","rs","c","h","cpp","java","lua","sh","css","scss"].indexOf(ext) !== -1) return colors.tertiary
        if (["conf","toml","yaml","yml","ini","rasi","json","xml"].indexOf(ext) !== -1) return colors.secondary
        if (["md","txt","org","tex"].indexOf(ext) !== -1) return colors.primary
        return colors.outline
    }
    function relDir(p) {
        var i = p.lastIndexOf("/")
        return i <= 0 ? "" : shortPath(p.slice(0, i))
    }
    // split a snippet around the hit so the match can be highlighted
    function hlParts(snippet, pattern) {
        var s = String(snippet)
        if (!pattern) return { pre: s, hit: "", post: "" }
        var re = null
        try {
            re = new RegExp(root.regexMode ? pattern : pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
                            root.caseSensitive ? "" : "i")
        } catch (e) { return { pre: s, hit: "", post: "" } }
        var m = re.exec(s)
        if (!m || m[0] === "") return { pre: s, hit: "", post: "" }
        var pre = s.slice(0, m.index)
        var cut = false
        if (pre.length > root.preCap) { pre = pre.slice(pre.length - root.preCap); cut = true }
        var hit = m[0].length > 32 ? m[0].slice(0, 32) : m[0]
        return { pre: (cut ? "…" : "") + pre, hit: hit, post: s.slice(m.index + m[0].length) }
    }

    function queueSearch(text) {
        root.query = text
        root.selected = 0
        var p = root.parseScope(text)
        root.scopeLabel = p.label
        if (p.pattern.trim().length < 2) {
            root.results = []
            root.contentResults = []
            root.fileResults = []
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
            root.startFindFor(text)
            return
        }
        root.searching = true
        root.status = "searching" + (p.label !== "" ? " " + p.label : "") + "…"
        root.searchStart = Date.now()
        searchProc.command = (function(){
            var a = ["rg", "--vimgrep", "--no-heading", "--no-messages",
                "--hidden", "-M", "300", "--max-count", "5",
                "--glob", "!.git/", "--glob", "!.cache/", "--glob", "!node_modules/",
                "--glob", "!.mozilla/", "--glob", "!.local/share/Trash/"]
            a.push(root.caseSensitive ? "--case-sensitive" : "--smart-case")
            if (!root.regexMode) a.push("--fixed-strings")
            a.push("-e", p.pattern, p.dir)
            return a
        })()
        searchProc.running = true
    }

    function mergeResults() {
        var files = root.fileResults.slice(0, 30)
        var content = root.contentResults.slice(0, Math.max(0, 150 - files.length))
        root.results = files.concat(content)
        if (root.selected >= root.results.length) root.selected = 0
        root.hovered = -1
        root.truncated = root.fileResults.length > 30 || root.contentResults.length > (150 - files.length)
        var where = root.scopeLabel !== "" ? "in " + root.scopeLabel + " · " : ""
        var t = root.lastElapsed !== "" ? " · " + root.lastElapsed + "s" : ""
        if (root.results.length === 0) root.status = where + "no matches" + t
        else root.status = where + files.length + " files + " + content.length + " hits" + t
    }

    // filename search (find) — runs alongside grep, fixed-strings so
    // 2-char queries can't blow up as regex; fd preferred, find fallback
    function startFindFor(text) {
        var p = root.parseScope(text)
        if (p.pattern.trim().length < 2) return
        if (!/^[A-Za-z0-9@._+~\/ -]+$/.test(p.pattern)) return
        root.findGen += 1
        var g = root.findGen
        var dir = p.dir.replace(/'/g, "'\\''")
        var pat = p.pattern.replace(/'/g, "'\\''")
        var glob = p.pattern.replace(/[*?\[\\]/g, "")
        if (glob.trim() === "") return
        findProc.gen = g
        findProc.command = ["sh", "-c", "fd -H -t f -F --max-results 30 --exclude .git --exclude node_modules --exclude .cache --exclude .mozilla --exclude Trash '" + pat + "' '" + dir + "' 2>/dev/null || find '" + dir + "' \\( -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/.cache/*' \\) -prune -o -type f -iname '*" + glob + "*' -print 2>/dev/null | head -n 30"]
        findProc.running = true
    }

    Process {
        id: searchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var elapsed = ((Date.now() - root.searchStart) / 1000).toFixed(2)
                var out = []
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i]
                    if (ln === "") continue
                    var m = /^(.+?):(\d+):(\d+):(.*)$/.exec(ln)
                    if (!m) continue
                    if (out.length >= 150) break
                    out.push({ file: m[1], line: parseInt(m[2], 10), col: parseInt(m[3], 10), snippet: m[4].trim(), isFile: false })
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
                root.contentResults = out
                root.lastElapsed = elapsed
                root.mergeResults()
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
    Process {
        id: findProc
        property int gen: 0
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (findProc.gen !== root.findGen) return
                var out = []
                var lines = text.split("\n")
                for (var i = 0; i < lines.length && out.length < 30; i++) {
                    var ln = lines[i].trim()
                    if (ln === "") continue
                    out.push({ file: ln, line: 1, col: 1, snippet: "", isFile: true })
                }
                root.fileResults = out
                root.mergeResults()
            }
        }
    }
    Timer { id: debounce; interval: 300; onTriggered: { root.startSearch(root.query); root.startFindFor(root.query) } }

    function openResult(r) {
        if (!r) return
        Quickshell.execDetached(["uwsm-app", "--", "kitty", "-e", "nano", "+" + r.line, r.file])
        root.open = false
    }
    function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    // copy `path:line:col` to the clipboard (house idiom)
    function copyResult(r) {
        if (!r) return
        var loc = r.file + ":" + r.line + ":" + r.col
        Quickshell.execDetached(["sh", "-c", "printf %s " + root.shQuote(loc) + " | (wl-copy 2>/dev/null || xclip -selection clipboard 2>/dev/null) && notify-send -u low -a 'Grap' 'Copied' " + root.shQuote(loc)])
    }
    // open the hit in the GUI editor at the exact line
    function openInZed(r) {
        if (!r) return
        Quickshell.execDetached(["uwsm-app", "--", "zed", r.file + ":" + r.line])
        root.open = false
    }

    onOpenChanged: {
        if (open) {
            root.query = ""
            searchField.text = ""
            root.results = []
            root.contentResults = []
            root.fileResults = []
            root.lastElapsed = ""
            root.status = ""
            root.scopeLabel = ""
            root.selected = 0
            root.hovered = -1
            root.truncated = false
            root.queued = false
            root.scopeKey = "home"
            root.explicitScope = false
            root.caseSensitive = false
            root.regexMode = true
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

            // v2: header removed — hero search + meta whisper carry identity and status.
            // No X button per house rule; Esc closes.

            // hero search — the panel IS this input
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
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
                        Text { text: root.glyphs.search; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 15; Layout.alignment: Qt.AlignVCenter }
                        // @path crumb — lives in the hero now; click drops the prefix
                        Rectangle {
                            visible: root.explicitScope
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: Math.min(Math.max(30, crumbTxt.implicitWidth + 30), 180)
                            radius: 12
                            color: colors.alpha(colors.secondary, 0.14)
                            border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                            Layout.alignment: Qt.AlignVCenter
                            Text {
                                id: crumbTxt
                                anchors.centerIn: parent
                                width: Math.min(crumbTxt.implicitWidth, 152)
                                elide: Text.ElideRight
                                text: root.glyphs.folder + "  " + root.scopeLabel
                                color: colors.secondary
                                font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.clearScopePrefix() }
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            placeholderText: "Grep + find home…  (@path to scope)"
                            placeholderTextColor: colors.alpha(colors.outline, 0.5)
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            background: null
                            selectByMouse: true
                            onTextChanged: root.queueSearch(text)
                            Keys.onPressed: function(e){
                                if (e.key === Qt.Key_Down) { root.selected = Math.min(root.selected + 1, root.results.length - 1); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
                                else if (e.key === Qt.Key_Up) { root.selected = Math.max(root.selected - 1, 0); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
                                else if (e.key === Qt.Key_Escape) { if (searchField.text !== "") { searchField.text = ""; root.queueSearch("") } else root.open = false; e.accepted = true }
                                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.openResult(root.results[root.selected]); e.accepted = true }
                                else if (e.key === Qt.Key_Y && (e.modifiers & Qt.ControlModifier)) { root.copyResult(root.results[root.selected]); e.accepted = true }
                                else if (e.key === Qt.Key_O && (e.modifiers & Qt.ControlModifier)) { root.openInZed(root.results[root.selected]); e.accepted = true }
                                else if (e.key === Qt.Key_U && (e.modifiers & Qt.ControlModifier)) { searchField.text = ""; root.queueSearch(""); e.accepted = true }
                                else if (e.key === Qt.Key_PageDown) { root.selected = Math.min(root.selected + 5, root.results.length - 1); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
                                else if (e.key === Qt.Key_PageUp) { root.selected = Math.max(root.selected - 5, 0); root.hovered = -1; resultList.positionViewAtIndex(root.selected, ListView.Contain); e.accepted = true }
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

            // meta whisper — counts + scope + time; collapses when empty
            Text {
                visible: root.status !== ""
                Layout.fillWidth: true
                text: root.status
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans; font.pixelSize: 9
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // toolbar — scope chips (left) · option chips (right)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                // segmented scope — one strip, not three chips
                Rectangle {
                    Layout.preferredHeight: 26
                    Layout.preferredWidth: segRow.implicitWidth + 6
                    Layout.alignment: Qt.AlignVCenter
                    radius: 13
                    color: colors.alpha(colors.surface, 0.55)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.1)
                    Row {
                        id: segRow
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: [ { key: "home", label: "~", glyph: root.glyphs.home },
                                     { key: "dotfiles", label: "dotfiles", glyph: root.glyphs.folder },
                                     { key: "config", label: ".config", glyph: root.glyphs.gear } ]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool on: !root.explicitScope && root.scopeKey === modelData.key
                                width: Math.max(34, segTxt.implicitWidth + 20)
                                height: 22
                                radius: 11
                                color: on ? colors.alpha(colors.primary, 0.15)
                                          : (segMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : "transparent")
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    id: segTxt
                                    anchors.centerIn: parent
                                    text: modelData.glyph + " " + modelData.label
                                    color: on ? colors.primary : colors.alpha(colors.outline, 0.75)
                                    font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.DemiBold
                                }
                                MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setScope(modelData.key) }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                // option chips — Aa = case-sensitive, .* = regex mode
                Repeater {
                    model: [ { key: "case", label: "Aa" }, { key: "regex", label: ".*" } ]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: modelData.key === "case" ? root.caseSensitive : root.regexMode
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: 30
                        radius: 11
                        color: on ? colors.alpha(colors.primary, 0.15)
                                  : (optMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.on ? colors.primary : colors.alpha(colors.outline, 0.75)
                            font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold
                        }
                        MouseArea { id: optMa; anchors.fill: parent; hoverEnabled: true; onClicked: {
                            if (modelData.key === "case") root.caseSensitive = !root.caseSensitive
                            else root.regexMode = !root.regexMode
                            root.startSearch(root.query)
                            root.startFindFor(root.query)
                        } }
                    }
                }
            }
            // results — fills the remaining height, six visible rows max
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 150
                visible: root.results.length > 0
                clip: true
                spacing: 6
                model: root.results
                currentIndex: root.selected
                // FILES / CONTENT groups — the model is files-first, isFile splits it
                section.property: "isFile"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    width: resultList.width
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: section === "true" ? "FILES" : "CONTENT"
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                    }
                }
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: rowRoot
                    required property var modelData
                    required property int index
                    readonly property bool active: index === root.selected || index === root.hovered
                    readonly property var parts: root.hlParts(modelData.snippet, root.activePattern)
                    width: resultList.width
                    // rows size to content — the fixed 58px is what kept breaking
                    height: Math.max(48, rowCol.implicitHeight + 16)
                    radius: 12
                    clip: true
                    color: active ? colors.alpha(colors.primary, 0.13) : colors.alpha(colors.surfaceVariant, 0.16)
                    border.width: 1
                    border.color: active ? colors.alpha(colors.primary, 0.32) : colors.alpha(colors.outline, 0.08)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    // v2: side rails removed — the file chip carries the accent
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 10
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: colors.alpha(root.fileAccent(modelData.file), 0.16)
                            border.width: 1
                            border.color: colors.alpha(root.fileAccent(modelData.file), 0.4)
                            Layout.alignment: Qt.AlignVCenter
                            Text {
                                anchors.centerIn: parent
                                text: root.fileGlyph(modelData.file)
                                color: root.fileAccent(modelData.file)
                                font.family: colors.fontSans
                                font.pixelSize: 11
                            }
                        }
                        ColumnLayout {
                            id: rowCol
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            // line 1 — name : line  ·  ~/dir
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: root.baseName(modelData.file)
                                    color: colors.foreground
                                    font.family: colors.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: ":" + modelData.line
                                    color: rowRoot.active ? colors.primary : colors.alpha(colors.outline, 0.7)
                                    font.family: colors.fontSans
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                                Text {
                                    text: root.relDir(modelData.file)
                                    color: colors.alpha(colors.outline, 0.5)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                            }
                            // line 2 — snippet with the hit highlighted (content hits only)
                            RowLayout {
                                visible: modelData.isFile !== true
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: rowRoot.parts.pre
                                    color: colors.alpha(colors.outline, 0.75)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                Text {
                                    text: rowRoot.parts.hit
                                    visible: rowRoot.parts.hit !== ""
                                    color: colors.primary
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                Text {
                                    text: rowRoot.parts.post
                                    color: colors.alpha(colors.outline, 0.75)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    Layout.fillWidth: true
                                }
                            }
                        }
                        Rectangle {
                            visible: modelData.isFile === true
                            Layout.preferredWidth: 38; Layout.preferredHeight: 18; radius: 9
                            color: colors.alpha(colors.tertiary, 0.16)
                            border.width: 1; border.color: colors.alpha(colors.tertiary, 0.4)
                            Layout.alignment: Qt.AlignVCenter
                            Text { anchors.centerIn: parent; text: "FILE"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1 }
                        }
                        Text {
                            text: "→"
                            color: rowRoot.active ? colors.primary : colors.alpha(colors.outline, 0.35)
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


            // empty state — fills the void before the first search
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.results.length === 0
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: "Type at least 2 characters"
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans; font.pixelSize: 10
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "@path  scopes one directory"
                        color: colors.alpha(colors.outline, 0.4)
                        font.family: colors.fontSans; font.pixelSize: 9
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // footer — kbd hints, no X per house rule
            Row {
                spacing: 12
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: [ { k: "↑↓", a: "move" }, { k: "↵", a: "nano" }, { k: "^O", a: "zed" }, { k: "^Y", a: "copy" }, { k: "^U", a: "clear" }, { k: "esc", a: "clear/close" } ]
                    delegate: Row {
                        required property var modelData
                        spacing: 4
                        Rectangle {
                            width: Math.max(22, kbdTxt.implicitWidth + 10)
                            height: 16
                            radius: 4
                            color: colors.alpha(colors.surfaceVariant, 0.5)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: kbdTxt
                                anchors.centerIn: parent
                                text: modelData.k
                                color: colors.secondary
                                font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold
                            }
                        }
                        Text {
                            text: modelData.a
                            color: colors.alpha(colors.outline, 0.45)
                            font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
