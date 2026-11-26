import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0
import "../components/Bloom.js" as Bloom

// App Launcher — Spotlight-style, replaces rofi.
// SUPER+SPACE to toggle. Type to fuzzy-search, ↑↓ to navigate, Enter to launch, Esc to close.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property int selected: 0

    // One-shot cascade state: rearm on open, never on typing.
    property bool cascading: false
    property int cascadeToken: 0
    // Bumped on launch, written to the usage DB only after the close animation.
    property string pendingUsage: ""

    visible: root.open || closeAnim.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-launcher"
    focusable: true

    IpcHandler { target: "launcher"; function toggle(): void { root.open = !root.open } }

    Component.onCompleted: loadStores()
    onOpenChanged: {
        if (open) {
            search.text = ""            // before cascading=true: textChanged clears the flag
            root.cascading = true
            root.cascadeToken++
            root.selected = 0
            resultList.positionViewAtBeginning()
            flashAnim.restart()
            openAnim.restart()
            cascadeEnd.restart()
            Qt.callLater(function () { search.forceActiveFocus() })
        } else {
            openAnim.stop()
            flashAnim.stop()
            closeAnim.restart()
        }
    }
    Timer { id: cascadeEnd; interval: 900; onTriggered: root.cascading = false }

    // ── data ────────────────────────────────────────────────────
    readonly property var denylist: ["rofi","kvantum","qv4l2","qt5ct","qt6ct","v4l2 test","logseq","printer","assistant","ava","btop","htop","xterm","uxterm","kvantummanager"]
    // word-boundary matches: "ava" no longer hides Java apps, "rofi" no longer hides "profile"
    readonly property var denyRes: denylist.map(function (d) { return new RegExp("\\b" + d + "\\b") })
    property var usageMap: ({})
    property var usageLast: ({})

    function denied(e) {
        var n = (e.name || "").toLowerCase(), id = (e.id || "").toLowerCase()
        for (var i = 0; i < denyRes.length; i++)
            if (denyRes[i].test(n) || denyRes[i].test(id)) return true
        return false
    }

    readonly property var storeApps: DesktopEntries.applications.values.filter(function (e) {
        if (e.noDisplay) return false
        if (!e.icon) return false
        return !denied(e)
    })

    // Glyphs restored from the previous launcher — the pasted copy lost them.
    readonly property var pluginApps: [
        { id: "qs-pomodoro",   name: "Pomodoro",     genericName: "focus timer · stats",            comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "pomodoro" },
        { id: "qs-github",     name: "GitHub",       genericName: "notifs · PRs · heatmap",         comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "github" },
        { id: "qs-notes",      name: "Quick Notes",  genericName: "idea capture · draggable",       comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "notes" },
        { id: "qs-screentime", name: "Screen Time",  genericName: "usage heatmaps · app ranks",     comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "screentime" },
        { id: "qs-phonebridge",name: "PhoneBridge",  genericName: "send & pull files over ADB",     comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "phonebridge" },
        { id: "qs-drives",     name: "Drive Health", genericName: "SMART + RAM + speed test",       comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "drives" },
        { id: "qs-monitors",   name: "Monitors",     genericName: "DPI / scale · rotate · display", comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "monitors" },
        { id: "qs-failwatch",  name: "FailWatch",    genericName: "failed units · journal errors",  comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "failwatch" },
        { id: "qs-dict",       name: "Dictionary",   genericName: "definitions · synonyms · audio", comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "dict" },
        { id: "qs-grap",       name: "Grap",         genericName: "instant file search · grep",     comment: "quickshell plugin", keywords: [], glyph: "", qsTarget: "grap" },
    ]
    readonly property var allApps: storeApps.concat(pluginApps)

    function db() { return LocalStorage.openDatabaseSync("qs_launcher", "1.0", "launcher", 100000) }
    function loadStores() {
        db().transaction(function (tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage(id TEXT PRIMARY KEY, count INTEGER, last INTEGER DEFAULT 0)')
            // migrate old tables only if the column is actually missing (no throw on every start)
            var info = tx.executeSql('PRAGMA table_info(usage)'), has = false
            for (var k = 0; k < info.rows.length; k++) if (info.rows.item(k).name === "last") has = true
            if (!has) tx.executeSql('ALTER TABLE usage ADD COLUMN last INTEGER DEFAULT 0')
            var r = tx.executeSql('SELECT * FROM usage'), m = {}, l = {}
            for (var i = 0; i < r.rows.length; i++) {
                var row = r.rows.item(i)
                m[row.id] = row.count
                l[row.id] = row.last || 0
            }
            usageMap = m; usageLast = l
        })
    }
    function usageScore(id) {
        var c = usageMap[id] || 0
        var s = Math.log2(1 + c) * 2
        var age = Date.now() - (usageLast[id] || 0)
        if (age < 86400000) s += 6
        else if (age < 604800000) s += 3
        return s
    }
    function bumpUsage(id) {
        var now = Date.now()
        db().transaction(function (tx) {
            tx.executeSql('INSERT OR REPLACE INTO usage VALUES(?, COALESCE((SELECT count FROM usage WHERE id=?),0)+1, ?)', [id, id, now])
        })
        var m = JSON.parse(JSON.stringify(usageMap)); m[id] = (m[id] || 0) + 1; usageMap = m
        var l = JSON.parse(JSON.stringify(usageLast)); l[id] = now; usageLast = l
    }
    // usage is bumped after the close animation, so rows never reshuffle while fading out
    function flushUsage() {
        if (root.pendingUsage === "") return
        var id = root.pendingUsage
        root.pendingUsage = ""
        bumpUsage(id)
    }

    function subseq(q, s) {
        var i = 0
        for (var j = 0; j < s.length && i < q.length; j++) if (s[j] === q[i]) i++
        return i === q.length
    }

    readonly property var filtered: {
        var q = search.text.trim().toLowerCase()
        if (q === "") {
            var copy = allApps.slice()
            copy.sort(function (a, b) {
                var ca = usageScore(a.id), cb = usageScore(b.id)
                if (ca !== cb) return cb - ca
                return a.name.localeCompare(b.name)
            })
            return copy.slice(0, 50)
        }
        var scored = []
        for (var i = 0; i < allApps.length; i++) {
            var e = allApps[i]
            var name = e.name.toLowerCase()
            var gen = (e.genericName || "").toLowerCase()
            var score = -1
            if (name.startsWith(q)) score = 0
            else if (name.includes(q)) score = 1
            else if (gen.includes(q)) score = 2
            else if (!e.qsTarget) {
                // comment/keywords only count for real apps — plugins all share the
                // same boilerplate and used to flood results for "s", "pl", "shell"
                var kw = ""
                try { kw = e.keywords ? e.keywords.join(" ") : "" } catch (e2) {}
                if ((kw + " " + (e.comment || "")).toLowerCase().includes(q)) score = 3
            }
            if (score < 0 && q.length > 1 && subseq(q, name)) score = 4   // fuzzy: "ghb" → GitHub
            if (score < 0) continue
            // tiers differ by 1; usage is at most ~0.2, so it only orders within a tier
            score -= usageScore(e.id) / 100
            scored.push({ e: e, score: score })
        }
        scored.sort(function (a, b) {
            if (a.score !== b.score) return a.score - b.score
            return a.e.name.localeCompare(b.e.name)
        })
        return scored.slice(0, 50).map(function (x) { return x.e })
    }

    function launch(entry) {
        if (!entry) return
        root.pendingUsage = entry.id
        root.open = false
        Qt.callLater(function () {
            if (entry.qsTarget)
                Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", entry.qsTarget, "toggle"])
            else if (entry.runInTerminal && entry.command && entry.command.length > 0)
                Quickshell.execDetached(["uwsm-app", "--", "kitty", "-e"].concat(entry.command))
            else
                entry.execute()
        })
    }

    // ── backdrop: faint dim + click-outside catcher ─────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.22 * shell.reveal)
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Item {
        id: shell
        anchors.horizontalCenter: parent.horizontalCenter
        // constant size + fixed position: the card unrolls inside it, nothing recenters
        width: 600
        height: barItem.height + gap + cardFullH
        y: Math.round((parent.height - height) / 2)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        readonly property int gap: 10
        readonly property int rowH: 52
        readonly property int rowGap: 3
        readonly property int footerH: 40
        readonly property int listH: 7 * (rowH + rowGap) - rowGap
        readonly property int cardFullH: 7 + listH + footerH

        // ONE timeline drives bar, card, rows' container and backdrop.
        property real reveal: 0
        readonly property real barP: Math.min(1, reveal / 0.40)
        readonly property real cardP: Math.min(1, Math.max(0, (reveal - 0.10) / 0.90))
        // Qt wants 6 numbers: (x1,y1,x2,y2,1,1). The old 4-value curve was ignored → linear.
        readonly property var outCurve: [0.22, 1, 0.36, 1, 1, 1]

        NumberAnimation {
            id: openAnim
            target: shell; property: "reveal"; to: 1
            duration: 600; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve
        }
        NumberAnimation {
            id: closeAnim
            target: shell; property: "reveal"; to: 0
            duration: 260; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve
            onFinished: root.flushUsage()
        }
        SequentialAnimation {
            id: flashAnim
            ColorAnimation { target: barItem; property: "border.color"; from: colors.alpha(colors.outline, 0); to: colors.alpha(colors.primary, 0.9); duration: 130; easing.type: Easing.OutCubic }
            ColorAnimation { target: barItem; property: "border.color"; to: colors.alpha(colors.outline, 0.18); duration: 260; easing.type: Easing.OutCubic }
        }

        // ── search bar ──────────────────────────────────────────
        Rectangle {
            id: barItem
            z: 2
            width: parent.width
            height: 58
            radius: 18
            color: colors.alpha(colors.surface, 0.78)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.18)
            opacity: shell.barP
            scale: 0.94 + 0.06 * shell.barP
            transform: Translate { y: -8 * (1 - shell.barP) }

            MouseArea { anchors.fill: parent }   // swallow clicks so dead space doesn't close the launcher

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Image {
                    source: Quickshell.env("HOME") + "/.config/quickshell/assets/hk-mask-white.png"
                    sourceClipRect: Qt.rect(131, 56, 237, 388)
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    fillMode: Image.PreserveAspectFit
                    mipmap: true
                    asynchronous: true
                    opacity: 0.95
                }

                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: "Search apps…"
                    placeholderTextColor: colors.alpha(colors.outline, 0.5)
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 17
                    background: null
                    selectByMouse: true
                    Keys.onPressed: function (event) {
                        var n = root.filtered.length
                        if (event.key === Qt.Key_Down) {
                            root.selected = Math.min(root.selected + 1, n - 1)
                            resultList.positionViewAtIndex(root.selected, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.selected = Math.max(root.selected - 1, 0)
                            resultList.positionViewAtIndex(root.selected, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.open = false; event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.launch(root.filtered[Math.min(root.selected, n - 1)])
                            event.accepted = true
                        }
                    }
                    onTextChanged: {
                        root.cascading = false          // typing never replays the cascade
                        root.selected = 0
                        resultList.positionViewAtBeginning()
                    }
                }

                Text {
                    visible: search.text !== ""
                    text: "󰅖"
                    color: clearMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 13
                    MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: search.text = "" }
                }

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 22
                    radius: 6
                    color: colors.alpha(colors.foreground, 0.06)
                    Text {
                        anchors.centerIn: parent
                        text: "esc"
                        color: colors.alpha(colors.outline, 0.7)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                    }
                }
            }
        }

        // ── results card: height unrolls from the top (no scale-from-30%) ──
        Rectangle {
            id: resultsCard
            y: barItem.height + shell.gap
            width: parent.width
            height: shell.cardFullH * shell.cardP
            radius: 18
            clip: true
            color: colors.alpha(colors.surface, 0.78)
            opacity: Math.min(1, shell.cardP * 2.5)

            MouseArea { anchors.fill: parent }

            // fixed-size content; slides down slightly as the card unrolls
            Item {
                id: cardContent
                width: parent.width
                height: shell.cardFullH
                y: -12 * (1 - shell.cardP)

                Item {
                    id: listArea
                    anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 7; leftMargin: 7; rightMargin: 7 }
                    height: shell.listH
                    clip: true

                    ListView {
                        id: resultList
                        anchors.fill: parent
                        visible: root.filtered.length > 0
                        clip: true
                        // ScriptModel diffs by value: typing moves/removes rows instead of
                        // resetting the whole view (that reset was the "reload" feel)
                        model: ScriptModel { values: root.filtered }
                        spacing: shell.rowGap
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 3
                            padding: 0
                            background: Item {}
                            contentItem: Rectangle {
                                implicitWidth: 3
                                radius: 1.5
                                color: colors.alpha(colors.outline, 0.32)
                            }
                        }

                        // one sliding selection pill (child of the flickable → lives in contentItem)
                        Rectangle {
                            id: pill
                            z: 0
                            width: resultList.width
                            height: shell.rowH
                            radius: 12
                            color: colors.alpha(colors.primary, 0.17)
                            visible: root.filtered.length > 0
                            y: root.selected * (shell.rowH + shell.rowGap)
                            // only animate once the card is mostly open, so it doesn't swim during the reveal
                            Behavior on y {
                                enabled: shell.cardP > 0.6
                                NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                            }
                        }

                        delegate: Item {
                            id: rowRoot
                            required property var modelData
                            required property int index
                            z: 1
                            width: resultList.width
                            height: shell.rowH

                            // 0→1 on open only. Rows created while typing start at 1.
                            property real p: root.cascading ? 0 : 1
                            opacity: p
                            transform: Translate { y: 10 * (1 - rowRoot.p) }
                            NumberAnimation {
                                id: pAnim
                                target: rowRoot; property: "p"; to: 1
                                duration: 420; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve
                            }
                            Timer {
                                id: rowTimer
                                interval: 120 + Math.min(rowRoot.index, 11) * 24
                                onTriggered: pAnim.restart()
                            }
                            Component.onCompleted: if (root.cascading) rowTimer.restart()
                            Connections {
                                target: root
                                function onCascadeTokenChanged() {
                                    pAnim.stop()
                                    rowRoot.p = 0
                                    rowTimer.restart()
                                }
                            }

                            // hover tone only; selection is the pill
                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: (index !== root.selected && ma.containsMouse) ? colors.alpha(colors.foreground, 0.045) : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Item {
                                    Layout.preferredWidth: 24
                                    Layout.preferredHeight: 24
                                    scale: index === root.selected ? 1.1 : 1
                                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        // plugins without a glyph used to show a folder icon; now they get the letter mark
                                        source: {
                                            if (modelData.glyph || modelData.qsTarget) return ""
                                            if (!modelData.icon) return Quickshell.iconPath("folder")
                                            var ic = modelData.icon
                                            if (ic === "org.gnome.Nautilus") ic = "system-file-manager"
                                            if (ic === "org.gnome.DiskUtility") ic = "drive-harddisk"
                                            if (ic.startsWith("/") || ic.startsWith("file://")) return ic.startsWith("file://") ? ic : "file://" + ic
                                            return Quickshell.iconPath(ic)
                                        }
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        visible: status === Image.Ready
                                        onStatusChanged: {
                                            if (status === Image.Error) {
                                                var fb = Quickshell.iconPath("folder")
                                                if (source !== fb) source = fb
                                            }
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: appIcon.status !== Image.Ready
                                        text: modelData.glyph ? modelData.glyph : (modelData.name ? modelData.name.charAt(0).toUpperCase() : "?")
                                        color: colors.primary
                                        font.family: modelData.glyph ? "Phosphor" : colors.fontSans
                                        font.pixelSize: modelData.glyph ? 17 : 13
                                        font.weight: Font.ExtraBold
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        text: modelData.name
                                        color: colors.foreground
                                        font.family: colors.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: modelData.genericName || modelData.comment || modelData.id
                                        color: colors.alpha(colors.outline, 0.85)
                                        font.family: colors.fontSans
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                Text {
                                    text: "↵"
                                    opacity: index === root.selected ? 1 : 0
                                    x: 0
                                    color: colors.alpha(colors.primary, 0.9)
                                    font.family: colors.fontSans
                                    font.pixelSize: 10
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }
                            }

                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                // positionChanged (not entered): rows scrolling under a still
                                // cursor can't steal selection, and open doesn't auto-highlight
                                onPositionChanged: root.selected = index
                                onClicked: root.launch(modelData)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.filtered.length === 0
                        text: "No results"
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 11
                    }
                }

                Item {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: shell.footerH
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14
                        Text { text: "↑↓ move";  color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                        Text { text: "↵ open";   color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                        Text { text: "esc close"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 10 }
                        Item { Layout.fillWidth: true }
                        Text {
                            visible: root.filtered.length > 0
                            text: root.filtered.length + (root.filtered.length === 1 ? " app" : " apps")
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: colors.fontSans
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
