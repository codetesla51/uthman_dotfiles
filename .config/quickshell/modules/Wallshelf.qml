import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components/Bloom.js" as Bloom

// Wallshelf — Wallhaven storefront. Browse + bulk download + manage.
// Applying wallpapers stays in ThemePanel (downloads symlink into its dir).
FloatingWindow {
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
    property bool keyReady: false
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
    property string sizeMode: "screen"  // screen | exact | any
    property var tags: []              // active search tags (AND-matched with free query)
    property int page: 1
    property int lastPage: 1
    property bool loading: false
    property string errorMsg: ""
    ListModel { id: resultModel }
    readonly property int resultCount: resultModel.count
    function wAt(i){
        if(i < 0 || i >= resultModel.count) return null
        var m = resultModel.get(i)
        return {id: m.wid, page: m.wpage, full: m.wfull, thumb: m.wthumb, res: m.wres, cat: m.wcat, purity: m.wpurity, views: m.wviews, favs: m.wfavs}
    }
    property var downloaded: ({})
    property var selected: ({})
    property int selCount: 0
    property int previewIdx: -1         // -1 = no preview
    property var pvTags: []             // tags of the previewed wall (fetched per open)
    property var tagCache: ({})         // wall id -> [tags], session cache: revisits are instant and cost no API calls
    property string pvTagsFor: ""       // wall id the in-flight tag fetch belongs to
    // related tags: co-occurrence across cached sets with the active seed
    // (current tags, else the open preview's). Pure local, no API.
    readonly property var relatedTags: {
        var seed = root.tags.length ? root.tags : (root.previewIdx !== -1 ? root.pvTags : [])
        if (!seed.length) return []
        var score = {}
        for (var id in tagCache) {
            var set = tagCache[id]
            var hit = false
            for (var i = 0; i < seed.length; i++) if (set.indexOf(seed[i]) !== -1) { hit = true; break }
            if (!hit) continue
            for (var j = 0; j < set.length; j++) {
                var t = set[j]
                if (seed.indexOf(t) !== -1) continue
                score[t] = (score[t] || 0) + 1
            }
        }
        return Object.keys(score).sort(function(a, b){ return score[b] - score[a] }).slice(0, 6)
    }
    property var localFiles: []
    property bool scanningLocal: false
    property string currentWallpaper: ""
    property bool curReady: false
    property double lastLocalScan: 0
    property bool debounceReset: false
    readonly property string sortParam: sorting === "latest" ? "date_added" : sorting
    readonly property string catParam: (catGeneral ? "1" : "0") + (catAnime ? "1" : "0") + (catPeople ? "1" : "0")
    readonly property string purParam: "1" + (purSketchy ? "1" : "0") + (purNsfw ? "1" : "0")
    // Screen shape as a Wallhaven ratio (1920x1080 -> 16x9). "screen" mode
    // asks for at-least-native walls in the same shape, so 4K fits and
    // 16:10 or portrait walls never sneak in as "dumb resolutions".
    readonly property string ratioParam: {
        var m = /^([0-9]+)x([0-9]+)$/.exec(root.resolution)
        if(!m) return ""
        var a = parseInt(m[1]), b = parseInt(m[2])
        function g(x, y){ return y === 0 ? x : g(y, x % y) }
        var d = g(a, b)
        if(d <= 0) return ""
        return (a / d) + "x" + (b / d)
    }

    // ── rate limit ──
    property double lastCall: 0
    property int retryCount: 0
    property var respCache: ({})
    property string pendingUrl: ""
    property string fetchUrl: ""
    property bool searchQueued: false
    property bool resetQueued: false

    title: "Wallshelf"
    implicitWidth: 1360
    implicitHeight: 880
    minimumSize: Qt.size(1100, 700)
    maximumSize: Qt.size(1500, 960)
    color: "transparent"
    visible: root.open || closeAnim.running

    onOpenChanged: { if(open){ Qt.callLater(function(){ if(root.tab === "browse") qField.forceActiveFocus(); else card.forceActiveFocus() }); if(resultModel.count === 0) search(true); root.resolveCurrent(); if(root.tab === "downloaded") root.refreshLocalMaybe(); openAnim.restart() } else closeAnim.restart() }
    onPreviewIdxChanged: if(root.previewIdx !== -1 && root.tab === "browse") root.fetchPvTags()

    // ── config ──
    // secret key lives in wallshelf.ini (gitignored) — never in wallshelf.json
    FileView {
        id: keyView
        path: Quickshell.env("HOME") + "/.config/quickshell/wallshelf.ini"
        printErrors: false
        onLoaded: {
            var m = text().match(/^\s*api_key\s*=\s*(\S+)/m)
            if(m) root.apiKey = m[1].trim()
            root.keyReady = true
        }
        onLoadFailed: root.keyReady = true
    }
    FileView {
        id: cfgView
        path: root.cfgPath
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if(!d) return
                if(d.apiKey) root.apiKey = d.apiKey
                // Stored paths are absolute — only trust them when they belong to
                // this machine's $HOME, so a fresh install keeps the defaults above.
                if(d.cacheDir && d.cacheDir.startsWith(Quickshell.env("HOME"))) root.cacheDir = d.cacheDir
                if(d.linkDir && d.linkDir.startsWith(Quickshell.env("HOME"))) root.linkDir = d.linkDir
                if(d.resOverride) root.resOverride = d.resOverride
                if(d.sizeMode) root.sizeMode = d.sizeMode
                if(d.fallbackMin) root.fallbackMin = d.fallbackMin
                if(d.resolution && !root.resOverride) root.detectedRes = d.resolution
            } catch(e) {}
        }
    }
    function cfgSave(){
        saveProc.command = ["sh","-c","mkdir -p '"+Quickshell.env("HOME")+"/.config/quickshell' '"+root.cacheDir+"' && echo '"+Qt.btoa(JSON.stringify({cacheDir: root.cacheDir, linkDir: root.linkDir, resOverride: root.resOverride, fallbackMin: root.fallbackMin, resolution: root.resolution, sizeMode: root.sizeMode}))+"' | base64 -d > '"+root.cfgPath+"'"]
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
                    var m = lines[i].trim().match(/wallhaven-([a-z0-9]+)(?:_[^/]*)?\.[a-z]+$/i)
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
                    files.push({path: p, name: name, thumb: parts[2] || p, size: parts[3] || parts[2]})
                }
                root.localFiles = files
                root.scanningLocal = false
                root.lastLocalScan = Date.now()
                root.syncCurrentToLocal()
            }
        }
    }
    function refreshLocal(){
        root.scanningLocal = true
        localProc.command = ["sh","-c","find '"+root.linkDir+"' '"+root.cacheDir+"' -path '*/thumbs' -prune -o -type f \\( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' \\) -printf '%T@|%p\\n' 2>/dev/null | sort -rn | head -n 200 | $HOME/.local/bin/mkthumbs"]
        localProc.running = true
    }
    function refreshLocalMaybe(){
        if(root.scanningLocal) return
        if(root.localFiles.length > 0 && (Date.now() - root.lastLocalScan) < 30000) return
        root.refreshLocal()
    }
    // ── current wallpaper: resolve the awww symlink, scroll the local grid to it ──
    Process {
        id: curProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                if(t !== ""){ root.currentWallpaper = t; root.curReady = true }
                root.syncCurrentToLocal()
            }
        }
    }
    function resolveCurrent(){
        curProc.command = ["sh","-c","readlink -f ~/.config/theme/current/background 2>/dev/null || readlink -f ~/.config/omarchy/current/background 2>/dev/null"]
        curProc.running = true
    }
    function syncCurrentToLocal(){
        if(!root.curReady || root.currentWallpaper === "") return
        if(root.tab !== "downloaded" || !root.localFiles.length) return
        var idx = 0
        for(var i=0;i<root.localFiles.length;i++){
            if(root.localFiles[i].path === root.currentWallpaper){ idx = i; break }
        }
        var target = idx  // 0 when nothing matches: graceful fallback, no errors
        Qt.callLater(function(){ localGrid.currentIndex = target; localGrid.positionViewAtIndex(target, GridView.Center) })
    }

    // ── search ──
    // Tag names with spaces must be quoted or Wallhaven treats them as two
    // AND-ed words. Free text stays raw so -, @, id:, like: still work.
    function tagTerm(t){
        var s = String(t).trim()
        if(s === "") return ""
        if(s.indexOf(" ") !== -1) return "\"" + s.replace(/"/g, "") + "\""
        return s
    }
    function apiUrl(pg){
        var terms = []
        for(var i = 0; i < root.tags.length; i++){
            var t = root.tagTerm(root.tags[i])
            if(t !== "") terms.push(t)
        }
        if(root.query.trim() !== "") terms.push(root.query.trim())
        var u = "https://wallhaven.cc/api/v1/search?q=" + encodeURIComponent(terms.join(" "))
        u += "&categories=" + root.catParam + "&purity=" + root.purParam
        u += "&sorting=" + root.sortParam + "&order=desc&page=" + pg
        if(root.sizeMode === "exact") u += "&resolutions=" + root.resolution
        else if(root.sizeMode === "screen"){
            if(root.ratioParam !== "") u += "&ratios=" + root.ratioParam
            u += "&atleast=" + root.resolution
        }
        if(root.apiKey !== "") u += "&apikey=" + root.apiKey
        return u
    }
    function search(reset){
        if(root.loading){ if(reset) root.resetQueued = true; root.searchQueued = true; return }
        if(reset){ root.page = 1; resultModel.clear(); root.selected = {}; root.selCount = 0; root.previewIdx = -1 }
        root.pendingUrl = root.apiUrl(root.page)
        var wait = Math.max(0, 1500 - (Date.now() - root.lastCall))
        if(wait > 0){ rateTimer.interval = wait; rateTimer.restart() }
        else root.doFetch(root.pendingUrl)
    }
    Timer { id: rateTimer; onTriggered: root.doFetch(root.pendingUrl) }
    Timer { id: searchDebounce; interval: 450; onTriggered: { var r = root.debounceReset; root.debounceReset = false; root.search(r) } }
    Timer { id: queryDebounce; interval: 550; onTriggered: root.search(true) }
    Timer { id: retryTimer; onTriggered: { if(!root.loading && root.errorMsg !== "") root.doFetch(root.pendingUrl) } }
    function debouncedSearch(reset){ if(reset) root.debounceReset = true; searchDebounce.restart() }
    function doFetch(url){
        root.fetchUrl = url
        if(respCache[url] && (Date.now() - respCache[url].at < 60000)){
            root.applyJson(respCache[url].body)
            return
        }
        root.loading = true
        root.errorMsg = ""
        fetchProc.command = ["sh","-c","curl -sS -m 25 -H 'User-Agent: wallshelf/1.0' '"+url.replace(/'/g,"'\\''")+"' -w '\\n__HTTP__%{http_code}' 2>&1"]
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
    // ── per-wall meta: tags for the preview overlay ──
    Process {
        id: wallProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var d = null
                try { d = JSON.parse(text) } catch(e) {}
                var t = []
                if(d && d.data && d.data.tags){
                    for(var i=0;i<d.data.tags.length;i++) t.push(d.data.tags[i].name)
                }
                if(root.pvTagsFor){
                    var c = Object.assign({}, root.tagCache)
                    c[root.pvTagsFor] = t.slice()
                    root.tagCache = c
                    root.pvTagsFor = ""
                }
                root.pvTags = t
            }
        }
    }
    function runQueued(){
        if(root.searchQueued){
            root.searchQueued = false
            var rq = root.resetQueued
            root.resetQueued = false
            root.search(rq)
        }
    }
    function applyResults(raw){
        root.loading = false
        var marker = "__HTTP__"
        var i = raw.lastIndexOf(marker)
        var code = i >= 0 ? raw.substring(i + marker.length).trim() : "000"
        var body = i >= 0 ? raw.substring(0, i) : raw
        if(code !== "200"){
            if(code === "429"){
                root.retryCount += 1
                if(root.retryCount <= 2){
                    var wait = Math.min(30, 4 * root.retryCount)
                    root.errorMsg = "Rate limited — retrying in " + wait + "s"
                    retryTimer.interval = wait * 1000
                    retryTimer.restart()
                } else root.errorMsg = "Rate limited by Wallhaven — try again in a minute"
            } else if(code === "401"){
                root.errorMsg = "Wallhaven rejected the API key — check wallshelf.ini"
            } else if(code === "000"){
                root.errorMsg = "Can't reach Wallhaven — check your connection"
            } else {
                root.errorMsg = "Wallhaven error " + code
            }
            root.runQueued()
            return
        }
        root.retryCount = 0
        root.applyJson(body)
    }
    function applyJson(text){
        var d = null
        try { d = JSON.parse(text) } catch(e) {}
        if(!d || !d.data){
            root.errorMsg = "Wallhaven sent an unreadable reply"
            root.runQueued()
            return
        }
        respCache[root.fetchUrl] = {at: Date.now(), body: text}
        var keys = Object.keys(respCache)
        if(keys.length > 40) delete respCache[keys[0]]
        root.lastPage = (d.meta && d.meta.last_page) || 1
        for(var k=0;k<d.data.length;k++){
            var w = d.data[k]
            resultModel.append({wid: w.id, wpage: "https://wallhaven.cc/w/" + w.id,
                wfull: w.path, wthumb: (w.thumbs && (w.thumbs.large || w.thumbs.original)) || "",
                wres: w.resolution || "", wcat: w.category || "", wpurity: w.purity || "",
                wviews: (w.views || 0), wfavs: (w.favorites || 0)})
        }
        root.runQueued()
    }
    function loadMore(){
        if(root.loading || root.page >= root.lastPage) return
        root.page += 1
        root.pendingUrl = root.apiUrl(root.page)
        var wait = Math.max(0, 1500 - (Date.now() - root.lastCall))
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
    // Card badge: compact, height-based tier — the grid never prints raw
    // "5120x2880" under every thumbnail. Full size lives in the preview.
    function resLabel(r){
        var m = /^([0-9]+)x([0-9]+)$/.exec(String(r || ""))
        if(!m) return r || ""
        var h = parseInt(m[2])
        if(h >= 2800) return "5K"
        if(h >= 2000) return "4K"
        if(h >= 1400) return "1440p"
        if(h >= 900) return "1080p"
        if(h >= 700) return "720p"
        return h + "p"
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
    function openPreview(i){
        root.pvTags = []
        root.previewIdx = i
    }
    function fetchPvTags(){
        var w = root.wAt(root.previewIdx)
        if(!w) return
        if(tagCache[w.id]){ root.pvTags = tagCache[w.id].slice(); return }
        root.pvTagsFor = w.id
        wallProc.command = ["sh","-c","curl -sS -m 15 -H 'User-Agent: wallshelf/1.0' 'https://wallhaven.cc/api/v1/w/"+w.id.replace(/'/g,"'\\''")+"' 2>/dev/null"]
        wallProc.running = true
    }
    function addTags(str){
        var t = root.tags.slice()
        var parts = str.split(",")
        for(var i=0;i<parts.length;i++){
            var n = parts[i].trim().replace(/^#/, "").toLowerCase()
            if(n && t.indexOf(n) === -1) t.push(n)
        }
        if(t.length !== root.tags.length){ root.tags = t; root.debouncedSearch(true) }
    }
    function setAsWallpaper(path){
        if(!path) return
        Quickshell.execDetached(["sh","-c","$HOME/.local/bin/set-wallpaper '"+path.replace(/'/g,"'\\''")+"' & disown"])
        // explicit pick → open the theme editor for mode/scheme/contrast
        Quickshell.execDetached(["sh","-c","sleep 2; quickshell -p ~/.config/quickshell ipc call themeedit open >/dev/null 2>&1"])
    }
    function toggleSelect(w){
        if(!w) return
        var s = Object.assign({}, root.selected)
        if(s[w.id]){ delete s[w.id]; root.selCount -= 1 }
        else { s[w.id] = true; root.selCount += 1 }
        root.selected = s
    }
    // ── grid keyboard nav: explicit index math on the view's real column count ──
    function gridCols(view){ return Math.max(1, Math.floor(view.width / view.cellWidth)) }
    function gridRows(view){ return Math.max(1, Math.floor(view.height / view.cellHeight)) }
    function gridGo(view, idx, total){
        if(total <= 0) return
        idx = Math.max(0, Math.min(total - 1, idx))
        view.currentIndex = idx
        view.positionViewAtIndex(idx, GridView.Visible)
    }
    function gridKey(view, total, key){
        var cols = root.gridCols(view)
        var idx = view.currentIndex < 0 ? 0 : view.currentIndex
        if(key === Qt.Key_Left) root.gridGo(view, idx - 1, total)
        else if(key === Qt.Key_Right) root.gridGo(view, idx + 1, total)
        else if(key === Qt.Key_Up) root.gridGo(view, idx - cols, total)
        else if(key === Qt.Key_Down) root.gridGo(view, idx + cols, total)
        else if(key === Qt.Key_Home) root.gridGo(view, 0, total)
        else if(key === Qt.Key_End) root.gridGo(view, total - 1, total)
        else if(key === Qt.Key_PageUp) root.gridGo(view, idx - cols * root.gridRows(view), total)
        else if(key === Qt.Key_PageDown) root.gridGo(view, idx + cols * root.gridRows(view), total)
        else return false
        return true
    }

    Component.onCompleted: { detectResolution(); refreshDownloaded() }

    // ── storefront card — Option A: contact sheet ──
    // The grid is the product: one glass strip on top, tags and filters in
    // two thin rails, one action bar at the bottom. Height budget at 700:
    // 32 margins + 34 top + 10 + 28 filters + 10 + 24 tags + 8 + 22 pairs
    // + 10 + 32 footer + 10 = 220 fixed; the grid gets the remaining ~480.
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: true
        Keys.onEscapePressed: { if(root.previewIdx !== -1) root.previewIdx = -1; else root.open = false }
        Keys.onPressed: function(e){
            if(root.tab === "downloaded"){
                if(e.key === Qt.Key_T){ var l = root.localFiles[localGrid.currentIndex]; if(l) root.removeLocal(l.path); e.accepted = true }
                else if(root.gridKey(localGrid, root.localFiles.length, e.key)) e.accepted = true
                return
            }
            if(root.previewIdx !== -1){
                if(e.key === Qt.Key_Left){ root.previewIdx = Math.max(0, root.previewIdx - 1); e.accepted = true }
                else if(e.key === Qt.Key_Right){ root.previewIdx = Math.min(resultModel.count - 1, root.previewIdx + 1); e.accepted = true }
                else if(e.key === Qt.Key_D){ var p = root.wAt(root.previewIdx); if(p) root.downloadOne(p); e.accepted = true }
                return
            }
            if(e.key === Qt.Key_Slash){ qField.forceActiveFocus(); e.accepted = true }
            else if(e.key === Qt.Key_D){ root.downloadBulk(); e.accepted = true }
            else if(e.key === Qt.Key_T){ var t = root.wAt(grid.currentIndex); if(t) root.removeWall(t); e.accepted = true }
            else if(e.key === Qt.Key_V || e.key === Qt.Key_S){ var v = root.wAt(grid.currentIndex); if(v) root.toggleSelect(v); e.accepted = true }
            else if(e.key === Qt.Key_Return || e.key === Qt.Key_Enter){ root.openPreview(grid.currentIndex); e.accepted = true }
            else if(root.gridKey(grid, resultModel.count, e.key)) e.accepted = true
        }

        // Same bounce pair as every other panel in the shell.
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "rotation"; from: Bloom.panelRotate; to: 0; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Bloom.normal; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "scale"; from: Bloom.panelScale; to: 1; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "rotation"; to: Bloom.panelRotate; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "scale"; to: Bloom.panelScale; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
        }

        component Kbd: Rectangle {
            id: kbd
            property string t: ""
            implicitWidth: kbdTxt.implicitWidth + 14
            implicitHeight: 21
            radius: 6
            color: colors.alpha(colors.surfaceVariant, 0.4)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.2)
            Text {
                id: kbdTxt
                anchors.centerIn: parent
                text: kbd.t
                color: colors.foreground
                font.family: colors.fontSans
                font.pixelSize: 11
                font.weight: Font.Bold
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ── row 1: brand · search · mode tabs · spinner ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 42; Layout.preferredHeight: 42; radius: 14
                    color: colors.primary
                    Text { anchors.centerIn: parent; text: "W"; color: colors.background; font.family: colors.fontSans; font.pixelSize: 16; font.weight: Font.Bold }
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: "Wallshelf"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.Bold }
                    Text { text: "wallhaven"; color: colors.alpha(colors.outline, 0.62); font.family: colors.fontSans; font.pixelSize: 11 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 260
                    implicitHeight: 42
                    visible: root.tab === "browse"
                    radius: 12
                    color: colors.alpha(colors.surface, 0.85)
                    border.width: 1
                    border.color: qField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.14)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 13
                        anchors.rightMargin: 11
                        spacing: 10
                        Rectangle { width: 6; height: 6; radius: 3; color: qField.activeFocus ? colors.primary : colors.alpha(colors.outline, 0.7); Layout.alignment: Qt.AlignVCenter }
                        TextField {
                            id: qField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Search Wallhaven…"
                            placeholderTextColor: colors.alpha(colors.outline, 0.45)
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            background: null
                            selectByMouse: true
                            onTextChanged: { var t = text.trim(); if(t !== root.query){ root.query = t; queryDebounce.restart() } }
                            onAccepted: { queryDebounce.stop(); root.query = text.trim(); root.search(true) }
                            Keys.onDownPressed: function(event){ card.forceActiveFocus(); root.gridGo(grid, grid.currentIndex < 0 ? 0 : grid.currentIndex, resultModel.count); event.accepted = true }
                            Keys.onEscapePressed: function(event){ card.forceActiveFocus(); event.accepted = true }
                        }
                        Text {
                            text: "×"
                            visible: qField.text !== ""
                            color: clearMa.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 16
                            Layout.alignment: Qt.AlignVCenter
                            MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: { qField.text = ""; queryDebounce.stop(); root.query = ""; root.search(true); qField.forceActiveFocus() } }
                        }
                    }
                }
                Item { visible: root.tab === "downloaded"; Layout.fillWidth: true }
                Repeater {
                    model: [{k:"browse",t:"Browse"},{k:"downloaded",t:"Downloaded"}]
                    Rectangle {
                        implicitWidth: 108; implicitHeight: 36; radius: 13
                        property bool on: root.tab === modelData.k
                        property bool hov: tabMa.containsMouse
                        color: on ? colors.alpha(colors.primary, 0.18) : (hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: on ? colors.primary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.4 }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.tab = modelData.k
                                if(root.tab === "downloaded"){ root.refreshLocalMaybe(); root.syncCurrentToLocal(); card.forceActiveFocus() }
                                else Qt.callLater(function(){ qField.forceActiveFocus() })
                            }
                        }
                    }
                }
                // Fixed slot: the search field never jumps when the spinner appears.
                Item {
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        visible: root.loading || root.scanningLocal
                        color: colors.alpha(colors.primary, 0.15)
                        Text {
                            anchors.centerIn: parent
                            text: "↻"
                            color: colors.primary
                            font.family: colors.fontSans
                            font.pixelSize: 16
                            RotationAnimation on rotation { running: root.loading || root.scanningLocal; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                        }
                    }
                }
            }

            // ── row 2: filter rail — category · purity · size · sort ──
            RowLayout {
                visible: root.tab === "browse"
                Layout.fillWidth: true
                spacing: 6
                Text { text: "FILTER"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignVCenter }
                Repeater {
                    model: [{k:"g",t:"General"},{k:"a",t:"Anime"},{k:"p",t:"People"}]
                    Rectangle {
                        implicitWidth: 74; implicitHeight: 28; radius: 14
                        property bool on: modelData.k === "g" ? root.catGeneral : (modelData.k === "a" ? root.catAnime : root.catPeople)
                        property bool hov: catMa.containsMouse
                        color: on ? colors.alpha(colors.primary, 0.18) : (hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: on ? colors.primary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea {
                            id: catMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if(modelData.k === "g") root.catGeneral = !root.catGeneral
                                else if(modelData.k === "a") root.catAnime = !root.catAnime
                                else root.catPeople = !root.catPeople
                                root.debouncedSearch(true)
                                card.forceActiveFocus()
                            }
                        }
                    }
                }
                Rectangle { implicitWidth: 1; implicitHeight: 16; color: colors.alpha(colors.outline, 0.15); Layout.alignment: Qt.AlignVCenter }
                Repeater {
                    model: [{k:"s",t:"SFW"},{k:"k",t:"Sketchy"},{k:"n",t:"NSFW"}]
                    Rectangle {
                        implicitWidth: 64; implicitHeight: 28; radius: 14
                        property bool on: modelData.k === "s" ? true : (modelData.k === "k" ? root.purSketchy : root.purNsfw)
                        property bool hov: purMa.containsMouse
                        color: on ? colors.alpha(colors.tertiary, 0.18) : (hov ? colors.alpha(colors.tertiary, 0.1) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.tertiary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: (modelData.k !== "s" && root.apiKey === "") ? colors.alpha(colors.outline, 0.45) : (on ? colors.tertiary : colors.foreground); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea {
                            id: purMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if(modelData.k === "s") return
                                if(root.apiKey === ""){ root.errorMsg = "Sketchy/NSFW need an API key (wallshelf.ini)"; return }
                                if(modelData.k === "k") root.purSketchy = !root.purSketchy
                                else root.purNsfw = !root.purNsfw
                                root.debouncedSearch(true)
                                card.forceActiveFocus()
                            }
                        }
                    }
                }
                Rectangle { implicitWidth: 1; implicitHeight: 16; color: colors.alpha(colors.outline, 0.15); Layout.alignment: Qt.AlignVCenter }
                Repeater {
                    model: [{k:"screen",t:"Fit"},{k:"exact",t:"Exact"},{k:"any",t:"Any"}]
                    Rectangle {
                        implicitWidth: 58; implicitHeight: 28; radius: 14
                        property bool on: root.sizeMode === modelData.k
                        property bool hov: sizeMa.containsMouse
                        color: on ? colors.alpha(colors.primary, 0.18) : (hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: on ? colors.primary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea {
                            id: sizeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.sizeMode = modelData.k; root.cfgSave(); root.debouncedSearch(true); card.forceActiveFocus() }
                        }
                    }
                }
                Rectangle { implicitWidth: 1; implicitHeight: 16; color: colors.alpha(colors.outline, 0.15); Layout.alignment: Qt.AlignVCenter }
                Repeater {
                    model: [{k:"toplist",t:"Top"},{k:"latest",t:"New"},{k:"random",t:"Random"},{k:"views",t:"Views"}]
                    Rectangle {
                        implicitWidth: 58; implicitHeight: 28; radius: 14
                        property bool on: root.sorting === modelData.k
                        property bool hov: sortMa.containsMouse
                        color: on ? colors.alpha(colors.primary, 0.18) : (hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5))
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: on ? colors.primary : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea {
                            id: sortMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { root.sorting = modelData.k; root.debouncedSearch(true); card.forceActiveFocus() }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: resultModel.count + " walls" + (root.page > 1 || root.lastPage > 1 ? " · p" + root.page + "/" + root.lastPage : "")
                    color: colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // ── row 3: active tags + add input ──
            RowLayout {
                visible: root.tab === "browse"
                Layout.fillWidth: true
                spacing: 6
                Text { text: "TAGS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignVCenter }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    clip: true
                    Repeater {
                        model: root.tags
                        Rectangle {
                            implicitHeight: 28; radius: 14
                            implicitWidth: tagRow.implicitWidth + 16
                            color: colors.alpha(colors.tertiary, 0.15)
                            border.width: 1
                            border.color: colors.alpha(colors.tertiary, 0.35)
                            RowLayout {
                                id: tagRow
                                anchors.centerIn: parent
                                spacing: 5
                                Text { text: "#" + modelData; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                Text {
                                    text: "×"
                                    color: tagXMa.containsMouse ? colors.foreground : colors.alpha(colors.tertiary, 0.8)
                                    font.family: colors.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    MouseArea { id: tagXMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: { var t = root.tags.slice(); t.splice(index, 1); root.tags = t; root.debouncedSearch(true); card.forceActiveFocus() } }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 190
                    implicitHeight: 30
                    radius: 15
                    color: colors.alpha(colors.surface, 0.85)
                    border.width: 1
                    border.color: tagField.activeFocus ? colors.alpha(colors.tertiary, 0.5) : colors.alpha(colors.outline, 0.14)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 11
                        anchors.rightMargin: 9
                        spacing: 7
                        Text { text: "+"; color: colors.alpha(colors.tertiary, 0.8); font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold; Layout.alignment: Qt.AlignVCenter }
                        TextField {
                            id: tagField
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "add tags"
                            placeholderTextColor: colors.alpha(colors.outline, 0.45)
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            background: null
                            selectByMouse: true
                            onAccepted: { root.addTags(text); text = ""; card.forceActiveFocus() }
                            Keys.onEscapePressed: function(event){ card.forceActiveFocus(); event.accepted = true }
                        }
                    }
                }
            }

            // ── row 4: co-occurring tags from the session cache ──
            RowLayout {
                visible: root.tab === "browse"
                Layout.fillWidth: true
                spacing: 6
                Text { text: "PAIRS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignVCenter }
                Text {
                    visible: root.relatedTags.length === 0
                    text: "add a tag or open a preview to see what pairs with it"
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }
                Repeater {
                    model: root.relatedTags
                    Rectangle {
                        implicitHeight: 28; radius: 14
                        implicitWidth: relT.implicitWidth + 16
                        property bool hov: relMa.containsMouse
                        color: hov ? colors.alpha(colors.secondary, 0.28) : colors.alpha(colors.secondary, 0.13)
                        border.width: 1
                        border.color: colors.alpha(colors.secondary, 0.35)
                        Text { id: relT; anchors.centerIn: parent; text: "#" + modelData; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea { id: relMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.addTags(modelData); card.forceActiveFocus() } }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // ── downloaded sub-header (browse rails collapse) ──
            RowLayout {
                visible: root.tab === "downloaded"
                Layout.fillWidth: true
                spacing: 8
                Text { text: "DOWNLOADS"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignVCenter }
                Text { text: root.scanningLocal ? "scanning…" : root.localFiles.length + " files"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                Rectangle {
                    implicitWidth: 86; implicitHeight: 30; radius: 15
                    property bool hov: rescanMa.containsMouse
                    color: hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                    Text { anchors.centerIn: parent; text: "Rescan"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                    MouseArea { id: rescanMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.refreshLocal(); card.forceActiveFocus() } }
                }
                Rectangle {
                    implicitWidth: 110; implicitHeight: 30; radius: 15
                    property bool hov: openDirMa.containsMouse
                    color: hov ? colors.alpha(colors.primary, 0.1) : colors.alpha(colors.surface, 0.5)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                    Text { anchors.centerIn: parent; text: "Open folder"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                    MouseArea { id: openDirMa; anchors.fill: parent; hoverEnabled: true; onClicked: Quickshell.execDetached(["xdg-open", root.linkDir]) }
                }
            }

            // ── main area: grid + loading / empty / error states ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 300

                GridView {
                    id: grid
                    anchors.fill: parent
                    visible: root.tab === "browse" && resultModel.count > 0
                    clip: true
                    cacheBuffer: 320
                    cellWidth: Math.max(240, Math.floor(width / 4))
                    cellHeight: Math.round(cellWidth * 0.60) + 10
                    model: resultModel
                    keyNavigationWraps: true
                    boundsBehavior: Flickable.StopAtBounds
                    onContentYChanged: { if(root.tab === "browse" && !root.loading && contentY + height > contentHeight - 320) root.loadMore() }
                    delegate: Rectangle {
                        width: GridView.view.cellWidth - 10
                        height: GridView.view.cellHeight - 10
                        radius: 12
                        color: colors.alpha(colors.background, 0.55)
                        border.width: grid.currentIndex === index ? 2 : 1
                        border.color: grid.currentIndex === index ? colors.alpha(colors.primary, 0.6) : colors.alpha(colors.outline, 0.12)
                        scale: (thumbMa.containsMouse || selCheck.containsMouse) ? 1.025 : 1.0
                        Behavior on scale { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 3
                            source: wthumb
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(480, 320)
                        }

                        // darkening for hover, focus and selection, so badges read
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 10
                            visible: thumbMa.containsMouse || selCheck.containsMouse || grid.currentIndex === index || !!root.selected[wid]
                            gradient: Gradient {
                                GradientStop { position: 0.45; color: colors.alpha(colors.background, 0) }
                                GradientStop { position: 1.0; color: colors.alpha(colors.background, 0.85) }
                            }
                        }

                        // selected tint
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            visible: !!root.selected[wid]
                            color: colors.alpha(colors.primary, 0.2)
                            border.width: 2
                            border.color: colors.alpha(colors.primary, 0.7)
                        }

                        // compact resolution — hover/focus only, never a wall of text
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            width: resText.implicitWidth + 16
                            height: 22
                            radius: 11
                            visible: !root.dlState[wid] && (thumbMa.containsMouse || selCheck.containsMouse || grid.currentIndex === index || !!root.selected[wid])
                            color: colors.alpha(colors.background, 0.78)
                            Text { id: resText; anchors.centerIn: parent; text: root.resLabel(wres); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        }

                        // downloaded check
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            width: 27; height: 27; radius: 14
                            visible: !!root.downloaded[wid]
                            color: colors.alpha(colors.primary, 0.9)
                            Text { anchors.centerIn: parent; text: ""; color: colors.alpha(colors.background, 1); font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.Bold }
                        }

                        // selection checkbox
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 7
                            width: 27; height: 27; radius: 8
                            color: root.selected[wid] ? colors.alpha(colors.primary, 0.9) : colors.alpha(colors.background, 0.62)
                            border.width: 1
                            border.color: colors.alpha(colors.primary, 0.6)
                            visible: root.selected[wid] || thumbMa.containsMouse || selCheck.containsMouse
                            Text { anchors.centerIn: parent; text: ""; visible: !!root.selected[wid]; color: colors.alpha(colors.background, 1); font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.Bold }
                        }

                        // download progress
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 3
                            height: 22
                            radius: 6
                            visible: !!root.dlState[wid]
                            color: colors.alpha(colors.background, 0.82)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 2
                                radius: 4
                                width: Math.max(0, (parent.width - 4) * ((root.dlState[wid] || {}).pct || 0) / 100)
                                color: colors.alpha(colors.primary, 0.7)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: ((root.dlState[wid] || {}).status === "queued") ? "queued" : (Math.round(((root.dlState[wid] || {}).pct || 0)) + "%  ↓")
                                color: colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            id: thumbMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { card.forceActiveFocus(); grid.currentIndex = index; var st = root.dlState[wid]; if(st && st.status === "failed") root.enqueue(root.wAt(index)) }
                            onDoubleClicked: root.downloadOne(root.wAt(index))
                        }
                        MouseArea {
                            id: selCheck
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 7
                            width: 22; height: 22
                            hoverEnabled: true
                            visible: root.selected[wid] || thumbMa.containsMouse || selCheck.containsMouse
                            onClicked: { card.forceActiveFocus(); root.toggleSelect({id: wid}) }
                        }
                    }
                }

                // downloaded manager
                GridView {
                    id: localGrid
                    anchors.fill: parent
                    visible: root.tab === "downloaded" && root.localFiles.length > 0
                    clip: true
                    cacheBuffer: 320
                    cellWidth: Math.max(240, Math.floor(width / 4))
                    cellHeight: Math.round(cellWidth * 0.60) + 10
                    model: root.localFiles
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        width: GridView.view.cellWidth - 10
                        height: GridView.view.cellHeight - 10
                        radius: 12
                        property bool thumbFailed: false
                        property bool isCurrent: modelData.path === root.currentWallpaper
                        color: colors.alpha(colors.background, 0.55)
                        border.width: localGrid.currentIndex === index ? 2 : 1
                        border.color: localGrid.currentIndex === index ? colors.alpha(colors.primary, 0.6) : colors.alpha(colors.outline, 0.12)
                        scale: (localMa.containsMouse || setMa.containsMouse) ? 1.025 : 1.0
                        Behavior on scale { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 3
                            source: thumbFailed ? ("file://" + modelData.path) : ("file://" + modelData.thumb)
                            onStatusChanged: if (status === Image.Error && !thumbFailed) thumbFailed = true
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(480, 320)
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 10
                            visible: localMa.containsMouse || setMa.containsMouse || localGrid.currentIndex === index
                            gradient: Gradient {
                                GradientStop { position: 0.45; color: colors.alpha(colors.background, 0) }
                                GradientStop { position: 1.0; color: colors.alpha(colors.background, 0.85) }
                            }
                        }

                        // current wallpaper marker
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 7
                            width: 44; height: 22; radius: 11
                            visible: isCurrent
                            color: colors.alpha(colors.primary, 0.9)
                            Text { anchors.centerIn: parent; text: "NOW"; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.6 }
                        }

                        // filename + size, hover only
                        Rectangle {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            width: Math.min(sizeText.implicitWidth + 16, parent.width - 84)
                            height: 22
                            radius: 11
                            visible: localMa.containsMouse || setMa.containsMouse || localGrid.currentIndex === index
                            color: colors.alpha(colors.background, 0.78)
                            Text { id: sizeText; anchors.centerIn: parent; text: modelData.name + " · " + modelData.size + "K"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 12; horizontalAlignment: Text.AlignHCenter }
                        }

                        // Set — topmost so the card MouseArea can't swallow it
                        Rectangle {
                            id: setBtn
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 7
                            width: 62; height: 27; radius: 13
                            visible: localMa.containsMouse || setMa.containsMouse
                            color: setMa.containsMouse ? colors.alpha(colors.primary, 0.82) : colors.alpha(colors.primary, 0.92)
                            Text { anchors.centerIn: parent; text: "Set"; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { id: setMa; anchors.fill: parent; hoverEnabled: true; onClicked: { card.forceActiveFocus(); root.setAsWallpaper(modelData.path) } }
                        }

                        MouseArea {
                            id: localMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { card.forceActiveFocus(); localGrid.currentIndex = index; Quickshell.execDetached(["xdg-open", modelData.path]) }
                        }
                    }
                }

                // loading — skeleton sheet, same 4-column rhythm as the real grid
                Item {
                    anchors.fill: parent
                    visible: root.tab === "browse" && resultModel.count === 0 && (root.loading || root.lastCall === 0)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        Text { text: "CONTACTING WALLHAVEN"; color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                        Grid {
                            columns: 4
                            spacing: 8
                            Repeater {
                                model: 8
                                Rectangle {
                                    width: (card.width - 40) / 4 - 10
                                    height: Math.round(width * 0.60)
                                    radius: 12
                                    color: colors.alpha(colors.surfaceVariant, 0.22)
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }
                        }
                    }
                }

                // empty
                Item {
                    anchors.fill: parent
                    visible: root.tab === "browse" && resultModel.count === 0 && !root.loading && root.lastCall > 0 && root.errorMsg === ""
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 10
                        Text { text: "No walls match this filter."; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                        Text {
                            text: "Fit screen widens the pool to every 16:9 wall at or above " + root.resolution.replace("x", "×") + "."
                            color: colors.alpha(colors.outline, 0.65)
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8
                            Rectangle {
                                implicitWidth: fitEmpty.implicitWidth + 28; implicitHeight: 32; radius: 10
                                property bool hov: fitEmptyMa.containsMouse
                                color: hov ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.primary, 0.15)
                                border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                                Text { id: fitEmpty; anchors.centerIn: parent; text: "Use fit screen"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                MouseArea { id: fitEmptyMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.sizeMode = "screen"; root.cfgSave(); root.search(true); card.forceActiveFocus() } }
                            }
                            Rectangle {
                                visible: root.tags.length > 0 || root.query !== ""
                                implicitWidth: clearAll.implicitWidth + 28; implicitHeight: 32; radius: 10
                                property bool hov: clearAllMa.containsMouse
                                color: hov ? colors.alpha(colors.surfaceVariant, 0.5) : colors.alpha(colors.surface, 0.5)
                                border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                                Text { id: clearAll; anchors.centerIn: parent; text: "Clear tags & search"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                MouseArea { id: clearAllMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.tags = []; qField.text = ""; queryDebounce.stop(); root.query = ""; root.search(true); card.forceActiveFocus() } }
                            }
                        }
                    }
                }

                // error / rate limited
                Item {
                    id: errState
                    anchors.fill: parent
                    visible: root.tab === "browse" && resultModel.count === 0 && !root.loading && root.errorMsg !== ""
                    property bool retrying: root.errorMsg.indexOf("retrying in") !== -1
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(500, parent.width - 60)
                        height: errCol.implicitHeight + 36
                        radius: 14
                        color: colors.alpha(colors.error, 0.12)
                        border.width: 1
                        border.color: colors.alpha(colors.error, 0.35)
                        ColumnLayout {
                            id: errCol
                            anchors.centerIn: parent
                            width: parent.width - 40
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: root.errorMsg
                                color: colors.error
                                font.family: colors.fontSans
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "The key is loaded. Retry runs the same search again."
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: colors.fontSans
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                                visible: !errState.retrying
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8
                                Rectangle {
                                    visible: !errState.retrying
                                    implicitWidth: 80; implicitHeight: 32; radius: 10
                                    property bool hov: retryMa.containsMouse
                                    color: hov ? colors.alpha(colors.error, 0.28) : colors.alpha(colors.error, 0.18)
                                    border.width: 1; border.color: colors.alpha(colors.error, 0.4)
                                    Text { anchors.centerIn: parent; text: "Retry"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                    MouseArea { id: retryMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.search(true) }
                                }
                                RowLayout {
                                    visible: errState.retrying
                                    spacing: 6
                                    Kbd { t: "Auto" }
                                    Text { text: "retry on"; color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 11 }
                                }
                            }
                        }
                    }
                }

                // downloaded empty
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.tab === "downloaded" && root.localFiles.length === 0 && !root.scanningLocal
                    spacing: 10
                    Text { text: "Nothing downloaded yet."; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "Pick a wall in Browse and press D, or double-click it."; color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 130; implicitHeight: 28; radius: 9
                        property bool hov: browseEmptyMa.containsMouse
                        color: hov ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.primary, 0.15)
                        border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                        Text { anchors.centerIn: parent; text: "Browse Wallhaven"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea { id: browseEmptyMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.tab = "browse"; Qt.callLater(function(){ qField.forceActiveFocus() }) } }
                    }
                }

                // transient status toast (download failures, queued, API retry with results on screen)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    width: Math.min(640, statusRow.implicitWidth + 28)
                    height: 32
                    radius: 9
                    visible: root.errorMsg !== "" && (resultModel.count > 0 || root.tab === "downloaded") && !(root.tab === "browse" && resultModel.count === 0)
                    property bool isInfo: root.errorMsg.indexOf("Queued") === 0
                    color: isInfo ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.error, 0.15)
                    border.width: 1
                    border.color: isInfo ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.error, 0.35)
                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            text: root.errorMsg
                            color: parent.parent.isInfo ? colors.primary : colors.error
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                            Layout.maximumWidth: 560
                        }
                        Text {
                            text: "dismiss"
                            color: colors.alpha(colors.outline, 0.75)
                            font.family: colors.fontSans
                            font.pixelSize: 11
                            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.errorMsg = "" }
                        }
                    }
                }
            }

            // ── footer: keys left, size hint + download right ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                RowLayout {
                    visible: root.tab === "browse"
                    spacing: 6
                    Kbd { t: "/" }
                    Text { text: "search"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "↑↓" }
                    Text { text: "move"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "↵" }
                    Text { text: "preview"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "V" }
                    Text { text: "select"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "D" }
                    Text { text: "download"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "Esc" }
                    Text { text: "close"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                }
                RowLayout {
                    visible: root.tab === "downloaded"
                    spacing: 6
                    Kbd { t: "↵" }
                    Text { text: "open"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "T" }
                    Text { text: "delete"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    Kbd { t: "Esc" }
                    Text { text: "close"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.tab === "browse"
                    text: root.sizeMode === "screen" ? "Fit " + root.ratioParam.replace("x", ":") + " · ≥ " + root.resolution.replace("x", "×") : (root.sizeMode === "exact" ? "Exact " + root.resolution.replace("x", "×") : "Any size")
                    color: colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }
                RowLayout {
                    visible: root.tab === "browse" && root.dlCurrent !== ""
                    spacing: 6
                    Text { text: Math.round(((root.dlState[root.dlCurrent] || {}).pct || 0)) + "%"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                    Rectangle {
                        implicitWidth: 80; implicitHeight: 4; radius: 2
                        color: colors.alpha(colors.surfaceVariant, 0.6)
                        Rectangle {
                            width: parent.width * Math.round(((root.dlState[root.dlCurrent] || {}).pct || 0)) / 100
                            height: 4; radius: 2
                            color: colors.primary
                        }
                    }
                    Text { text: root.dlActive > 0 ? root.dlActive + " queued" : "1 left"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                }
                Rectangle {
                    visible: root.tab === "browse"
                    implicitWidth: dlBtnTxt.implicitWidth + 32
                    implicitHeight: 34
                    radius: 9
                    property bool hov: dlBtnMa.containsMouse
                    color: hov ? colors.alpha(colors.primary, 0.88) : colors.primary
                    Text {
                        id: dlBtnTxt
                        anchors.centerIn: parent
                        text: root.selCount > 0 ? "↓  Download " + root.selCount : "↓  Download"
                        color: colors.background
                        font.family: colors.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    MouseArea { id: dlBtnMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.downloadBulk(); card.forceActiveFocus() } }
                }
                Text {
                    visible: root.tab === "downloaded"
                    text: root.localFiles.length + " files · T deletes the selected wall"
                    color: colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // ── preview overlay — full image, no X icon, Esc closes ──
        Rectangle {
            visible: root.previewIdx !== -1 && root.tab === "browse"
            anchors.fill: parent
            radius: 16
            color: colors.alpha(colors.background, 0.92)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: (root.previewIdx + 1) + " / " + resultModel.count
                        color: colors.alpha(colors.outline, 0.7)
                        font.family: colors.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignCenter
                        elide: Text.ElideMiddle
                        text: root.previewIdx !== -1 && root.wAt(root.previewIdx) ? (root.wAt(root.previewIdx).res + "  ·  " + root.wAt(root.previewIdx).views + " views  ·  " + root.wAt(root.previewIdx).favs + " favs") : ""
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    Rectangle {
                        implicitWidth: 70; implicitHeight: 30; radius: 9
                        property bool hov: pvCloseMa.containsMouse
                        color: hov ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                        border.width: 1
                        border.color: colors.alpha(colors.outline, 0.15)
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            Kbd { t: "Esc" }
                            Text { text: "close"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11 }
                        }
                        MouseArea { id: pvCloseMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.previewIdx = -1 }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Image {
                        anchors.fill: parent
                        source: (root.previewIdx !== -1 && root.wAt(root.previewIdx)) ? root.wAt(root.previewIdx).full : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        sourceSize: Qt.size(1920, 1080)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 21
                        visible: root.previewIdx > 0
                        color: pvPrevMa.containsMouse ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.background, 0.65)
                        border.width: 1
                        border.color: colors.alpha(colors.outline, 0.2)
                        Text { anchors.centerIn: parent; text: "‹"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 22; font.weight: Font.Bold }
                        MouseArea { id: pvPrevMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.previewIdx = Math.max(0, root.previewIdx - 1) }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 21
                        visible: root.previewIdx < resultModel.count - 1
                        color: pvNextMa.containsMouse ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.background, 0.65)
                        border.width: 1
                        border.color: colors.alpha(colors.outline, 0.2)
                        Text { anchors.centerIn: parent; text: "›"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 22; font.weight: Font.Bold }
                        MouseArea { id: pvNextMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.previewIdx = Math.min(resultModel.count - 1, root.previewIdx + 1) }
                    }
                }

                RowLayout {
                    visible: root.pvTags.length > 0
                    Layout.fillWidth: true
                    spacing: 6
                    Layout.preferredHeight: 22
                    Text { text: "TAGS"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignVCenter }
                    ListView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        spacing: 6
                        orientation: ListView.Horizontal
                        clip: true
                        model: root.pvTags
                        delegate: Rectangle {
                            implicitWidth: tagText.implicitWidth + 16
                            height: 22
                            radius: 11
                            color: pvTagMa.containsMouse ? colors.alpha(colors.tertiary, 0.28) : colors.alpha(colors.tertiary, 0.15)
                            border.width: 1
                            border.color: colors.alpha(colors.tertiary, 0.35)
                            Text { id: tagText; anchors.centerIn: parent; text: "#" + modelData; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea {
                                id: pvTagMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    var n = String(modelData).replace(/^#/, "").toLowerCase()
                                    var t = root.tags.slice()
                                    if(n && t.indexOf(n) === -1){ t.push(n); root.tags = t; root.debouncedSearch(true) }
                                    root.previewIdx = -1
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Layout.alignment: Qt.AlignHCenter
                    Rectangle {
                        visible: root.previewIdx !== -1 && root.wAt(root.previewIdx) && !!root.downloaded[root.wAt(root.previewIdx).id]
                        implicitWidth: 158; implicitHeight: 38; radius: 11
                        property bool hov: pvSetMa.containsMouse
                        color: hov ? colors.alpha(colors.primary, 0.88) : colors.primary
                        border.width: 1; border.color: colors.primary
                        Text { anchors.centerIn: parent; text: "Set wallpaper"; color: colors.background; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                        MouseArea { id: pvSetMa; anchors.fill: parent; hoverEnabled: true; onClicked: { var w = root.wAt(root.previewIdx); if(w) root.setAsWallpaper(root.linkDir + "/" + root.fnameFor(w)) } }
                    }
                    Rectangle {
                        implicitWidth: 138; implicitHeight: 38; radius: 11
                        property bool hov: pvDlMa.containsMouse
                        color: hov ? colors.alpha(colors.primary, 0.15) : "transparent"
                        border.width: 1; border.color: colors.alpha(colors.primary, 0.5)
                        Text { anchors.centerIn: parent; text: "↓ Download"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                        MouseArea { id: pvDlMa; anchors.fill: parent; hoverEnabled: true; onClicked: { var w = root.wAt(root.previewIdx); if(w) root.downloadOne(w) } }
                    }
                    Rectangle {
                        visible: root.previewIdx !== -1 && root.wAt(root.previewIdx) && !!root.downloaded[root.wAt(root.previewIdx).id]
                        implicitWidth: 112; implicitHeight: 38; radius: 11
                        property bool hov: pvDelMa.containsMouse
                        color: hov ? colors.alpha(colors.error, 0.14) : "transparent"
                        border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                        Text { anchors.centerIn: parent; text: "Delete"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                        MouseArea { id: pvDelMa; anchors.fill: parent; hoverEnabled: true; onClicked: { var w = root.wAt(root.previewIdx); if(w){ root.removeWall(w); root.previewIdx = -1 } } }
                    }
                }
            }
        }
    }
}
