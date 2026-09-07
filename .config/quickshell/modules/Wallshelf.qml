import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Wallshelf — Wallhaven browser/downloader. Browse + download + delete ONLY;
// applying wallpapers stays in ThemePanel (this only symlinks into its dir).
PanelWindow {
    id: root
    property var colors
    property bool open: false

    // ── config (one JSON, ~/.config/quickshell/wallshelf.json) ──
    property string apiKey: ""
    property string cacheDir: Quickshell.env("HOME") + "/.cache/wallshelf"
    property string linkDir: Quickshell.env("HOME") + "/dotfiles/wallpapers"
    property string resOverride: ""     // e.g. "2560x1440", empty = detected
    property string detectedRes: "1920x1080"
    property int fallbackMin: 3         // exact-res hits below this -> atleast fallback
    property bool useFallback: true
    readonly property string cfgPath: Quickshell.env("HOME") + "/.config/quickshell/wallshelf.json"
    readonly property string resolution: resOverride !== "" ? resOverride : detectedRes

    // ── search state ──
    property string query: ""
    property bool catGeneral: true
    property bool catAnime: true
    property bool catPeople: false
    property bool purSketchy: false
    property bool purNsfw: false
    property string sorting: "toplist"  // toplist | latest(date_added) | relevance | random | views | favorites
    property int page: 1
    property int lastPage: 1
    property bool loading: false
    property string errorMsg: ""
    property var results: []
    property var downloaded: ({})       // wallhaven id -> true
    readonly property string sortParam: sorting === "latest" ? "date_added" : sorting
    readonly property string catParam: (catGeneral ? "1" : "0") + (catAnime ? "1" : "0") + (catPeople ? "1" : "0")
    readonly property string purParam: "1" + (purSketchy ? "1" : "0") + (purNsfw ? "1" : "0")

    // ── rate limit: min gap between calls + backoff on 429 ──
    property double lastCall: 0
    property int backoffMs: 0
    property var respCache: ({})
    property var pendingUrl: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-wallshelf"
    WlrLayershell.layer: WlrLayer.Overlay
    IpcHandler { target: "wallshelf"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if(open){ Qt.callLater(function(){ card.forceActiveFocus() }); if(!results.length) search(true) }

    // ── config load/save ──
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

    // ── screen resolution: Quickshell screens first, hyprctl fallback ──
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

    // ── downloaded set: filenames are wallhaven-<id>.<ext> ──
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
        if(root.loading) return
        if(reset){ root.page = 1; root.results = []; root.useFallback = true }
        var now = Date.now()
        var wait = Math.max(0, 1500 - (now - root.lastCall)) + root.backoffMs
        root.pendingUrl = apiUrl(root.page, false)
        if(wait > 0){ rateTimer.interval = wait; rateTimer.restart() }
        else doFetch(root.pendingUrl)
    }
    Timer {
        id: rateTimer
        onTriggered: root.doFetch(root.pendingUrl)
    }
    function doFetch(url){
        if(respCache[url] && (Date.now() - respCache[url].at < 60000)){
            root.applyResults(respCache[url].body, false)
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
            onStreamFinished: root.applyResults(text, root.pendingUrl)
        }
    }
    function applyResults(text, url){
        root.loading = false
        var d = null
        try { d = JSON.parse(text) } catch(e) {}
        if(!d || !d.data){
            if(text.indexOf("429") !== -1 || text.toLowerCase().indexOf("rate") !== -1){
                root.backoffMs = Math.min(30000, (root.backoffMs || 2000) * 2)
                root.errorMsg = "Rate limited — backing off, scroll to retry"
            } else root.errorMsg = "Search failed"
            return
        }
        root.backoffMs = 0
        respCache[url] = {at: Date.now(), body: text}
        root.lastPage = (d.meta && d.meta.last_page) || 1
        var rows = d.data.map(function(w){
            return {id: w.id, page: "https://wallhaven.cc/w/" + w.id,
                    full: w.path, thumb: (w.thumbs && w.thumbs.large) || "",
                    res: w.resolution || "", cat: w.category || "", purity: w.purity || ""}
        })
        // exact-res too thin and fallback armed -> single atleast retry
        if(root.useFallback && root.page === 1 && rows.length < root.fallbackMin){
            root.useFallback = false
            root.pendingUrl = apiUrl(1, true)
            root.doFetch(root.pendingUrl)
            return
        }
        root.useFallback = false
        root.results = root.results.concat(rows)
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

    // ── download (curl full-res -> cache, symlink into picker dir) + delete ──
    function fnameFor(w){
        var ext = "jpg"
        var m = w.full.match(/\.([a-z0-9]+)(\?|$)/i)
        if(m) ext = m[1].toLowerCase()
        return "wallhaven-" + w.id + "." + ext
    }
    function download(w){
        if(!w || root.downloaded[w.id]) return
        var fn = fnameFor(w)
        dlProc.command = ["sh","-c","mkdir -p '"+root.cacheDir+"' '"+root.linkDir+"' && curl -sSL -m 120 -H 'User-Agent: wallshelf/1.0' '"+w.full.replace(/'/g,"'\\''")+"' -o '"+root.cacheDir+"/"+fn+"' && ln -sf '"+root.cacheDir+"/"+fn+"' '"+root.linkDir+"/"+fn+"' && echo DL_OK || echo DL_FAIL"]
        dlProc.running = true
    }
    Process {
        id: dlProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { if(text.indexOf("DL_OK") !== -1) root.refreshDownloaded(); else root.errorMsg = "Download failed" }
        }
    }
    function removeWall(w){
        if(!w) return
        var fn = fnameFor(w)
        rmProc.command = ["sh","-c","rm -f '"+root.linkDir+"/"+fn+"' '"+root.cacheDir+"/"+fn+"' && echo RM_OK"]
        rmProc.pendingId = w.id
        rmProc.running = true
    }
    Process {
        id: rmProc
        property string pendingId: ""
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if(text.indexOf("RM_OK") !== -1 && rmProc.pendingId){
                    var set = root.downloaded
                    delete set[rmProc.pendingId]
                    root.downloaded = set
                    root.downloadedChanged()
                }
            }
        }
    }

    Component.onCompleted: { detectResolution(); refreshDownloaded() }

    // dim backdrop
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.5 : 0)
        Behavior on color { ColorAnimation { duration: 220 } }
        MouseArea { anchors.fill: parent; onClicked: {} }
    }

    // storefront card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.94, 1080)
        height: Math.min(parent.height * 0.9, 760)
        radius: 20
        color: colors.alpha(colors.surface, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.16)
        focus: true
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(e){
            if(e.key === Qt.Key_D){ var w = root.results[grid.currentIndex]; if(w) root.download(w); e.accepted = true }
            else if(e.key === Qt.Key_T){ var t = root.results[grid.currentIndex]; if(t) root.removeWall(t); e.accepted = true }
            else if(e.key === Qt.Key_Left){ grid.moveCurrentIndexLeft(); e.accepted = true }
            else if(e.key === Qt.Key_Right){ grid.moveCurrentIndexRight(); e.accepted = true }
            else if(e.key === Qt.Key_Up){ grid.moveCurrentIndexUp(); e.accepted = true }
            else if(e.key === Qt.Key_Down){ grid.moveCurrentIndexDown(); e.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // header: title + search + close
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Text { text: "WALLSHELF"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 13; font.weight: Font.Bold; font.letterSpacing: 1 }
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 9
                    color: colors.alpha(colors.surface, 0.85)
                    border.width: 1; border.color: qField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.14)
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                        Text { text: ""; color: colors.alpha(colors.outline, 0.6); font.family: "FiraCode Nerd Font"; font.pixelSize: 11 }
                        TextField { id: qField; Layout.fillWidth: true; placeholderText: "Search Wallhaven…  (d download • t delete)"; placeholderTextColor: colors.alpha(colors.outline, 0.45); color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; background: null; selectByMouse: true; onAccepted: { root.query = text.trim(); root.search(true) } }
                    }
                }
            }

            // filter row: categories + purity + sort + resolution
            RowLayout {
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
                Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: root.resolution + (root.results.length ? "  •  " + root.results.length + " walls" : ""); color: colors.alpha(colors.outline, 0.55); font.family: "FiraCode Nerd Font"; font.pixelSize: 8 }
            }

            Text { visible: root.errorMsg !== ""; text: root.errorMsg; color: colors.error; font.family: "FiraCode Nerd Font"; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }

            // grid
            GridView {
                id: grid
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                cellWidth: 176; cellHeight: 128
                model: root.results
                keyNavigationWraps: true
                onContentYChanged: { if(!root.loading && contentY + height > contentHeight - 300) root.loadMore() }
                delegate: Rectangle {
                    width: 168; height: 120; radius: 12
                    color: colors.alpha(colors.background, 0.55)
                    border.width: grid.currentIndex === index ? 2 : 1
                    border.color: grid.currentIndex === index ? colors.alpha(colors.primary, 0.6) : colors.alpha(colors.outline, 0.12)
                    scale: thumbMa.containsMouse ? 1.04 : 1.0
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Image {
                        anchors.fill: parent; anchors.margins: 3
                        source: modelData.thumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                    // resolution badge
                    Rectangle {
                        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 7
                        width: resText.implicitWidth + 12; height: 18; radius: 9
                        color: colors.alpha(colors.background, 0.75)
                        Text { id: resText; anchors.centerIn: parent; text: modelData.res; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold }
                    }
                    // downloaded check
                    Rectangle {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 7
                        width: 22; height: 22; radius: 11
                        visible: !!root.downloaded[modelData.id]
                        color: colors.alpha(colors.primary, 0.85)
                        Text { anchors.centerIn: parent; text: "✓"; color: colors.alpha(colors.background, 1); font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold }
                    }
                    MouseArea {
                        id: thumbMa; anchors.fill: parent; hoverEnabled: true
                        onClicked: { grid.currentIndex = index; grid.forceActiveFocus() }
                        onDoubleClicked: root.download(modelData)
                    }
                }
            }

            Text { text: "arrows move • d download • t delete • double-click downloads"; color: colors.alpha(colors.outline, 0.45); font.family: "FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter }
        }
    }
}
