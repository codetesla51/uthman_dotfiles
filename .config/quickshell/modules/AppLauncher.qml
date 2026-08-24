import Quickshell
import Quickshell.Io
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

    visible: root.open
    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: true

    IpcHandler { target: "launcher"; function toggle(): void { root.open = !root.open } }

    // reset state on open/close
    property bool allowHover: false
    Component.onCompleted: loadStores()
    onOpenChanged: {
        if (open) { search.text = ""; selected = -1; allowHover = false; Qt.callLater(function(){ search.forceActiveFocus() }) }
    }
    // no timer — hover enables on first mouse move only, so open doesn't auto-highlight

    // denylist — system junk the user never launches; edit this array to hide more
    readonly property var denylist: ["rofi","kvantum","qv4l2","qt5ct","qt6ct","v4l2 test","logseq","printer","assistant","ava","btop","htop","xterm","uxterm","kvantummanager"]
    property var usageMap: ({})
    property var favSet: ({})
    readonly property var allApps: DesktopEntries.applications.values.filter(e => {
        if (e.noDisplay) return false
        if (!e.icon) return false  // no icon = hidden per user request
        var lowName = (e.name||"").toLowerCase()
        var lowId = (e.id||"").toLowerCase()
        for (var i=0;i<denylist.length;i++) if (lowName.includes(denylist[i]) || lowId.includes(denylist[i])) return false
        return true
    })
    function db() { return LocalStorage.openDatabaseSync("qs_launcher", "1.0", "launcher", 100000) }
    function loadStores() {
        var d = db()
        d.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS usage(id TEXT PRIMARY KEY, count INTEGER)')
            tx.executeSql('CREATE TABLE IF NOT EXISTS favs(id TEXT PRIMARY KEY)')
            var r = tx.executeSql('SELECT * FROM usage'); var m={}; for(var i=0;i<r.rows.length;i++) m[r.rows.item(i).id]=r.rows.item(i).count; usageMap=m
            var f = tx.executeSql('SELECT * FROM favs'); var s2={}; for(var j=0;j<f.rows.length;j++) s2[f.rows.item(j).id]=true; favSet=s2
        })
    }
    function bumpUsage(id){
        var d=db(); d.transaction(function(tx){ tx.executeSql('INSERT OR REPLACE INTO usage VALUES(?, COALESCE((SELECT count FROM usage WHERE id=?),0)+1)', [id,id]) })
        var m=JSON.parse(JSON.stringify(usageMap)); m[id]=(m[id]||0)+1; usageMap=m
    }
    function toggleFav(id){
        var d=db(); var isFav=favSet[id]
        d.transaction(function(tx){ if(isFav) tx.executeSql('DELETE FROM favs WHERE id=?',[id]); else tx.executeSql('INSERT INTO favs VALUES(?)',[id]) })
        var s2=JSON.parse(JSON.stringify(favSet)); if(isFav) delete s2[id]; else s2[id]=true; favSet=s2
    }
    readonly property var filtered: {
        var q = search.text.trim().toLowerCase()
        if (q === "") {
            var copy=allApps.slice()
            copy.sort(function(a,b){
                var fa=favSet[a.id]?1:0, fb=favSet[b.id]?1:0
                if(fa!==fb) return fb-fa
                var ca=usageMap[a.id]||0, cb=usageMap[b.id]||0
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
            // boost favorites and frequent
            if (favSet[e.id]) score -= 10
            score -= Math.min(5, (usageMap[e.id]||0)*0.5)
            scored.push({e:e, score:score})
        }
        scored.sort(function(a,b){
            if (a.score!==b.score) return a.score-b.score
            var ca=usageMap[a.e.id]||0, cb=usageMap[b.e.id]||0
            if (ca!==cb) return cb-ca
            return a.e.name.localeCompare(b.e.name)
        })
        return scored.slice(0,50).map(function(x){return x.e})
    }

    function launch(entry) {
        if (!entry) return
        bumpUsage(entry.id)
        root.open = false
        Qt.callLater(function(){ entry.execute() })
    }

    // dim backdrop
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.45 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560
        height: Math.min(520, col.implicitHeight + 28)
        radius: 18
        color: colors.alpha(colors.background, 0.96)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.25)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Keys.onEscapePressed: root.open = false
        focus: root.open

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 10

            // search bar
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: colors.alpha(colors.surface, 0.6)
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
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 14
                    }

                    TextField {
                        id: search
                        Layout.fillWidth: true
                        placeholderText: "Search apps…"
                        placeholderTextColor: colors.alpha(colors.outline, 0.5)
                        color: colors.foreground
                        font.family: "FiraCode Nerd Font"
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
                        onTextChanged: root.selected = -1
                    }

                    Text {
                        visible: search.text !== ""
                        text: "󰅖"
                        color: clearMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.6)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                        MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; onClicked: search.text = "" }
                    }
                }
            }

            Text {
                visible: search.text.trim() === "" && Object.keys(usageMap).length > 0
                text: "RECENT"
                color: colors.alpha(colors.outline, 0.55)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 8
                font.letterSpacing: 1.5
                font.weight: Font.Bold
                Layout.leftMargin: 4
            }

            // results
            ListView {
                id: resultList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(7*56, root.filtered.length*56)
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
                    required property var modelData
                    required property int index
                    width: resultList.width
                    height: 52
                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 2
                        anchors.rightMargin: 2
                        radius: 10
                        scale: (index === root.selected || ma.containsMouse) ? 1.02 : 1
                        color: index === root.selected ? colors.alpha(colors.primary, 0.18) : ma.containsMouse ? colors.alpha(colors.surfaceVariant, 0.25) : "transparent"
                        border.width: index === root.selected ? 1 : 0
                        border.color: colors.alpha(colors.primary, 0.4)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }

                        RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 8
                            color: colors.alpha(colors.primary, 0.10)
                            border.width: 1
                            border.color: colors.alpha(colors.primary, 0.15)
                            Image {
                                id: appIcon
                                anchors.fill: parent
                                anchors.margins: 5
                                source: {
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
                                text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                                color: colors.primary
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.ExtraBold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: colors.foreground
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.genericName || modelData.comment || modelData.id
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: "FiraCode Nerd Font"
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
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                Layout.bottomMargin: 16
            }

            // footer hint
            Text {
                text: "↑↓ navigate  •  ↵ launch  •  esc close"
                color: colors.alpha(colors.outline, 0.45)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 8
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
            }
        }
    }
}
