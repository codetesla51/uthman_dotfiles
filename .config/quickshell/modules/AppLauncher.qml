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

    visible: root.open || closeAnim.running
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "qs-launcher"
    focusable: true

    IpcHandler { target: "launcher"; function toggle(): void { root.open = !root.open } }

    // reset state on open/close
    property bool allowHover: false
    Component.onCompleted: loadStores()
    onOpenChanged: {
        if (open) { closeAnim.stop(); flashAnim.restart(); search.text = ""; selected = filtered.length > 0 ? 0 : -1; allowHover = false; Qt.callLater(function(){ search.forceActiveFocus() }); openAnim.restart() }
        else { openAnim.stop(); flashAnim.stop(); closeAnim.restart() }
    }
    // no timer — hover enables on first mouse move only, so open doesn't auto-highlight

    // denylist — system junk the user never launches; edit this array to hide more
    readonly property var denylist: ["rofi","kvantum","qv4l2","qt5ct","qt6ct","v4l2 test","logseq","printer","assistant","ava","btop","htop","xterm","uxterm","kvantummanager"]
    // usage ranking is fully automatic: every launch bumps count + timestamp,
    // and the score blends both (log-scaled count + recency bonus). No manual
    // starring — the system learns purely from what you actually open.
    property var usageMap: ({})
    property var usageLast: ({})

    readonly property var storeApps: DesktopEntries.applications.values.filter(e => {
        if (e.noDisplay) return false
        if (!e.icon) return false  // no icon = hidden per user request
        var lowName = (e.name||"").toLowerCase()
        var lowId = (e.id||"").toLowerCase()
        for (var i=0;i<denylist.length;i++) if (lowName.includes(denylist[i]) || lowId.includes(denylist[i])) return false
        return true
    })
    // quickshell plugins ride the launcher as apps now (PluginMenu
    // scrapped) — plain data, launch() toggles by qsTarget.
    readonly property var pluginApps: [
        { id: "qs-pomodoro", name: "Pomodoro", genericName: "focus timer · stats", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "pomodoro" },
        { id: "qs-github", name: "GitHub", genericName: "notifs · PRs · heatmap", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "github" },
        { id: "qs-notes", name: "Quick Notes", genericName: "idea capture · draggable", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "notes" },
        { id: "qs-screentime", name: "Screen Time", genericName: "usage heatmaps · app ranks", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "screentime" },
        { id: "qs-phonebridge", name: "PhoneBridge", genericName: "send & pull files over ADB", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "phonebridge" },
        { id: "qs-drives", name: "Drive Health", genericName: "SMART + RAM + speed test", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "drives" },
        { id: "qs-monitors", name: "Monitors", genericName: "DPI / scale · rotate · display", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "monitors" },
        { id: "qs-failwatch", name: "FailWatch", genericName: "failed units · journal errors", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "failwatch" },
        { id: "qs-dict", name: "Dictionary", genericName: "definitions · synonyms · audio", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "dict" },
        { id: "qs-grap", name: "Grap", genericName: "instant file search · grep", comment: "quickshell plugin", keywords: ["plugin", "quickshell"], glyph: "", qsTarget: "grap" },
    ]
    readonly property var allApps: storeApps.concat(pluginApps)
    function db() { return LocalStorage.openDatabaseSync("qs_launcher", "1.0", "launcher", 100000) }
    function loadStores() {
        var d = db()
        d.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage(id TEXT PRIMARY KEY, count INTEGER)')
            try { tx.executeSql('ALTER TABLE usage ADD COLUMN last INTEGER DEFAULT 0') } catch(e) {}
            var r = tx.executeSql('SELECT * FROM usage'); var m={}; var l={}
            for(var i=0;i<r.rows.length;i++){ m[r.rows.item(i).id]=r.rows.item(i).count; try{ l[r.rows.item(i).id]=r.rows.item(i).last||0 }catch(e2){} }
            usageMap=m; usageLast=l
        })
    }
    // learned rank: log count (204 launches ≈ 15, 20 ≈ 9, 0 = 0) plus a
    // recency kick — opened today +6, this week +3. Stale giants still lose
    // to what you actually touched recently.
    function usageScore(id){
        var c = usageMap[id]||0
        var s = Math.log2(1+c)*2
        var age = Date.now() - (usageLast[id]||0)
        if (age < 86400000) s += 6
        else if (age < 604800000) s += 3
        return s
    }
    function bumpUsage(id){
        var now = Date.now()
        var d=db(); d.transaction(function(tx){ tx.executeSql('INSERT OR REPLACE INTO usage VALUES(?, COALESCE((SELECT count FROM usage WHERE id=?),0)+1, ?)', [id,id,now]) })
        var m=JSON.parse(JSON.stringify(usageMap)); m[id]=(m[id]||0)+1; usageMap=m
        var l=JSON.parse(JSON.stringify(usageLast)); l[id]=now; usageLast=l
    }
    readonly property var filtered: {
        var q = search.text.trim().toLowerCase()
        if (q === "") {
            var copy=allApps.slice()
            copy.sort(function(a,b){
                var ca=usageScore(a.id), cb=usageScore(b.id)
                if(ca!==cb) return cb-ca
                return a.name.localeCompare(b.name)
            })
            return copy.slice(0,50)
        }
        var scored = []
        for (var i=0;i<allApps.length;i++) {
            var e = allApps[i]
            var kw = ""
            try { kw = e.keywords ? e.keywords.join(" ") : "" } catch(e2) { kw = "" }
            var hay = (e.name + " " + (e.genericName||"") + " " + (e.comment||"") + " " + kw).toLowerCase()
            if (!hay.includes(q)) continue
            var score = 99
            if (e.name.toLowerCase().startsWith(q)) score = 0
            else if (e.name.toLowerCase().includes(q)) score = 1
            else if (e.genericName.toLowerCase().includes(q)) score = 2
            else score = 3
            // learned rank does the work: name match sets the tier,
            // usage score (uncapped log + recency) orders within it
            score -= usageScore(e.id) / 2
            scored.push({e:e, score:score})
        }
        scored.sort(function(a,b){
            if (a.score!==b.score) return a.score-b.score
            var ca=usageScore(a.e.id), cb=usageScore(b.e.id)
            if (ca!==cb) return cb-ca
            return a.e.name.localeCompare(b.e.name)
        })
        return scored.slice(0,50).map(function(x){return x.e})
    }

    function launch(entry) {
        if (!entry) return
        bumpUsage(entry.id)
        root.open = false
        Qt.callLater(function(){
            // quickshell plugins live in the launcher now: toggle by target.
            if (entry.qsTarget)
                Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", entry.qsTarget, "toggle"])
            // Terminal apps die instantly with no TTY — run them inside
            // kitty (same uwsm-app scope as SUPER+RETURN).
            else if (entry.runInTerminal && entry.command && entry.command.length > 0)
                Quickshell.execDetached(["uwsm-app", "--", "kitty", "-e"].concat(entry.command))
            else
                entry.execute()
        })
    }

    // click-outside catcher (invisible — no dim backdrop, glass floats over desktop)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    // Design C — two stacked glass surfaces. No rails, no hairlines, no borders:
    // the bar and the card are separated by tone and 10px of space only.
    Item {
        id: shell
        anchors.centerIn: parent
        width: 600
        height: barItem.height + gap + resultsCard.height
        focus: root.open
        Keys.onEscapePressed: root.open = false

        readonly property int gap: 10
        readonly property int rowH: 52
        readonly property int rowGap: 3
        readonly property int footerH: 40
        // Fixed viewport: typing only swaps rows inside it. If this tracked
        // filtered.length, the card resized on every keystroke and the whole
        // center-anchored shell jumped — that was the "reload" while searching.
        readonly property int listH: 7 * (rowH + rowGap) - rowGap

        // Direction C — "Unfold / Lens", but on ONE continuous timeline. The
        // previous version gave the bar its own POP bounce, paused 100ms, then
        // unrolled the card on a different curve; the seam read as a clunk.
        // A single eased reveal drives both surfaces and every sub-property,
        // so bar → card is one uninterrupted move. The sub-ranges overlap so
        // the card is already moving while the bar settles.
        property real reveal: 0
        readonly property real barP: Math.min(1, reveal / 0.40)
        readonly property real cardP: Math.min(1, Math.max(0, (reveal - 0.10) / 0.90))
        readonly property var outCurve: [0.2, 0.8, 0.2, 1]

        NumberAnimation {
            id: openAnim
            target: shell; property: "reveal"; to: 1
            duration: 460; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve
        }
        NumberAnimation {
            id: closeAnim
            target: shell; property: "reveal"; to: 0
            duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve
        }
        SequentialAnimation {
            id: flashAnim
            ColorAnimation { target: barItem; property: "border.color"; from: colors.alpha(colors.outline, 0); to: colors.alpha(colors.primary, 0.9); duration: 110; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve }
            ColorAnimation { target: barItem; property: "border.color"; to: colors.alpha(colors.outline, 0.18); duration: 110; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve }
        }

        // ── search bar ──────────────────────────────────────────────
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
            scale: 0.92 + 0.08 * shell.barP
            transform: Translate { id: barShift; y: -6 * (1 - shell.barP) }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 12

                Image {
                    // Hollow Knight mark, carried over from the brand rail.
                    // Crop the transparent padding (art bbox 131,56 237x388)
                    // so the mark fills the box instead of shrinking inside it.
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
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Down) { root.selected = Math.min(root.selected+1, root.filtered.length-1); resultList.positionViewAtIndex(root.selected, ListView.Contain); event.accepted = true }
                        else if (event.key === Qt.Key_Up) { root.selected = Math.max(root.selected-1, 0); resultList.positionViewAtIndex(root.selected, ListView.Contain); event.accepted = true }
                        else if (event.key === Qt.Key_Escape) { root.open = false; event.accepted = true }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            var e = root.filtered[root.selected]
                            if (e) root.launch(e)
                            event.accepted = true
                        }
                    }
                    onTextChanged: root.selected = 0
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

        // ── results card ────────────────────────────────────────────
        Rectangle {
            id: resultsCard
            y: barItem.height + shell.gap
            width: parent.width
            height: 7 + shell.listH + shell.footerH
            radius: 18
            color: colors.alpha(colors.surface, 0.78)
            opacity: shell.cardP
            scale: 0.3 + 0.7 * shell.cardP
            transformOrigin: Item.Top
            transform: Translate { id: resultShift; y: -10 * (1 - shell.cardP) }

            Item {
                id: listArea
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    topMargin: 7
                    leftMargin: 7
                    rightMargin: 7
                }
                height: shell.listH
                clip: true

                ListView {
                    id: resultList
                    anchors.fill: parent
                    visible: root.filtered.length > 0
                    clip: true
                    model: root.filtered
                    currentIndex: root.selected
                    onCurrentIndexChanged: root.selected = currentIndex
                    spacing: shell.rowGap
                    interactive: true
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
                    delegate: Item {
                        id: rowRoot
                        required property var modelData
                        required property int index
                        width: resultList.width
                        height: shell.rowH
                        // Cascade only on open. Rows created while typing (the
                        // model swaps them out) appear instantly — replaying
                        // the stagger on every keystroke read as a reload.
                        property bool shown: false
                        // C's rows rise 8px into place on open, fade out in
                        // place on close (no dip — the card does the rolling).
                        opacity: shown ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: root.open ? 200 : 100; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve } }
                        transform: Translate { id: dip; y: (shown || !root.open) ? 0 : 8; Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: shell.outCurve } } }
                        Component.onCompleted: { if (root.open) rowRoot.shown = true; else cascadeTimer.restart() }
                        Connections {
                            target: root
                            function onOpenChanged() {
                                rowRoot.shown = false
                                if (root.open) {
                                    cascadeTimer.interval = 240 + Math.min(rowRoot.index, 11) * 20
                                    cascadeTimer.restart()
                                }
                            }
                        }
                        Timer {
                            id: cascadeTimer
                            interval: 240 + Math.min(rowRoot.index, 11) * 20
                            onTriggered: rowRoot.shown = true
                        }

                        // same no-scale rule as before: the fill never overflows
                        // the list. Selected is tone; hover is a lighter tone.
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: index === root.selected
                                ? colors.alpha(colors.primary, 0.17)
                                : ma.containsMouse ? colors.alpha(colors.foreground, 0.045) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            // plain 24px mark, no tile behind it
                            Item {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                scale: index === root.selected ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } }
                                Image {
                                    id: appIcon
                                    anchors.fill: parent
                                    source: {
                                        if (modelData.glyph) return ""
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
                                color: index === root.selected ? colors.alpha(colors.primary, 0.9) : colors.alpha(colors.outline, 0.5)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: if (root.allowHover) root.selected = index
                            onPositionChanged: if (!root.allowHover) root.allowHover = true
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

            // footer hint + live count
            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: shell.footerH
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14
                    Text {
                        text: "↑↓ move"
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                    }
                    Text {
                        text: "↵ open"
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                    }
                    Text {
                        text: "esc close"
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                    }
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
