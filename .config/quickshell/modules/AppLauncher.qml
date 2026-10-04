import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

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
        if (open) { search.text = ""; selected = filtered.length > 0 ? 0 : -1; allowHover = false; Qt.callLater(function(){ search.forceActiveFocus() }); openAnim.restart() }
        else closeAnim.restart()
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

    // click-outside catcher (invisible — no dim backdrop, card floats over desktop)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 750
        height: Math.min(520, col.implicitHeight + 28)
        radius: 18
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        Keys.onEscapePressed: root.open = false
        focus: root.open

        // bezier pair — open pops with overshoot bounce (fast), close hurries
        // out with none. Same curves as the notification drawer.
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

        RowLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // brand rail — Hollow Knight mask, live caption under it
            Item {
                Layout.preferredWidth: 168
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Image {
                        // solid-white bake: the source PNG is faint low-alpha
                        // line art that reads black on the card — this one is
                        // opaque white wherever the art is.
                        // Flex sizing: the card shrinks on empty results, so
                        // the art scales down with it instead of breaking.
                        source: Quickshell.env("HOME") + "/.config/quickshell/assets/hk-mask-white.png"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: 130
                        Layout.maximumHeight: root.filtered.length > 1 ? 210 : 84
                        Layout.minimumHeight: 30
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        Layout.alignment: Qt.AlignHCenter
                        opacity: root.open ? 1 : 0
                        scale: root.open ? 1 : 0.92
                        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        // live caption: follows the highlighted app. Hidden
                        // on empty results — nothing to follow, saves rail.
                        visible: root.filtered.length > 0
                        text: (root.selected >= 0 && root.selected < root.filtered.length && root.filtered[root.selected])
                            ? root.filtered[root.selected].name : "技"
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        Layout.maximumWidth: 160
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "HOLLOW"
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        font.letterSpacing: 3
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // hairline between brand and search
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                color: colors.alpha(colors.outline, 0.15)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

            // search bar
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: colors.alpha(colors.surface, 0.42)
                border.width: 1
                border.color: search.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.15)
                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: ""
                        color: colors.alpha(colors.outline, 0.8)
                        font.family: colors.fontSans
                        font.pixelSize: 14
                    }

                    TextField {
                        id: search
                        Layout.fillWidth: true
                        placeholderText: "Search apps…"
                        placeholderTextColor: colors.alpha(colors.outline, 0.5)
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 13
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
                }
            }

            Text {
                visible: search.text.trim() === "" && Object.keys(usageMap).length > 0
                text: "RECENT"
                color: colors.alpha(colors.outline, 0.55)
                font.family: colors.fontSans
                font.pixelSize: 8
                font.letterSpacing: 1.5
                font.weight: Font.Bold
                Layout.leftMargin: 4
            }

            // results
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(7*50, root.filtered.length*50)
                visible: root.filtered.length > 0
                clip: true
                model: root.filtered
                currentIndex: root.selected
                onCurrentIndexChanged: root.selected = currentIndex
                spacing: 4
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: rowRoot
                    required property var modelData
                    required property int index
                    width: resultList.width
                    height: 50
                    // cascade in on creation (also gently re-fades recycled rows)
                    property bool shown: false
                    opacity: shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    transform: Translate { id: dip; y: shown ? 0 : 10; Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                    Component.onCompleted: cascadeTimer.restart()
                    Timer {
                        id: cascadeTimer
                        interval: Math.min(rowRoot.index, 11) * 28
                        onTriggered: rowRoot.shown = true
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: 10
                        // NOTE: no scale here on purpose — 1.02 overflowed the
                        // highlight past the list width on hover. Feedback is
                        // color + border + the left accent bar below.
                        color: index === root.selected ? colors.alpha(colors.primary, 0.15) : ma.containsMouse ? colors.alpha(colors.primary, 0.08) : "transparent"
                        border.width: index === root.selected ? 1 : 0
                        border.color: colors.alpha(colors.primary, 0.4)
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 9
                            color: colors.alpha(colors.primary, 0.10)
                            border.width: 1
                            border.color: colors.alpha(colors.primary, 0.15)
                            scale: index === root.selected ? 1.14 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                anchors.margins: 5
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
                                font.pixelSize: modelData.glyph ? 15 : 13
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
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.genericName || modelData.comment || modelData.id
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
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
            }

            Text {
                visible: root.filtered.length === 0
                text: "No results"
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans
                font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 16
            }

            // footer hint + live count
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Text {
                    text: "↑↓ navigate  •  ↵ launch  •  esc close"
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: colors.fontSans
                    font.pixelSize: 8
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.filtered.length > 0
                    text: root.filtered.length + (root.filtered.length === 1 ? " app" : " apps")
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: colors.fontSans
                    font.pixelSize: 8
                    font.weight: Font.Bold
                }
            }
            } // mainCol, then col RowLayout
        }
    }
}
