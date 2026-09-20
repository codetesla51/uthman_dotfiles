import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Dictionary — instant word lookup via dictionaryapi.dev (no key, no auth),
// related words via Datamuse. Type + Enter, synonyms/antonyms/related chips
// are clickable (drill down without retyping), audio plays via mpv.
// Session cache: repeat lookups never hit the network twice.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    // state: idle | loading | done | error
    property string state: "idle"
    property string errMsg: ""
    property var entry: null          // {word, phonetic, audio, meanings[], sourceUrl}
    property var relatedSyn: []
    property var relatedSound: []
    property var history: []
    property var cache: ({})

    title: "Dictionary"
    implicitWidth: 560
    implicitHeight: 500
    minimumSize: Qt.size(480, 400)
    maximumSize: Qt.size(700, 620)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "dict"
        function toggle(): void { root.open = !root.open }
        function lookup(word: string): void { root.open = true; root.lookup(word) }
    }

    onOpenChanged: {
        if (open) Qt.callLater(function() { searchField.forceActiveFocus() })
    }

    // --- HTTP via curl Process, not QML XHR: Qt's network stack fails
    // these hosts with status 0 (verified in qslog), while curl works.
    // Same Process-driven pattern as every other module in this shell.
    property bool dictBusy: false
    property string dictQueued: ""
    property bool mirror: false
    property int _seq: 0
    property bool dmBusy: false
    property var dmQueued: null
    property string _dmRel: ""
    property string _dmW: ""
    property int _dmSeq: 0
    property string _dmKind: ""

    Process {
        id: dictProc
        onExited: function(code) { console.log("DICT exited code=" + code + " busy=" + root.dictBusy) }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.dictBusy = false
                if (root.dictQueued !== "") {
                    var q = root.dictQueued
                    root.dictQueued = ""
                    root.runDict(q)
                    return
                }
                if (root.state !== "loading") return
                var trimmed = text.trimEnd()
                var idx = trimmed.lastIndexOf("\n")
                var code = idx !== -1 ? trimmed.slice(idx + 1).trim() : ""
                var body = idx !== -1 ? trimmed.slice(0, idx) : trimmed
                console.log("DICT code=" + code + " len=" + body.length + (root.mirror ? " mirror" : ""))
                if (root.mirror) root.onWikiResult(code, body)
                else root.onDictResult(code, body)
            }
        }
    }
    Process {
        id: dmProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.dmBusy = false
                var words = []
                try {
                    var arr = JSON.parse(text)
                    for (var i = 0; i < arr.length && words.length < 8; i++)
                        if (arr[i].word) words.push(arr[i].word)
                } catch (e) {}
                if (root._dmSeq === root._seq) {
                    if (root._dmKind === "syn") {
                        root.relatedSyn = words
                        root.writeCache()
                        root.fetchDm("sl", root._dmW, root._dmSeq, "sound")
                    } else {
                        root.relatedSound = words
                        root.writeCache()
                    }
                }
                if (root.dmQueued !== null) {
                    var nq = root.dmQueued
                    root.dmQueued = null
                    root.fetchDm(nq.rel, nq.w, nq.seq, nq.kind)
                }
            }
        }
    }
    function runDict(w) {
        console.log("DICT runDict w=" + w + " busy=" + root.dictBusy)
        if (root.dictBusy) { root.dictQueued = w; return }
        root.dictBusy = true
        root.dictQueued = ""
        root.mirror = false
        dictProc.command = ["curl", "-s", "--max-time", "30", "-o", "/tmp/dict-result.json", "-w", "\n%{http_code}",
            "https://api.dictionaryapi.dev/api/v2/entries/en/" + w]
        dictProc.running = true
    }
    function onDictResult(code, body) {
        var w = searchField.text.trim().toLowerCase()
        if (code === "200") {
            try {
                root.applyEntry(JSON.parse(body))
            } catch (e) {
                root.runWiki(w)
            }
        } else {
            root.runWiki(w)
        }
    }
    // Wiktionary mirror — dictionaryapi.dev stalls from some routes;
    // this answers in <1s with plain definitions (no audio/synonyms).
    function runWiki(w) {
        root.mirror = true
        dictProc.command = ["curl", "-s", "--max-time", "15", "-w", "\n%{http_code}",
            "https://en.wiktionary.org/api/rest_v1/page/definition/" + w]
        dictProc.running = true
    }
    function onWikiResult(code, body) {
        var w = searchField.text.trim().toLowerCase()
        if (code === "200") {
            try {
                root.applyWikiEntry(JSON.parse(body), w)
                return
            } catch (e) {}
        }
        root.state = "error"
        if (code === "404")
            root.errMsg = "No definition found for \"" + w + "\". Check the spelling."
        else
            root.errMsg = "Both sources failed (network error). Check your connection and retry."
    }
    function stripHtml(s) { return String(s || "").replace(/<[^>]*>/g, "") }
    function applyWikiEntry(obj, w) {
        var en = obj.en || []
        var meanings = []
        for (var m = 0; m < en.length; m++) {
            var defs = []
            var dd = en[m].definitions || []
            for (var k = 0; k < dd.length && defs.length < 5; k++) {
                var dt = stripHtml(dd[k].definition)
                if (dt === "") continue
                var exs = dd[k].examples || []
                defs.push({ def: dt, example: exs.length > 0 ? stripHtml(exs[0]) : "", synonyms: [], antonyms: [] })
            }
            if (defs.length > 0)
                meanings.push({ pos: en[m].partOfSpeech || "", defs: defs, synonyms: [], antonyms: [] })
        }
        if (meanings.length === 0) {
            state = "error"
            errMsg = "No English definitions found for \"" + w + "\"."
            return
        }
        entry = { word: w, phonetic: "", audio: "", meanings: meanings,
                  sourceUrl: "https://en.wiktionary.org/wiki/" + w }
        state = "done"
        console.log("DICT done (wiki) word=" + w + " meanings=" + meanings.length)
        touchHistory(w)
        fireRelated(w, entry)
    }

    function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function lookup(raw) {
        console.log("DICT lookup called raw=" + raw)
        var w = String(raw || "").trim().toLowerCase()
        if (w === "") return
        if (!/^[a-zA-Z]+([ '-][a-zA-Z]+)*$/.test(w)) {
            state = "error"
            entry = null
            errMsg = "Letters, hyphens and apostrophes only — try a single English word."
            return
        }
        if (searchField.text !== w) searchField.text = w
        var hit = cache[w]
        if (hit) {
            _seq++
            entry = hit.entry
            relatedSyn = hit.syn
            relatedSound = hit.sound
            state = "done"
            errMsg = ""
            touchHistory(w)
            return
        }
        _seq++
        state = "loading"
        errMsg = ""
        entry = null
        relatedSyn = []
        relatedSound = []
        root.runDict(w)
    }

    function applyEntry(arr) {
        if (!arr || arr.length === 0) {
            state = "error"
            errMsg = "Empty response. Try again."
            return
        }
        var d = arr[0]
        var phonetic = d.phonetic || ""
        var audio = ""
        var phs = d.phonetics || []
        for (var i = 0; i < phs.length; i++) {
            if (!phonetic && phs[i].text) phonetic = phs[i].text
            if (!audio && phs[i].audio) audio = phs[i].audio
        }
        var meanings = []
        var ms = d.meanings || []
        for (var m = 0; m < ms.length; m++) {
            var defs = []
            var dd = ms[m].definitions || []
            for (var k = 0; k < dd.length; k++) {
                defs.push({
                    def: dd[k].definition || "",
                    example: dd[k].example || "",
                    synonyms: (dd[k].synonyms || []).slice(0, 6),
                    antonyms: (dd[k].antonyms || []).slice(0, 6)
                })
            }
            meanings.push({
                pos: ms[m].partOfSpeech || "",
                defs: defs,
                synonyms: (ms[m].synonyms || []).slice(0, 8),
                antonyms: (ms[m].antonyms || []).slice(0, 8)
            })
        }
        var src = ""
        if (d.sourceUrls && d.sourceUrls.length > 0) src = d.sourceUrls[0]
        var e = { word: d.word || "", phonetic: phonetic, audio: audio, meanings: meanings, sourceUrl: src }
        entry = e
        state = "done"
        console.log("DICT done word=" + e.word + " meanings=" + meanings.length)
        touchHistory(e.word)
        fireRelated(e.word, e)
    }

    function touchHistory(w) {
        var h = []
        h.push(w)
        for (var i = 0; i < history.length; i++)
            if (history[i] !== w) h.push(history[i])
        history = h.slice(0, 12)
    }

    function writeCache() {
        if (!entry || !entry.word) return
        cache[entry.word] = { entry: entry, syn: relatedSyn, sound: relatedSound }
    }

    function fireRelated(w, e) {
        var seq = _seq
        fetchDm("rel_syn", w, seq, "syn")
    }

    function fetchDm(rel, w, seq, kind) {
        if (root.dmBusy) { root.dmQueued = { rel: rel, w: w, seq: seq, kind: kind }; return }
        root.dmBusy = true
        root.dmQueued = null
        root._dmRel = rel
        root._dmW = w
        root._dmSeq = seq
        root._dmKind = kind
        dmProc.command = ["curl", "-s", "--max-time", "15",
            "https://api.datamuse.com/words?" + rel + "=" + w + "&max=8"]
        dmProc.running = true
    }

    function playAudio() {
        if (entry && entry.audio)
            Quickshell.execDetached(["mpv", "--no-video", "--really-quiet", entry.audio])
    }

    function copyEntry() {
        if (!entry || !entry.meanings.length || !entry.meanings[0].defs.length) return
        var txt = entry.word + " (" + entry.meanings[0].pos + ") — " + entry.meanings[0].defs[0].def
        Quickshell.execDetached(["sh", "-c", "printf %s " + shQuote(txt) + " | wl-copy && notify-send -u low -a 'Dictionary' 'Copied' " + shQuote(entry.word)])
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // header — no X: Esc closes, hub tile reopens
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.tertiary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.3)
                    Text { anchors.centerIn: parent; text: ""; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "DICTIONARY"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                Text { text: "esc closes"; color: colors.alpha(colors.outline, 0.4); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignVCenter }
            }

            // search bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                radius: 12
                color: colors.alpha(colors.surface, 0.6)
                border.width: 1
                border.color: searchField.activeFocus ? colors.alpha(colors.tertiary, 0.5) : colors.alpha(colors.outline, 0.15)
                Behavior on border.color { ColorAnimation { duration: 150 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 8
                    spacing: 8
                    Text { text: "Aa"; color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold; Layout.alignment: Qt.AlignVCenter }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        placeholderText: "Type a word, hit Enter…"
                        placeholderTextColor: colors.alpha(colors.outline, 0.5)
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 14
                        selectByMouse: true
                        background: null
                        onAccepted: root.lookup(text)
                        Keys.onEscapePressed: root.open = false
                    }
                    Rectangle {
                        width: 64; height: 28; radius: 9
                        color: goMa.containsMouse ? colors.alpha(colors.tertiary, 0.28) : colors.alpha(colors.tertiary, 0.13)
                        border.width: 1; border.color: colors.alpha(colors.tertiary, 0.4)
                        Text { anchors.centerIn: parent; text: root.state === "loading" ? "…" : "define"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                        MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(searchField.text) }
                    }
                }
            }

            // recent history
            RowLayout {
                visible: root.history.length > 0
                Layout.fillWidth: true
                spacing: 6
                Text { text: "RECENT"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: root.history
                        delegate: Rectangle {
                            required property var modelData
                            width: histLbl.implicitWidth + 18; height: 22; radius: 11
                            color: histMa.containsMouse ? colors.alpha(colors.tertiary, 0.22) : colors.alpha(colors.surface, 0.6)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                            Text { id: histLbl; anchors.centerIn: parent; text: modelData; color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 9 }
                            MouseArea { id: histMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(modelData) }
                        }
                    }
                }
            }

            Rectangle { visible: root.history.length > 0; Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // ---- body states ----
            // idle hint
            Item {
                visible: root.state === "idle"
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: ""; color: colors.alpha(colors.outline, 0.3); font.family: colors.fontSans; font.pixelSize: 30; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "Look up any English word — definitions, examples, synonyms."; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // loading
            Item {
                visible: root.state === "loading"
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "↻"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 26
                        Layout.alignment: Qt.AlignHCenter
                        RotationAnimation on rotation { running: root.state === "loading"; loops: Animation.Infinite; duration: 1200; from: 0; to: 360 }
                    }
                    Text { text: root.mirror ? "Trying mirror…" : "Looking up…"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 10; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // error — icon + reason + retry, not a bare red strip
            Rectangle {
                visible: root.state === "error"
                Layout.fillWidth: true
                Layout.preferredHeight: errCol.implicitHeight + 28
                radius: 12
                color: colors.alpha(colors.error, 0.07)
                border.width: 1; border.color: colors.alpha(colors.error, 0.3)
                ColumnLayout {
                    id: errCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    spacing: 6
                    Rectangle {
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                        color: colors.alpha(colors.error, 0.14)
                        border.width: 1; border.color: colors.alpha(colors.error, 0.4)
                        Text { anchors.centerIn: parent; text: "!"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold }
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text { text: "No definition found"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                    Text { text: root.errMsg; color: colors.alpha(colors.foreground, 0.75); font.family: colors.fontSans; font.pixelSize: 10; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
                    Rectangle {
                        width: 76; height: 26; radius: 13
                        color: retryMa.containsMouse ? colors.alpha(colors.tertiary, 0.28) : colors.alpha(colors.tertiary, 0.12)
                        border.width: 1; border.color: colors.alpha(colors.tertiary, 0.4)
                        Text { anchors.centerIn: parent; text: "retry"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                        MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(searchField.text) }
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // results
            ScrollView {
                id: dictScroll
                visible: root.state === "done" && root.entry !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                contentWidth: availableWidth
                contentHeight: resultCol.implicitHeight

                ColumnLayout {
                    id: resultCol
                    width: dictScroll.availableWidth
                    spacing: 10

                    // word hero
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: heroCol.implicitHeight + 24
                        radius: 14
                        color: colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: colors.alpha(colors.tertiary, 0.3)
                        ColumnLayout {
                            id: heroCol
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16; anchors.rightMargin: 12
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text { text: root.entry ? root.entry.word : ""; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 20; font.weight: Font.ExtraBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Rectangle {
                                    visible: root.entry && root.entry.audio !== ""
                                    width: 26; height: 26; radius: 13
                                    color: audioMa.containsMouse ? colors.alpha(colors.tertiary, 0.28) : colors.alpha(colors.tertiary, 0.12)
                                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.4)
                                    Text { anchors.centerIn: parent; text: "♪"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 12 }
                                    MouseArea { id: audioMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.playAudio() }
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 13
                                    color: copyMa.containsMouse ? colors.alpha(colors.secondary, 0.28) : "transparent"
                                    border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                                    Text { anchors.centerIn: parent; text: "⧉"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 12 }
                                    MouseArea { id: copyMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.copyEntry() }
                                }
                            }
                            Text {
                                visible: root.entry && root.entry.phonetic !== ""
                                text: root.entry ? root.entry.phonetic : ""
                                color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 11
                            }
                        }
                    }

                    // meanings
                    Repeater {
                        model: root.entry ? root.entry.meanings : []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: (modelData.pos || "").toUpperCase(); color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }

                            Repeater {
                                model: modelData.defs
                                delegate: ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: (index + 1) + "."; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold; Layout.alignment: Qt.AlignTop }
                                        Text { text: modelData.def; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                                    }
                                    Text {
                                        visible: modelData.example !== ""
                                        text: "“" + modelData.example + "”"
                                        color: colors.alpha(colors.outline, 0.75); font.family: colors.fontSans; font.pixelSize: 10; font.italic: true
                                        wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.leftMargin: 22
                                    }
                                    Flow {
                                        visible: modelData.synonyms.length > 0 || modelData.antonyms.length > 0
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 22
                                        spacing: 5
                                        Repeater {
                                            model: modelData.synonyms
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: synLbl.implicitWidth + 16; height: 20; radius: 10
                                                color: synMa.containsMouse ? colors.alpha(colors.secondary, 0.28) : colors.alpha(colors.secondary, 0.1)
                                                border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                                                Text { id: synLbl; anchors.centerIn: parent; text: modelData; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 8 }
                                                MouseArea { id: synMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(modelData) }
                                            }
                                        }
                                        Repeater {
                                            model: modelData.antonyms
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: antLbl.implicitWidth + 16; height: 20; radius: 10
                                                color: antMa.containsMouse ? colors.alpha(colors.error, 0.28) : colors.alpha(colors.error, 0.08)
                                                border.width: 1; border.color: colors.alpha(colors.error, 0.35)
                                                Text { id: antLbl; anchors.centerIn: parent; text: "≠ " + modelData; color: colors.error; font.family: colors.fontSans; font.pixelSize: 8 }
                                                MouseArea { id: antMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(modelData) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // related (Datamuse)
                    ColumnLayout {
                        visible: root.relatedSyn.length > 0 || root.relatedSound.length > 0
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "RELATED"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Flow {
                            visible: root.relatedSyn.length > 0
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: root.relatedSyn
                                delegate: Rectangle {
                                    required property var modelData
                                    width: rsLbl.implicitWidth + 16; height: 20; radius: 10
                                    color: rsMa.containsMouse ? colors.alpha(colors.primary, 0.28) : colors.alpha(colors.primary, 0.1)
                                    border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                                    Text { id: rsLbl; anchors.centerIn: parent; text: modelData; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8 }
                                    MouseArea { id: rsMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(modelData) }
                                }
                            }
                        }
                        Flow {
                            visible: root.relatedSound.length > 0
                            Layout.fillWidth: true
                            spacing: 5
                            Text { text: "sounds like:"; color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                            Repeater {
                                model: root.relatedSound
                                delegate: Rectangle {
                                    required property var modelData
                                    width: rhLbl.implicitWidth + 16; height: 20; radius: 10
                                    color: rhMa.containsMouse ? colors.alpha(colors.outline, 0.3) : "transparent"
                                    border.width: 1; border.color: colors.alpha(colors.outline, 0.3)
                                    Text { id: rhLbl; anchors.centerIn: parent; text: modelData; color: colors.alpha(colors.foreground, 0.8); font.family: colors.fontSans; font.pixelSize: 8 }
                                    MouseArea { id: rhMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.lookup(modelData) }
                                }
                            }
                        }
                    }

                    // source
                    RowLayout {
                        visible: root.entry && root.entry.sourceUrl !== ""
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Source: wiktionary"; color: colors.alpha(colors.outline, 0.45); font.family: colors.fontSans; font.pixelSize: 8; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text {
                            text: "open →"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: if (root.entry) Quickshell.execDetached(["xdg-open", root.entry.sourceUrl]) }
                        }
                    }
                }
            }
        }
    }
}
