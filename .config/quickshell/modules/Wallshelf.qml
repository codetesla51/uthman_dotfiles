import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Wallshelf — Wallhaven storefront. Browse + bulk download + manage.
// Applying wallpapers stays in ThemePanel (downloads symlink into its dir).
PanelWindow {
    id: root
    property var colors
    property bool open: false

    // ── config (~/.config/quickshell/wallshelf.json) ──
    property string apiKey: ""
    property string cacheDir: Quickshell.env("HOME") + "/.cache/wallshelf"
    property string linkDir: Quickshell.env("HOME") + "/dotfiles/wallpapers"
    property string resOverride: ""
    property string detectedRes: "1920x1080"
    property int fallbackMin: 3
    property bool useFallback: true
    readonly property string cfgPath: Quickshell.env("HOME") + "/.config/quickshell/wallshelf.json"
    readonly property string resolution: resOverride !== "" ? resOverride : detectedRes

    // ── ui state ──
    property string tab: "browse"       // browse | downloaded
    property string query: ""
    property bool catGeneral: true
    property bool catAnime: true
    property bool catPeople: false
    property bool purSketchy: false
    property bool purNsfw: false
    property string sorting: "toplist"
    property int page: 1
    property int lastPage: 1
    property bool loading: false
    property string errorMsg: ""
    ListModel { id: resultModel }
    function wAt(i){
        if(i < 0 || i >= resultModel.count) return null
        var m = resultModel.get(i)
        return {id: m.wid, page: m.wpage, full: m.wfull, thumb: m.wthumb, res: m.wres, cat: m.wcat, purity: m.wpurity, views: m.wviews, favs: m.wfavs}
    }
    property var downloaded: ({})
    property var selected: ({})
    property int selCount: 0
    property int previewIdx: -1         // -1 = no preview
    property var localFiles: []
    property bool scanningLocal: false
    readonly property string sortParam: sorting === "latest" ? "date_added" : sorting
    readonly property string catParam: (catGeneral ? "1" : "0") + (catAnime ? "1" : "0") + (catPeople ? "1" : "0")
    readonly property string purParam: "1" + (purSketchy ? "1" : "0") + (purNsfw ? "1" : "0")

    // ── rate limit ──
    property double lastCall: 0
    property int backoffMs: 0
    property var respCache: ({})
    property string pendingUrl: ""
    property bool searchQueued: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-wallshelf"
    WlrLayershell.layer: WlrLayer.Overlay
    IpcHandler { target: "wallshelf"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if(open){ Qt.callLater(function(){ card.forceActiveFocus() }); if(resultModel.count === 0) search(true) }

    // ── config ──
    FileView {
        id: cfgView
        path: root.cfgPath
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if(!d) return
                if(d.apiKey) root.apiKey = d.apiKey
                if(d.cacheDir) root.cacheDir = d.cacheDir
                if(d.linkDir) root.linkDir = d.linkDir
                if(d.resOverride) root.resOverride = d.resOverride
                if(d.fallbackMin) root.fallbackMin = d.fallbackMin
                if(d.resolution && !root.resOverride) root.detectedRes = d.resolution
            } catch(e) {}
        }
    }
    function cfgSave(){
        saveProc.command = ["sh","-c","mkdir -p '"+Quickshell.env("HOME")+"/.config/quickshell' '"+root.cacheDir+"' && echo '"+Qt.btoa(JSON.stringify({apiKey: root.apiKey, cacheDir: root.cacheDir, linkDir: root.linkDir, resOverride: root.resOverride, fallbackMin: root.fallbackMin, resolution: root.resolution}))+"' | base64 -d > '"+root.cfgPath+"'"]
        saveProc.running = true
    }
    Process { id: saveProc }

    // ── resolution ──
    function detectResolution(){
        var got = ""
        try {
            var ss = Quickshell.screens
            var list = (ss && ss.values) ? ss.values : ss
            if(list && list.length){
                var s = list[0]
                var w = s.width || s.pixelWidth || 0
                var h = s.height || s.pixelHeight || 0
                var sc = s.scaleFactor || s.devicePixelRatio || 1
                if(w > 0 && h > 0) got = Math.round(w * sc) + "x" + Math.round(h * sc)
            }
        } catch(e) {}
        if(got !== ""){ root.detectedRes = got; root.cfgSave(); return }
        resProc.running = true
    }
    Process {
        id: resProc
        command: ["sh","-c","hyprctl monitors -j 2>/dev/null | python3 -c \"import json,sys; ms=json.load(sys.stdin); m=[x for x in ms if x.get('focused')][0] if any(x.get('focused') for x in ms) else ms[0]; print(str(m['width'])+'x'+str(m['height']))\" 2>/dev/null || echo 1920x1080"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { var r = text.trim(); if(r.match(/^[0-9]+x[0-9]+$/)){ root.detectedRes = r; root.cfgSave() } }
        }
    }

    // ── downloaded set + local files ──
    Process {
        id: dlListProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var set = {}
                var lines = text.split("\n")
                for(var i=0;i<lines.length;i++){
                    var m = lines[i].trim().match(/wallhaven-([a-z0-9]+)\.[a-z]+$/i)
                    if(m) set[m[1]] = true
                }
                root.downloaded = set
            }
        }
    }
    function refreshDownloaded(){
        dlListProc.command = ["sh","-c","ls '"+root.linkDir+"' '"+root.cacheDir+"' 2>/dev/null"]
        dlListProc.running = true
    }
    Process {
        id: localProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var files = []
                var lines = text.split("\n")
                for(var i=0;i<lines.length;i++){
                    var parts = lines[i].trim().split("|")
                    if(parts.length < 3 || !parts[1]) continue
                    var p = parts[1]
                    var name = p.split("/").pop()
                    files.push({path: p, name: name, size: parts[2]})
                }
                root.localFiles = files
                root.scanningLocal = false
            }
        }
    }
    function refreshLocal(){
        root.scanningLocal = true
        localProc.command = ["sh","-c","find '"+root.linkDir+"' '"+root.cacheDir+"' -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \\) -printf '%T@|%p|%k\\n' 2>/dev/null | sort -rn | head -n 300"]
        localProc.running = true
    }

    // ── search ──
    function apiUrl(pg, fallback){
        var u = "https://wallhaven.cc/api/v1/search?q=" + encodeURIComponent(root.query)
        u += "&categories=" + root.catParam + "&purity=" + root.purParam
        u += "&sorting=" + root.sortParam + "&order=desc&page=" + pg
        if(!fallback) u += "&resolutions=" + root.resolution
        else u += "&atleast=" + root.resolution
        if(root.apiKey !== "") u += "&apikey=" + root.apiKey
        return u
    }
    function search(reset){
        if(root.loading){ root.searchQueued = true; return }
        if(reset){ root.page = 1; resultModel.clear(); root.selected = {}; root.selCount = 0; root.previewIdx = -1; root.useFallback = true }
        var now = Date.now()
        var wait = Math.max(0, 1500 - (now - root.lastCall)) + root.backoffMs
        root.pendingUrl = apiUrl(root.page, false)
        if(wait > 0){ rateTimer.interval = wait; rateTimer.restart() }
        else doFetch(root.pendingUrl)
    }
    Timer { id: rateTimer; onTriggered: root.doFetch(root.pendingUrl) }
    function doFetch(url){
        if(respCache[url] && (Date.now() - respCache[url].at < 60000)){
            root.applyResults(respCache[url].body)
            return
        }
        root.loading = true
        root.errorMsg = ""
        fetchProc.command = ["sh","-c","curl -sS -m 25 -H 'User-Agent: wallshelf/1.0' '"+url.replace(/'/g,"'\\''")+"' 2>&1"]
        root.lastCall = Date.now()
        fetchProc.running = true
    }
    Process {
        id: fetchProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyResults(text)
        }
    }
    function applyResults(text){
        root.loading = false
        var d = null
        try { d = JSON.parse(text) } catch(e) {}
        if(!d || !d.data){
            if(text.indexOf("429") !== -1 || text.toLowerCase().indexOf("rate") !== -1){
                root.backoffMs = Math.min(30000, (root.backoffMs || 2000) * 2)
                root.errorMsg = "Rate limited — backing off, scroll to retry"
            } else root.errorMsg = "Search failed — check connection"
            if(root.searchQueued){ root.searchQueued = false; root.search(false) }
            return
        }
        root.backoffMs = 0
        respCache[root.pendingUrl] = {at: Date.now(), body: text}
        root.lastPage = (d.meta && d.meta.last_page) || 1
        var rows = d.data.map(function(w){
            return {id: w.id, page: "https://wallhaven.cc/w/" + w.id,
                    full: w.path, thumb: (w.thumbs && w.thumbs.large) || "",
                    res: w.resolution || "", cat: w.category || "", purity: w.purity || "",
                    views: (w.views || 0), favs: (w.favorites || 0)}
        })
        if(root.useFallback && root.page === 1 && rows.length < root.fallbackMin){
            root.useFallback = false
            root.pendingUrl = apiUrl(1, true)
            root.doFetch(root.pendingUrl)
            return
        }
        root.useFallback = false
        for(var k=0;k<rows.length;k++){
            var r = rows[k]
            resultModel.append({wid: r.id, wpage: r.page, wfull: r.full, wthumb: r.thumb, wres: r.res, wcat: r.cat, wpurity: r.purity, wviews: r.views, wfavs: r.favs})
        }
        if(root.searchQueued){ root.searchQueued = false; root.search(false) }
    }
    function loadMore(){
        if(root.loading || root.page >= root.lastPage) return
        root.page += 1
        root.pendingUrl = apiUrl(root.page, false)
        var now = Date.now()
        var wait = Math.max(0, 1500 - (now - root.lastCall)) + root.backoffMs
        if(wait > 0){ rateTimer.interval = wait; rateTimer.restart() }
        else root.doFetch(root.pendingUrl)
    }

    // ── download queue: sequential curl with live % from --progress-bar ──
    property var dlQueue: []
    property string dlCurrent: ""
    property var dlState: ({})          // id -> {pct, status}
    property int dlActive: 0
    function dlSet(id, pct, status){
        var s = Object.assign({}, root.dlState)
        s[id] = {pct: pct, status: status}
        root.dlState = s
    }
    function dlClear(id){
        var s = Object.assign({}, root.dlState)
        delete s[id]
        root.dlState = s
    }
    function fnameFor(w){
        var ext = "jpg"
        var m = w.full.match(/\.([a-z0-9]+)(\?|$)/i)
        if(m) ext = m[1].toLowerCase()
        return "wallhaven-" + w.id + "." + ext
    }
    function enqueue(w){
        if(!w || root.downloaded[w.id]) return
        for(var i=0;i<root.dlQueue.length;i++) if(root.dlQueue[i].id === w.id) return
        root.dlQueue = root.dlQueue.concat([w])
        root.dlSet(w.id, 0, "queued")
        pumpQueue()
    }
    function downloadOne(w){ root.enqueue(w) }
    function downloadBulk(){
        var ids = Object.keys(root.selected)
        if(ids.length){
            var byId = {}
            for(var i=0;i<resultModel.count;i++){ var it = root.wAt(i); byId[it.id] = it }
            var n = 0
            for(var j=0;j<ids.length;j++){ if(byId[ids[j]] && !root.downloaded[ids[j]]){ root.enqueue(byId[ids[j]]); n++ } }
            root.selected = {}; root.selCount = 0
            if(n) root.errorMsg = "Queued " + n + "…"
            return
        }
        var w = root.wAt(grid.currentIndex)
        if(w) root.enqueue(w)
    }
    function pumpQueue(){
        if(root.dlCurrent !== "" || !root.dlQueue.length) return
        var w = root.dlQueue[0]
        root.dlQueue = root.dlQueue.slice(1)
        root.dlCurrent = w.id
        root.dlActive = root.dlQueue.length + 1
        var fn = fnameFor(w)
        dlTotal = 0
        dlPath = root.cacheDir + "/" + fn
        root.dlSet(w.id, 0, "downloading")
        dlProc.command = ["sh","-c","mkdir -p '"+root.cacheDir+"' '"+root.linkDir+"' && rm -f '"+dlPath+"' && total=$(curl -sIL -m 20 -H 'User-Agent: wallshelf/1.0' '"+w.full.replace(/'/g,"'\\''")+"' | grep -i '^content-length:' | tail -1 | tr -dc '0-9'); echo TOTAL_${total:-0} && curl -sSL -m 600 -H 'User-Agent: wallshelf/1.0' '"+w.full.replace(/'/g,"'\\''")+"' -o '"+dlPath+"' && ln -sf '"+dlPath+"' '"+root.linkDir+"/"+fn+"' && echo DL_OK || echo DL_FAIL"]
        dlProc.running = true
        pollTimer.restart()
    }
    property string dlPath: ""
    property double dlTotal: 0
    Timer {
        id: pollTimer
        interval: 400
        repeat: true
        onTriggered: {
            if(root.dlCurrent === ""){ pollTimer.stop(); return }
            if(root.dlTotal > 0){
                szProc.command = ["sh","-c","stat -c%s '"+root.dlPath+"' 2>/dev/null || echo 0"]
                szProc.running = true
            }
        }
    }
    Process {
        id: szProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if(root.dlCurrent === "" || root.dlTotal <= 0) return
                var got = parseInt(text.trim()) || 0
                root.dlSet(root.dlCurrent, Math.min(99, Math.round(got / root.dlTotal * 100)), "downloading")
            }
        }
    }
    Process {
        id: dlProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                pollTimer.stop()
                var ok = text.indexOf("DL_OK") !== -1
                var id = root.dlCurrent
                if(ok){
                    root.dlClear(id)
                    root.refreshDownloaded()
                    if(root.tab === "downloaded") root.refreshLocal()
                } else {
                    root.dlSet(id, 0, "failed")
                    root.errorMsg = "Download failed: " + id
                }
                root.dlCurrent = ""
                root.dlPath = ""
                root.dlTotal = 0
                root.dlActive = root.dlQueue.length
                if(!root.dlQueue.length && ok) root.errorMsg = ""
                pumpQueue()
            }
        }
    }
    function removeWall(w){
        if(!w) return
        var fn = fnameFor(w)
        rmProc.command = ["sh","-c","rm -f '"+root.linkDir+"/"+fn+"' '"+root.cacheDir+"/"+fn+"' && echo RM_OK"]
        rmProc.pendingId = w.id
        rmProc.running = true
    }
    function removeLocal(path){
        if(!path) return
        var q = path.replace(/'/g,"'\\''")
        rmProc.command = ["sh","-c","rm -f '"+q+"' && echo RM_OK"]
        rmProc.pendingId = ""
        rmProc.pendingLocal = true
        rmProc.running = true
    }
    Process {
        id: rmProc
        property string pendingId: ""
        property bool pendingLocal: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if(text.indexOf("RM_OK") !== -1){
                    if(rmProc.pendingId){
                        var set = Object.assign({}, root.downloaded)
                        delete set[rmProc.pendingId]
                        root.downloaded = set
                    }
                    root.refreshDownloaded()
                    if(root.tab === "downloaded") root.refreshLocal()
                }
                rmProc.pendingId = ""
                rmProc.pendingLocal = false
            }
        }
    }
    function toggleSelect(w){
        if(!w) return
        var s = Object.assign({}, root.selected)
        if(s[w.id]){ delete s[w.id]; root.selCount -= 1 }
        else { s[w.id] = true; root.selCount += 1 }
        root.selected = s
    }

    Component.onCompleted: { detectResolution(); refreshDownloaded() }

    // transparent backdrop (blur comes from the compositor) — blocks clicks
    MouseArea { anchors.fill: parent; onClicked: {} }

    // storefront card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.94, 1120)
        height: Math.min(parent.height * 0.9, 780)
        radius: 20
        color: colors.alpha(colors.surface, 0.82)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.16)
        focus: true
        Keys.onEscapePressed: { if(root.previewIdx !== -1) root.previewIdx = -1; else root.open = false }
        Keys.onPressed: function(e){
            if(root.tab === "downloaded"){
                if(e.key === Qt.Key_T){ var l = root.localFiles[localGrid.currentIndex]; if(l) root.removeLocal(l.path); e.accepted = true }
                else if(e.key === Qt.Key_Left){ localGrid.moveCurrentIndexLeft(); e.accepted = true }
                else if(e.key === Qt.Key_Right){ localGrid.moveCurrentIndexRight(); e.accepted = true }
                else if(e.key === Qt.Key_Up){ localGrid.moveCurrentIndexUp(); e.accepted = true }
                else if(e.key === Qt.Key_Down){ localGrid.moveCurrentIndexDown(); e.accepted = true }
                return
            }
            if(root.previewIdx !== -1){
                if(e.key === Qt.Key_Left){ root.previewIdx = Math.max(0, root.previewIdx - 1); e.accepted = true }
                else if(e.key === Qt.Key_Right){ root.previewIdx = Math.min(resultModel.count - 1, root.previewIdx + 1); e.accepted = true }
                else if(e.key === Qt.Key_D){ var p = root.wAt(root.previewIdx); if(p) root.downloadOne(p); e.accepted = true }
                return
            }
            if(e.key === Qt.Key_D){ root.downloadBulk(); e.accepted = true }
            else if(e.key === Qt.Key_T){ var t = root.wAt(grid.currentIndex); if(t) root.removeWall(t); e.accepted = true }
            else if(e.key === Qt.Key_V || e.key === Qt.Key_S){ var v = root.wAt(grid.currentIndex); if(v) root.toggleSelect(v); e.accepted = true }
            else if(e.key === Qt.Key_Left){ grid.moveCurrentIndexLeft(); e.accepted = true }
            else if(e.key === Qt.Key_Right){ grid.moveCurrentIndexRight(); e.accepted = true }
            else if(e.key === Qt.Key_Up){ grid.moveCurrentIndexUp(); e.accepted = true }
            else if(e.key === Qt.Key_Down){ grid.moveCurrentIndexDown(); e.accepted = true }
            else if(e.key === Qt.Key_Return || e.key === Qt.Key_Enter){ root.previewIdx = grid.currentIndex; e.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // header: tabs + search + loader + close
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Text { text: "WALLSHELF"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1 }
                Repeater { model: [{k:"browse",t:"Browse"},{k:"downloaded",t:"Downloaded"}]
                    Rectangle { width: 104; height: 30; radius: 15
                        color: root.tab === modelData.k ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: { root.tab = modelData.k; if(root.tab === "downloaded") root.refreshLocal() } }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 9
                    color: colors.alpha(colors.surface, 0.85)
                    border.width: 1; border.color: qField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.14)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                        Text { text: ""; color: colors.alpha(colors.outline, 0.6); font.family: "FiraCode Nerd Font"; font.pixelSize: 11 }
                        TextField { id: qField; Layout.fillWidth: true; placeholderText: "Search Wallhaven…  (v/s select • d download • t delete)"; placeholderTextColor: colors.alpha(colors.outline, 0.45); color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; background: null; selectByMouse: true; onAccepted: { root.query = text.trim(); root.search(true) } }
                    }
                }
                // loader (font-independent spinning bar)
                Rectangle {
                    width: 34; height: 34; radius: 17
                    visible: root.loading || root.scanningLocal
                    color: colors.alpha(colors.primary, 0.15)
                    Rectangle {
                        width: 14; height: 3; radius: 2
                        anchors.centerIn: parent
                        color: colors.primary
                        transformOrigin: Item.Center
                        RotationAnimation on rotation { running: root.loading || root.scanningLocal; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                    }
                }
                // selected counter + bulk button
                Rectangle {
                    visible: root.selCount > 0; width: 150; height: 34; radius: 9
                    color: bulkMa.containsMouse ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.primary, 0.18)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.4)
                    Text { anchors.centerIn: parent; text: "↓ " + root.selCount + " selected"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.ExtraBold }
                    MouseArea { id: bulkMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.downloadBulk() }
                }
            }

            // applied-query echo (tags visibly applied) + counts
            Text {
                visible: root.tab === "browse"
                text: (root.query !== "" ? "\"" + root.query + "\"  •  " : "") + resultModel.count + " walls" + (root.page > 1 || root.lastPage > 1 ? "  •  page " + root.page + "/" + root.lastPage : "") + "  •  " + root.resolution
                color: colors.alpha(colors.outline, 0.65); font.family: "FiraCode Nerd Font"; font.pixelSize: 8
            }

            // filter row
            RowLayout {
                visible: root.tab === "browse"
                Layout.fillWidth: true; spacing: 6
                Repeater { model: [{k:"g",t:"General"},{k:"a",t:"Anime"},{k:"p",t:"People"}]
                    Rectangle { width: 74; height: 26; radius: 13
                        property bool on: modelData.k === "g" ? root.catGeneral : (modelData.k === "a" ? root.catAnime : root.catPeople)
                        color: on ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: { if(modelData.k === "g") root.catGeneral = !root.catGeneral; else if(modelData.k === "a") root.catAnime = !root.catAnime; else root.catPeople = !root.catPeople; root.search(true) } }
                    }
                }
                Repeater { model: [{k:"s",t:"SFW"},{k:"k",t:"Sketchy"},{k:"n",t:"NSFW"}]
                    Rectangle { width: 64; height: 26; radius: 13
                        property bool on: modelData.k === "s" ? true : (modelData.k === "k" ? root.purSketchy : root.purNsfw)
                        color: on ? colors.alpha(colors.tertiary, 0.25) : colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: (modelData.k !== "s" && root.apiKey === "") ? colors.alpha(colors.outline, 0.45) : colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: {
                            if(modelData.k === "s") return
                            if(root.apiKey === ""){ root.errorMsg = "Sketchy/NSFW need an API key (see wallshelf.json)"; return }
                            if(modelData.k === "k") root.purSketchy = !root.purSketchy; else root.purNsfw = !root.purNsfw
                            root.search(true)
                        } }
                    }
                }
                Repeater { model: [{k:"toplist",t:"Top"},{k:"latest",t:"New"},{k:"random",t:"Random"},{k:"views",t:"Views"}]
                    Rectangle { width: 62; height: 26; radius: 13
                        color: root.sorting === modelData.k ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: { root.sorting = modelData.k; root.search(true) } }
                    }
                }
            }

            Text { visible: root.errorMsg !== ""; text: root.errorMsg; color: colors.error; font.family: "FiraCode Nerd Font"; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }

            // ── browse grid ──
            GridView {
                id: grid
                visible: root.tab === "browse"
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                cellWidth: 178; cellHeight: 130
                model: resultModel
                keyNavigationWraps: true
                onContentYChanged: { if(!root.loading && contentY + height > contentHeight - 300) root.loadMore() }
                delegate: Rectangle {
                    width: 170; height: 122; radius: 12
                    color: colors.alpha(colors.background, 0.55)
                    border.width: grid.currentIndex === index ? 2 : 1
                    border.color: grid.currentIndex === index ? colors.alpha(colors.primary, 0.6) : colors.alpha(colors.outline, 0.12)
                    scale: thumbMa.containsMouse ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Image {
                        anchors.fill: parent; anchors.margins: 3
                        source: wthumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                    // selected tint
                    Rectangle {
                        anchors.fill: parent; radius: 12
                        visible: !!root.selected[wid]
                        color: colors.alpha(colors.primary, 0.22)
                        border.width: 2; border.color: colors.alpha(colors.primary, 0.7)
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 7
                        width: resText.implicitWidth + 12; height: 18; radius: 9
                        color: colors.alpha(colors.background, 0.78)
                        Text { id: resText; anchors.centerIn: parent; text: wres; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold }
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 7
                        width: 22; height: 22; radius: 11
                        visible: !!root.downloaded[wid]
                        color: colors.alpha(colors.primary, 0.9)
                        Text { anchors.centerIn: parent; text: "✓"; color: colors.alpha(colors.background, 1); font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold }
                    }
                    // selected checkbox (top-left) + progress overlay
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 7
                        width: 22; height: 22; radius: 6
                        color: root.selected[wid] ? colors.alpha(colors.primary, 0.9) : colors.alpha(colors.background, 0.6)
                        border.width: 1; border.color: colors.alpha(colors.primary, 0.6)
                        visible: root.selected[wid] || thumbMa.containsMouse
                        Text { anchors.centerIn: parent; text: "✓"; visible: root.selected[wid]; color: colors.alpha(colors.background, 1); font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleSelect({id: wid}) }
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                        height: 26
                        visible: !!root.dlState[wid]
                        color: colors.alpha(colors.background, 0.8)
                        Rectangle {
                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.margins: 3; radius: 6
                            width: Math.max(0, (parent.width - 6) * ((root.dlState[wid] || {}).pct || 0) / 100)
                            color: colors.alpha(colors.primary, 0.7)
                        }
                        Text { anchors.centerIn: parent; text: ((root.dlState[wid] || {}).status === "queued") ? "queued" : (Math.round(((root.dlState[wid] || {}).pct || 0)) + "%  ↓"); color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                    }
                    MouseArea {
                        id: thumbMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { grid.currentIndex = index }
                        onDoubleClicked: root.downloadOne(modelData)
                    }
                }
            }

            // ── downloaded manager ──
            GridView {
                id: localGrid
                visible: root.tab === "downloaded"
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                cellWidth: 178; cellHeight: 130
                model: root.localFiles
                delegate: Rectangle {
                    width: 170; height: 122; radius: 12
                    color: colors.alpha(colors.background, 0.55)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                    scale: localMa.containsMouse ? 1.05 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Image {
                        anchors.fill: parent; anchors.margins: 3
                        source: "file://" + modelData.path
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 7
                        width: Math.min(sizeText.implicitWidth + 12, parent.width - 14); height: 18; radius: 9
                        color: colors.alpha(colors.background, 0.78)
                        Text { id: sizeText; anchors.centerIn: parent; text: modelData.name + "  •  " + modelData.size + "K"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 7; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter }
                    }
                    MouseArea {
                        id: localMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { localGrid.currentIndex = index; Quickshell.execDetached(["xdg-open", modelData.path]) }
                    }
                }
            }
            Text {
                visible: root.tab === "downloaded"
                text: root.scanningLocal ? "Scanning…" : (root.localFiles.length + " files  •  t deletes hovered (via keyboard: focus + t)")
                color: colors.alpha(colors.outline, 0.55); font.family: "FiraCode Nerd Font"; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter
            }

            Text { visible: root.tab === "browse"; text: "arrows move • v/s select • d download • t delete • enter preview"; color: colors.alpha(colors.outline, 0.45); font.family: "FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter }
        }

        // ── preview overlay ──
        Rectangle {
            visible: root.previewIdx !== -1 && root.tab === "browse"
            anchors.fill: parent; radius: 20
            color: colors.alpha(colors.background, 0.88)
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 10
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Text { text: (root.previewIdx + 1) + " / " + resultModel.count; color: colors.alpha(colors.outline, 0.7); font.family: "FiraCode Nerd Font"; font.pixelSize: 9 }
                    Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignCenter; elide: Text.ElideMiddle; text: root.previewIdx !== -1 && root.wAt(root.previewIdx) ? (root.wAt(root.previewIdx).res + "  •  " + root.wAt(root.previewIdx).id) : ""; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                    Rectangle { width: 30; height: 30; radius: 15; color: pvCloseMa.containsMouse ? colors.alpha(colors.error, 0.18) : colors.alpha(colors.surface, 0.6); border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                        Text { anchors.centerIn: parent; text: "✕"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea { id: pvCloseMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.previewIdx = -1 } }
                }
                Image {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    source: (root.previewIdx !== -1 && root.wAt(root.previewIdx)) ? root.wAt(root.previewIdx).full : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 10; Layout.alignment: Qt.AlignHCenter
                    Rectangle { width: 150; height: 36; radius: 10; color: pvDlMa.containsMouse ? colors.alpha(colors.primary, 0.32) : colors.alpha(colors.primary, 0.2); border.width: 1; border.color: colors.alpha(colors.primary, 0.5)
                        Text { anchors.centerIn: parent; text: "↓ Download"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold }
                        MouseArea { id: pvDlMa; anchors.fill: parent; hoverEnabled: true; onClicked: { var w = root.wAt(root.previewIdx); if(w) root.downloadOne(w) } } }
                    Rectangle { width: 130; height: 36; radius: 10; color: pvDelMa.containsMouse ? colors.alpha(colors.error, 0.2) : colors.alpha(colors.surface, 0.6); border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                        Text { anchors.centerIn: parent; text: "Delete"; color: colors.error; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                        MouseArea { id: pvDelMa; anchors.fill: parent; hoverEnabled: true; onClicked: { var w = root.wAt(root.previewIdx); if(w){ root.removeWall(w); root.previewIdx = -1 } } } }
                }
            }
        }
    }
}
