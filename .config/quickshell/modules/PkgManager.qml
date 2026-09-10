import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Package Manager — Hyprland floating window (NOT a PanelWindow popup).
// Search official + AUR via yay, multi-select queue, install with live progress,
// uninstall (native vs foreign), updates check. Wraps pacman/yay — no reimpl.
// Theming via Colors.qml (Matugen colors.css polling). Window is a real
// Hyprland window: FloatingWindow + windowrules float/center/size.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    // tabs: 0 Search  1 Queue  2 Installed  3 Updates
    property int tab: 0
    property string query: ""
    property var searchResults: []
    property int searchNav: 0
    property int instNav: 0
    property int updNav: 0
    property bool allowHover: false
    property var selectedMap: ({})
    property var installedOfficial: []
    property var installedAur: []
    property string instQuery: ""
    property int instFilter: 0 // 0 all 1 official 2 aur
    property var uninstallMap: ({})
    property var updatesList: []
    property var updateSelected: ({})
    property bool searching: false
    property bool installing: false
    property real installPct: 0
    property string installLog: ""
    property string installMode: "" // "install" or "remove" or "update"
    property string lastChecked: ""
    property string sudoPass: "" // cached after PassPrompt result, cleared after 5 min
    property string pendingAction: "" // "install" | "remove" | "update" | "updateAll"
    property var sizeMap: ({}) // name -> "15.7 MiB"
    property string totalQueuedSizeStr: {
        var total=0
        for(var k in selectedMap){
            var s=sizeMap[k]
            if(!s) continue
            var m=s.match(/([\d.]+)\s*(KiB|MiB|GiB|KB|MB|GB)/i)
            if(!m) continue
            var v=parseFloat(m[1]); var u=m[2].toLowerCase()
            if(u.indexOf("k")===0) total+=v*1024
            else if(u.indexOf("m")===0) total+=v*1024*1024
            else if(u.indexOf("g")===0) total+=v*1024*1024*1024
        }
        if(total===0) return ""
        if(total>=1073741824) return (total/1073741824).toFixed(1)+" GB"
        if(total>=1048576) return (total/1048576).toFixed(1)+" MB"
        return (total/1024).toFixed(0)+" KB"
    }

    // derived
    readonly property var selectedList: {
        var a=[]
        for (var k in selectedMap) a.push(selectedMap[k])
        return a
    }
    readonly property var installedAll: {
        var a=[]
        for (var i=0;i<installedOfficial.length;i++) a.push(installedOfficial[i])
        for (var j=0;j<installedAur.length;j++) a.push(installedAur[j])
        return a
    }
    readonly property var installedFiltered: {
        var q = instQuery.trim().toLowerCase()
        var list = installedAll
        if (instFilter === 1) list = installedOfficial
        else if (instFilter === 2) list = installedAur
        if (q === "") return list
        return list.filter(function(p){ return p.name.toLowerCase().includes(q) })
    }
    readonly property int uninstallCount: {
        var c=0; for(var k in uninstallMap) c++
        return c
    }
    readonly property int updateSelectedCount: {
        var c=0; for(var k in updateSelected) c++
        return c
    }

    title: "Package Manager"
    implicitWidth: 980
    implicitHeight: 640
    minimumSize: Qt.size(860, 520)
    maximumSize: Qt.size(1200, 800)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "pkgman"; function toggle(): void { root.open = !root.open }
        function showSearch(): void { root.tab=0; root.open=true }
        function showQueue(): void { root.tab=1; root.open=true }
        function showInstalled(): void { root.tab=2; root.open=true }
        function showUpdates(): void { root.tab=3; root.open=true }
        function search(q: string): void { root.query=q; searchField.text=q; root.tab=0; root.open=true; searchDebounce.restart(); if(q.trim().length>=1) searchProc.running=true }
        function demoSearch(q: string): void { searchField.text=q; root.query=q; root.tab=0; root.open=true; searchDebounce.restart() }
    }
    // alias for walker/rofi desktop entry
    IpcHandler { target: "packages"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if (open) { refreshInstalled(); refreshUpdates(); searchNav=0; instNav=0; updNav=0; allowHover=false; if(root.tab===0) Qt.callLater(function(){ searchField.forceActiveFocus() }) }
    onTabChanged: { searchNav=0; instNav=0; updNav=0; allowHover=false; if(open) { if(tab===0) Qt.callLater(function(){ searchField.forceActiveFocus() }); else if(tab===2) Qt.callLater(function(){ instField.forceActiveFocus() }); else card.forceActiveFocus() } }
    onSearchResultsChanged: searchNav=0
    onInstalledFilteredChanged: instNav=0
    onUpdatesListChanged: updNav=0

    function isSelected(name) { return selectedMap.hasOwnProperty(name) }
    function toggleSelect(pkg) {
        var m = JSON.parse(JSON.stringify(selectedMap))
        if (m[pkg.name]) delete m[pkg.name]
        else m[pkg.name] = pkg
        selectedMap = m
        // fetch size for this pkg if not already known (for total)
        if(!sizeMap.hasOwnProperty(pkg.name)) fetchSizes([pkg])
    }
    function removeSelected(name) {
        var m = JSON.parse(JSON.stringify(selectedMap))
        delete m[name]
        selectedMap = m
    }
    function clearQueue() { selectedMap = ({}) }

    function isUninstallSelected(name) { return uninstallMap.hasOwnProperty(name) }
    function toggleUninstall(pkg) {
        var m = JSON.parse(JSON.stringify(uninstallMap))
        if (m[pkg.name]) delete m[pkg.name]
        else m[pkg.name] = pkg
        uninstallMap = m
    }

    function isUpdateSelected(name) { return updateSelected.hasOwnProperty(name) }
    function toggleUpdate(pkg) {
        var m = JSON.parse(JSON.stringify(updateSelected))
        if (m[pkg.name]) delete m[pkg.name]
        else m[pkg.name] = pkg
        updateSelected = m
    }

    function refreshInstalled() { instOfficialProc.running = true; instAurProc.running = true }
    function refreshUpdates() {
        lastChecked = Qt.formatDateTime(new Date(), "hh:mm:ss")
        updRepoProc.running = true
        updAurProc.running = true
    }

    function parseSection(txt) {
        var lines = txt.split("\n")
        var arr = []
        for (var i=0;i<lines.length;i++) {
            var line = lines[i]
            if (!line.trim()) continue
            if (line.indexOf("/") !== -1 && line[0] !== " " && line[0] !== "\t") {
                var slash = line.indexOf("/")
                var repo = line.substring(0, slash).trim()
                var rest = line.substring(slash+1).trim()
                if (!rest) continue
                var parts = rest.split(/\s+/)
                var name = parts[0]
                var version = parts[1] || ""
                var installed = line.indexOf("[installed") !== -1
                var desc = ""
                if (i+1 < lines.length && (lines[i+1][0] === " " || lines[i+1][0] === "\t")) {
                    desc = lines[i+1].trim()
                    i++
                }
                var source = (repo === "aur") ? "AUR" : "official"
                arr.push({repo: repo, name: name, version: version, desc: desc, installed: installed, source: source})
            }
        }
        return arr
    }
    function levenshtein(a,b){
        var m=a.length, n=b.length
        if(m===0) return n
        if(n===0) return m
        var v=[]
        for(var i=0;i<=n;i++) v[i]=i
        for(var i=1;i<=m;i++){
            var prev=v[0]; v[0]=i
            for(var j=1;j<=n;j++){
                var cur=v[j]
                var cost=(a.charAt(i-1)===b.charAt(j-1))?0:1
                v[j]=Math.min(v[j]+1, v[j-1]+1, prev+cost)
                prev=cur
            }
        }
        return v[n]
    }
    function scorePackage(pkg, qraw){
        var q=qraw.toLowerCase().trim()
        if(q==="") return 99
        var name=pkg.name.toLowerCase()
        var desc=(pkg.desc||"").toLowerCase()
        var hay=name+" "+desc
        var qnospace=q.replace(/\s+/g,"")
        var namenospace=name.replace(/-/g,"")
        // token split for "fire fox" -> ["fire","fox"]
        var tokens=q.split(/\s+/)
        var allTokensInHay=true
        for(var t=0;t<tokens.length;t++) if(hay.indexOf(tokens[t])===-1) allTokensInHay=false
        if(name===q) return 0
        if(name===qnospace) return 0.5
        if(namenospace===qnospace) return 0.6
        if(name.indexOf(q)===0) return 1
        if(namenospace.indexOf(qnospace)===0) return 1.2
        if(name.indexOf(q)!==-1) return 2
        if(allTokensInHay) return 2.5
        if(desc.indexOf(q)!==-1) return 3
        // fuzzy typo tolerance: e.g. "postgress" -> "postgres", "firefoxx" -> "firefox"
        var lev=levenshtein(name, q)
        if(lev<=2) return 3.5 + lev*0.4
        var lev2=levenshtein(namenospace, qnospace)
        if(lev2<=2) return 3.8 + lev2*0.4
        // also try each token fuzzy
        for(var k=0;k<tokens.length;k++){
            if(levenshtein(name, tokens[k])<=2) return 4.5
        }
        return 9 + (hay.indexOf(tokens[0])===-1 ? 2 : 0)
    }
    function parseSearch(text) {
        var parts = text.split("___AUR___")
        var off = parseSection(parts[0] || "")
        var aur = parseSection(parts[1] || "")
        var seen = {}
        var merged = []
        for (var a=0;a<off.length;a++) if (!seen[off[a].name]) { seen[off[a].name]=true; merged.push(off[a]) }
        for (var b=0;b<aur.length;b++) if (!seen[aur[b].name]) { seen[aur[b].name]=true; merged.push(aur[b]) }
        var q = root.query.trim().toLowerCase()
        if (q !== "" && merged.length>1) {
            // attach score and sort smarter: exact > prefix > token-contains > desc > fuzzy > official first
            for(var i=0;i<merged.length;i++) merged[i]._score = scorePackage(merged[i], q)
            merged.sort(function(x,y){
                if(x._score!==y._score) return x._score - y._score
                if(x.source!==y.source) return x.source==="official" ? -1 : 1
                if(x.name.length!==y.name.length) return x.name.length - y.name.length
                return x.name.localeCompare(y.name)
            })
            for(var j=0;j<merged.length;j++) delete merged[j]._score
        }
        if (parts.length===1 && off.length===0 && aur.length===0) {
            var fallback = parseSection(text)
            var s={}; var fb=[]
            for(var k=0;k<fallback.length;k++) if(!s[fallback[k].name]){s[fallback[k].name]=true; fb.push(fallback[k])}
            var fq=root.query.trim().toLowerCase()
            for(var p=0;p<fb.length;p++) fb[p]._score=scorePackage(fb[p], fq)
            fb.sort(function(x,y){ if(x._score!==y._score) return x._score-y._score; if(x.source!==y.source) return x.source==="official"?-1:1; return x.name.length - y.name.length })
            for(var q2=0;q2<fb.length;q2++) delete fb[q2]._score
            searchResults = fb.slice(0,60)
        } else {
            searchResults = merged.slice(0,60)
        }
        searching = false
        // fetch download sizes for visible results (batched)
        if(searchResults.length>0) fetchSizes(searchResults.slice(0,20))
    }
    function fetchSizes(pkgs){
        if(!pkgs || pkgs.length===0) return
        var offNames=[], aurNames=[]
        for(var i=0;i<pkgs.length;i++){
            var n=pkgs[i].name
            if(sizeMap.hasOwnProperty(n)) continue
            if(pkgs[i].source==="AUR") aurNames.push(n)
            else offNames.push(n)
        }
        if(offNames.length>0){
            var q=offNames.join(" ").replace(/'/g,"'\\''")
            sizeProcOff.command=["sh","-c","for p in "+q+"; do pacman -Si \"$p\" 2>/dev/null | awk '/^Name/{n=\$3} /^Download Size/{print n\"|\"\$4\" \"\$5}' ; done"]
            sizeProcOff.running=true
        }
        if(aurNames.length>0){
            var q2=aurNames.join(" ").replace(/'/g,"'\\''")
            sizeProcAur.command=["sh","-c","for p in "+q2+"; do yay -Si \"$p\" 2>/dev/null | awk '/^Name/{n=\$3} /^Download Size/{print n\"|\"\$4\" \"\$5} /^Installed Size/{if(!d) print n\"|\"\$4\" \"\$5}' ; done"]
            sizeProcAur.running=true
        }
    }

    function parseInstalled(text, source) {
        var lines = text.trim().split("\n")
        var arr=[]
        for (var i=0;i<lines.length;i++) {
            var l=lines[i].trim()
            if (!l) continue
            var sp=l.indexOf(" ")
            if (sp<0) continue
            var name=l.substring(0, sp).trim()
            var ver=l.substring(sp+1).trim().split(/\s+/)[0]
            arr.push({name: name, version: ver, source: source, repo: source==="official"?"repo":"aur"})
        }
        return arr
    }

    function parseUpdates(text, source) {
        var lines=text.trim().split("\n")
        var arr=[]
        for(var i=0;i<lines.length;i++){
            var l=lines[i].trim()
            if(!l) continue
            // formats: "pkg old -> new"  or "aur/pkg old -> new"
            // strip repo prefix
            var slash=l.indexOf("/")
            if (slash!==-1 && l.indexOf(" ")>slash) {
                // remove "aur/" or "extra/"
                l=l.substring(slash+1).trim()
            }
            var parts=l.split(/\s+/)
            if(parts.length<3) continue
            var name=parts[0]
            var oldVer=parts[1]
            var newVer=parts[parts.length-1]
            // handle "->" token
            if (parts[2]==="->" && parts.length>=4) {
                oldVer=parts[1]
                newVer=parts[3]
            } else if (l.indexOf("->")!==-1) {
                var segs=l.split("->")
                if(segs.length===2){
                    var left=segs[0].trim().split(/\s+/)
                    var right=segs[1].trim().split(/\s+/)
                    name=left[0]
                    oldVer=left[left.length-1]
                    newVer=right[0]
                }
            }
            arr.push({name:name, oldVer: oldVer, newVer: newVer, source: source, repo: source})
        }
        return arr
    }

    function escPass(p){ return p.replace(/'/g, "'\\''") }
    function sudoPrefix(){ return sudoPass ? "echo '"+escPass(sudoPass)+"' | sudo -S " : "" }
    // yay's inner sudo has no terminal here, so it reaches the GUI prompt via askpass whenever the timestamp lapses
    function askpassEnv(){ return "export SUDO_ASKPASS=\"$HOME/.local/bin/askpass\"; " }
    function buildInstallCmd() {
        var off=[]
        var aur=[]
        for(var k in selectedMap){
            var p=selectedMap[k]
            if(p.source==="AUR") aur.push(k)
            else off.push(k)
        }
        var cmds=[]
        var sp=sudoPrefix()
        if(off.length>0) cmds.push("echo ':: Installing official: "+off.join(" ")+"' ; "+sp+"pacman -S --noconfirm --needed "+off.join(" ")+" 2>&1")
        if(aur.length>0) {
            // yay internally calls sudo, but we pre-auth via sudo -v with the same pass
            var aurCmd="echo ':: Installing AUR: "+aur.join(" ")+"' ; "+askpassEnv()+(sudoPass ? "printf '%s\\n' '"+escPass(sudoPass)+"' | sudo -S true 2>&1; " : "")+"yay -S --noconfirm --needed "+aur.join(" ")+" 2>&1"
            if(cmds.length>0) cmds.push("echo '___AUR_START___' ; "+aurCmd)
            else cmds.push(aurCmd)
        }
        if(cmds.length===0) return ""
        return cmds.join(" ; ")
    }

    function buildRemoveCmd() {
        var names=[]
        for(var k in uninstallMap) names.push(k)
        if(names.length===0) return ""
        return sudoPrefix()+"pacman -Rns --noconfirm "+names.join(" ")+" 2>&1"
    }

    function buildUpdateCmd(all) {
        var names=[]
        if(all){
            for(var i=0;i<updatesList.length;i++) names.push(updatesList[i].name)
        } else {
            for(var k in updateSelected) names.push(k)
        }
        if(names.length===0) return ""
        var off=[]
        var aur=[]
        for(var j=0;j<names.length;j++){
            var n=names[j]
            var src=null
            for(var u=0;u<updatesList.length;u++) if(updatesList[u].name===n) {src=updatesList[u].source; break}
            if(src==="AUR") aur.push(n)
            else off.push(n)
        }
        var sp=sudoPrefix()
        var parts=[]
        if(off.length>0) parts.push(sp+"pacman -S --noconfirm "+off.join(" ")+" 2>&1")
        if(aur.length>0) parts.push(askpassEnv()+(sudoPass ? "printf '%s\\n' '"+escPass(sudoPass)+"' | sudo -S true 2>&1; " : "")+"yay -S --noconfirm "+aur.join(" ")+" 2>&1")
        if(parts.length===0) return askpassEnv()+(sudoPass ? "printf '%s\\n' '"+escPass(sudoPass)+"' | sudo -S true 2>&1; " : "")+"yay -Syu --noconfirm 2>&1"
        return parts.join(" ; echo '___AUR_START___' ; ")
    }

    function needPass(action){
        if(sudoPass!=="") return false
        if(pendingAction!=="") return true // already asking via PassPrompt
        pendingAction=action
        var label=(action==="install")?"install packages":(action==="remove")?"remove packages":(action==="updateAll")?"update all packages":"update packages"
        passAskProc.command=["sh","-c","quickshell -p $HOME/.config/quickshell ipc call passprompt ask 'PkgManager — sudo needed to "+label+"' >/dev/null 2>&1"]
        passAskProc.running=true
        return true
    }
    function dispatchPass(a){
        if(a==="install") root.startInstall()
        else if(a==="remove") root.startRemove()
        else if(a==="update") root.startUpdate(false)
        else if(a==="updateAll") root.startUpdate(true)
    }
    function startInstall() {
        if(needPass("install")) return
        var cmd=buildInstallCmd()
        if(!cmd) return
        installMode="install"
        installLog=""; installPct=0.05; installing=true
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }
    function startRemove() {
        if(needPass("remove")) return
        var cmd=buildRemoveCmd()
        if(!cmd) return
        installMode="remove"
        installLog=""; installPct=0.05; installing=true
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }
    function startUpdate(all) {
        if(needPass(all ? "updateAll" : "update")) return
        var cmd=buildUpdateCmd(all)
        if(!cmd) return
        installMode="update"
        installLog=""; installPct=0.05; installing=true
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }


    // ---- Processes ----
    Process {
        id: searchProc
        running: false
        command: ["sh","-c", "q='"+root.query.replace(/'/g, "'\\''")+"'; [ -z \"$q\" ] && exit 0; (pacman -Ss --color=never \"$q\" 2>/dev/null | head -n 140; echo '___AUR___'; yay -Ssa --color=never -- \"$q\" 2>/dev/null | head -n 140) 2>&1"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseSearch(text)
        }
        onRunningChanged: if(running) root.searching=true
    }
    Process {
        id: sizeProcOff
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                var m=JSON.parse(JSON.stringify(sizeMap))
                for(var i=0;i<lines.length;i++){
                    var l=lines[i].trim(); if(!l) continue
                    var p=l.indexOf("|"); if(p<0) continue
                    var n=l.substring(0,p).trim(); var s=l.substring(p+1).trim()
                    if(n && s) m[n]=s
                }
                sizeMap=m
            }
        }
    }
    Process {
        id: sizeProcAur
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                var m=JSON.parse(JSON.stringify(sizeMap))
                for(var i=0;i<lines.length;i++){
                    var l=lines[i].trim(); if(!l) continue
                    var p=l.indexOf("|"); if(p<0) continue
                    var n=l.substring(0,p).trim(); var s=l.substring(p+1).trim()
                    if(n && s) m[n]=s
                }
                sizeMap=m
            }
        }
    }
    Process {
        id: instOfficialProc
        command: ["sh","-c","pacman -Qn 2>/dev/null | head -n 2000"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.installedOfficial = root.parseInstalled(text, "official")
        }
    }
    Process {
        id: instAurProc
        command: ["sh","-c","pacman -Qm 2>/dev/null | head -n 2000"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.installedAur = root.parseInstalled(text, "AUR")
        }
    }
    Process {
        id: updRepoProc
        command: ["sh","-c","pacman -Qu 2>/dev/null | head -n 200"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var a=root.parseUpdates(text, "official")
                // merge with aur later; keep repo part
                var aurPart=[]
                for(var i=0;i<root.updatesList.length;i++) if(root.updatesList[i].source==="AUR") aurPart.push(root.updatesList[i])
                // dedup by name: aur wins? keep both but repo names shouldn't overlap with aur foreign? they can overlap if AUR shadows repo
                var merged=a.concat(aurPart)
                // dedup
                var seen={}; var out=[]
                for(var j=0;j<merged.length;j++){ if(!seen[merged[j].name]){seen[merged[j].name]=true; out.push(merged[j])}}
                root.updatesList=out
            }
        }
    }
    Process {
        id: updAurProc
        command: ["sh","-c","yay -Qua 2>/dev/null | head -n 200"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var b=root.parseUpdates(text, "AUR")
                var repoPart=[]
                for(var i=0;i<root.updatesList.length;i++) if(root.updatesList[i].source==="official") repoPart.push(root.updatesList[i])
                var merged=repoPart.concat(b)
                var seen={}; var out=[]
                for(var j=0;j<merged.length;j++){ if(!seen[merged[j].name]){seen[merged[j].name]=true; out.push(merged[j])}}
                root.updatesList=out
            }
        }
    }
    // sudo password via the dedicated PassPrompt module — ask() then poll st() like ~/.local/bin/askpass
    Process {
        id: passAskProc
        running: false
        onExited: function(code){
            if(code!==0 && root.pendingAction!==""){ root.pendingAction=""; return }
            if(root.pendingAction!=="") passPoll.restart()
        }
    }
    Timer { id: passPoll; interval: 250; repeat: true; onTriggered: passStProc.running=true }
    Process {
        id: passStProc
        running: false
        command: ["sh","-c","quickshell -p $HOME/.config/quickshell ipc call passprompt st 2>/dev/null | tr -d '\" '"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var st=text.trim()
                if(st==="done"){
                    passPoll.stop()
                    passResProc.running=true
                } else if(st==="cancelled" || st==="idle"){
                    passPoll.stop()
                    root.pendingAction=""
                }
            }
        }
    }
    Process {
        id: passResProc
        running: false
        command: ["sh","-c","quickshell -p $HOME/.config/quickshell ipc call passprompt result 2>/dev/null | sed 's/^\"//; s/\"$//'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var a=root.pendingAction
                root.pendingAction=""
                var p=text.trim()
                if(a!=="" && p!==""){
                    root.sudoPass=p
                    passClearTimer.restart()
                    root.dispatchPass(a)
                }
            }
        }
    }
    Timer { id: passClearTimer; interval: 300000; onTriggered: root.sudoPass="" }
    Process {
        id: installProc
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line){
                root.installLog += line + "\n"
                // progress sync: transaction steps "( 1/5)" AND pacman/yay download bars "NN%" — keep the bar monotonic so downloads visibly move it
                var m=line.match(/\(\s*(\d+)\s*\/\s*(\d+)\s*\)/)
                if(m){
                    var cur=parseInt(m[1]); var tot=parseInt(m[2])
                    if(tot>0 && cur/tot>root.installPct) root.installPct = cur/tot
                } else {
                    var pm=line.match(/(\d{1,3})(?:\.\d+)?\s*%/)
                    if(pm){
                        var pct=parseInt(pm[1])/100
                        if(pct>root.installPct && pct<1) root.installPct=pct
                    }
                }
                if(line.indexOf("checking")!==-1) { if(root.installPct<0.15) root.installPct=0.15 }
                else if(line.indexOf("resolving")!==-1) { if(root.installPct<0.10) root.installPct=0.10 }
                // auto scroll: handled via Flickable contentY binding in log view
                if(root.installLog.length>8000) root.installLog = root.installLog.slice(-8000)
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(line){ root.installLog += line + "\n" }
        }
        onRunningChanged: {
            if(!running && root.installing){
                // finished
                root.installPct = 1.0
                root.installLog += "\n— done —\n"
                // refresh lists after a short delay, don't auto-close
                refreshTimer.restart()
            }
        }
    }
    Timer { id: refreshTimer; interval: 1200; onTriggered: { root.installing=false; root.refreshInstalled(); root.refreshUpdates() } }
    Timer { id: searchDebounce; interval: 380; onTriggered: if(root.query.trim().length>=1) searchProc.running=true; else {searchResults=[]; searching=false} }

    // card
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        color: colors.alpha(colors.background, 0.72)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.12)
        focus: root.open
        Keys.onEscapePressed: {
            if(root.installing) return
            root.open=false
        }
        Keys.onPressed: function(e){
            if(root.installing) return
            if(root.tab===0 && root.searchResults.length>0){
                if(e.key===Qt.Key_Down){ root.searchNav=Math.min(root.searchNav+1, root.searchResults.length-1); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Up){ root.searchNav=Math.max(root.searchNav-1,0); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter){ var p=root.searchResults[root.searchNav]; if(p) root.toggleSelect(p); e.accepted=true }
                else if(e.key===Qt.Key_Space){ var q=root.searchResults[root.searchNav]; if(q) root.toggleSelect(q); e.accepted=true }
            } else if(root.tab===2 && root.installedFiltered.length>0){
                if(e.key===Qt.Key_Down){ root.instNav=Math.min(root.instNav+1, root.installedFiltered.length-1); instList.positionViewAtIndex(root.instNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Up){ root.instNav=Math.max(root.instNav-1,0); instList.positionViewAtIndex(root.instNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter || e.key===Qt.Key_Space){ var r=root.installedFiltered[root.instNav]; if(r) root.toggleUninstall(r); e.accepted=true }
            } else if(root.tab===3 && root.updatesList.length>0){
                if(e.key===Qt.Key_Down){ root.updNav=Math.min(root.updNav+1, root.updatesList.length-1); updList.positionViewAtIndex(root.updNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Up){ root.updNav=Math.max(root.updNav-1,0); updList.positionViewAtIndex(root.updNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter || e.key===Qt.Key_Space){ var u=root.updatesList[root.updNav]; if(u) root.toggleUpdate(u); e.accepted=true }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // header — title + stats + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "󰏖  PACKAGE MANAGER"
                    color: colors.primary
                    font.family: colors.fontSans
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.1
                }
                Rectangle {
                    Layout.preferredWidth: queueBadge.implicitWidth+14
                    Layout.preferredHeight: 22
                    radius: 11
                    visible: root.selectedList.length>0
                    color: colors.alpha(colors.primary, 0.18)
                    border.width:1; border.color: colors.alpha(colors.primary, 0.35)
                    Text {
                        id: queueBadge
                        anchors.centerIn: parent
                        text: root.selectedList.length + " queued"
                        color: colors.primary
                        font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.installedAll.length + " installed  •  " + root.updatesList.length + " updates"
                    color: colors.alpha(colors.outline, 0.65)
                    font.family: colors.fontSans; font.pixelSize: 9
                }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width:1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // tab bar — glass pills, hover lifts
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        {l:"Search", c: root.searchResults.length},
                        {l:"Queue", c: root.selectedList.length},
                        {l:"Installed", c: root.installedAll.length},
                        {l:"Updates", c: root.updatesList.length}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 36
                        radius: 12
                        color: root.tab===index ? colors.alpha(colors.primary, 0.20) : ma.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : colors.alpha(colors.surface, 0.55)
                        border.width:1
                        border.color: root.tab===index ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.14)
                        scale: ma.containsMouse ? 1.02 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: modelData.l
                                color: root.tab===index ? colors.primary : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: root.tab===index ? Font.ExtraBold : Font.Bold
                            }
                            Rectangle {
                                visible: modelData.c>0
                                width: cnt.implicitWidth+10; height: 18; radius: 9
                                color: root.tab===index ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.surfaceVariant, 0.5)
                                Text { id: cnt; anchors.centerIn: parent; text: modelData.c; color: root.tab===index?colors.primary:colors.alpha(colors.outline,0.9); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                            }
                        }
                        MouseArea { id: ma; anchors.fill: parent; hoverEnabled:true; onClicked: root.tab=index }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height:1; color: colors.alpha(colors.outline,0.12) }

            // ---- content stack ----
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.tab

                // TAB 0: SEARCH
                ColumnLayout {
                    spacing: 10
                    // search field
                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        radius: 12
                        color: colors.alpha(colors.surface, 0.75)
                        border.width:1
                        border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.15)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14; anchors.rightMargin: 10
                            spacing: 10
                            Text { text: ""; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 14 }
                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Search pacman + AUR…  (e.g. firefox, neovim)"
                                placeholderTextColor: colors.alpha(colors.outline, 0.45)
                                color: colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 12
                                background: null
                                selectByMouse: true
                                onTextChanged: { root.query=text; searchDebounce.restart() }
                                Keys.onPressed: function(e){
                                    if(e.key===Qt.Key_Escape){ root.open=false; e.accepted=true }
                                    else if(e.key===Qt.Key_Down){ if(root.searchResults.length>0){ root.searchNav=Math.min(root.searchNav+1, root.searchResults.length-1); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true } }
                                    else if(e.key===Qt.Key_Up){ if(root.searchResults.length>0){ root.searchNav=Math.max(root.searchNav-1,0); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true } }
                                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter || e.key===Qt.Key_Space){ var p=root.searchResults[root.searchNav]; if(p){ root.toggleSelect(p)} else if(root.searchResults.length>0) root.toggleSelect(root.searchResults[0]); e.accepted=true }
                                }
                            }
                            // spinner / clear
                            Text {
                                visible: root.searching
                                text: ""
                                color: colors.primary
                                font.family: colors.fontSans; font.pixelSize: 12
                                RotationAnimation on rotation { running: root.searching; loops: Animation.Infinite; from:0; to:360; duration: 700 }
                            }
                            Text {
                                visible: !root.searching && searchField.text!==""
                                text: "󰅖"
                                color: clearMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.6)
                                font.family: colors.fontSans; font.pixelSize: 14
                                MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled:true; onClicked: {searchField.text=""; root.query=""; root.searchResults=[]} }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: root.searching ? "Searching…" : root.query.trim()==="" ? "Type to search official repos + AUR" : root.searchResults.length+" results  •  click checkbox to queue"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 9; Layout.fillWidth:true; elide: Text.ElideRight }
                        Text { visible: root.selectedList.length>0; text: root.selectedList.length+" queued → Queue tab"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    }

                    // results list — arrow keys + mouse
                    ListView {
                        id: searchList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.searchResults
                        currentIndex: root.searchNav
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: searchList.width
                            height: 64
                            radius: 12
                            color: modelData.name && root.isSelected(modelData.name) ? colors.alpha(colors.primary, 0.14) : index===root.searchNav ? colors.alpha(colors.primary, 0.08) : maS.containsMouse ? colors.alpha(colors.surfaceVariant, 0.28) : colors.alpha(colors.surface, 0.45)
                            border.width:1
                            border.color: modelData.name && root.isSelected(modelData.name) ? colors.alpha(colors.primary, 0.45) : index===root.searchNav ? colors.alpha(colors.primary, 0.35) : maS.containsMouse ? colors.alpha(colors.primary, 0.22) : colors.alpha(colors.outline, 0.12)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                anchors.topMargin: 8; anchors.bottomMargin: 8
                                spacing: 12
                                // checkbox
                                Rectangle {
                                    Layout.preferredWidth: 22; Layout.preferredHeight: 22; radius: 6
                                    color: modelData.name && root.isSelected(modelData.name) ? colors.primary : "transparent"
                                    border.width:1; border.color: modelData.name && root.isSelected(modelData.name) ? colors.primary : colors.alpha(colors.outline, 0.35)
                                    Text { anchors.centerIn: parent; visible: modelData.name && root.isSelected(modelData.name); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleSelect(modelData) }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: false }
                                        Text { text: modelData.version; color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 9 }
                                        Rectangle {
                                            visible: (sizeMap[modelData.name]||"")!==""
                                            Layout.preferredWidth: sTxt.implicitWidth+10; Layout.preferredHeight: 18; radius: 9
                                            color: colors.alpha(colors.outline,0.10)
                                            Text { id: sTxt; anchors.centerIn: parent; text: sizeMap[modelData.name]||""; color: colors.alpha(colors.outline,0.75); font.family: colors.fontSans; font.pixelSize: 8 }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: srcTxt.implicitWidth+10; Layout.preferredHeight: 18; radius: 9
                                            color: modelData.source==="AUR" ? colors.alpha(colors.tertiary, 0.18) : colors.alpha(colors.secondary, 0.18)
                                            border.width:1; border.color: modelData.source==="AUR" ? colors.alpha(colors.tertiary, 0.35) : colors.alpha(colors.secondary, 0.35)
                                            Text { id: srcTxt; anchors.centerIn: parent; text: modelData.source==="AUR" ? "AUR" : modelData.repo; color: modelData.source==="AUR"?colors.tertiary:colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                        }
                                        Rectangle {
                                            visible: modelData.installed
                                            width: instTxt.implicitWidth+10; height: 18; radius: 9
                                            color: colors.alpha(colors.primary, 0.15)
                                            Text { id: instTxt; anchors.centerIn: parent; text: "installed"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                    Text { text: modelData.desc || "—"; color: colors.alpha(colors.foreground, 0.72); font.family: colors.fontSans; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true; maximumLineCount: 2; wrapMode: Text.Wrap }
                                }
                            }
                            MouseArea { id: maS; anchors.fill: parent; hoverEnabled:true; onEntered: if(root.allowHover) root.searchNav=index; onPositionChanged: if(!root.allowHover) root.allowHover=true; onClicked: root.toggleSelect(modelData) }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !root.searching && root.searchResults.length===0 && root.query.trim()!==""
                            text: "No results"
                            color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 11
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !root.searching && root.searchResults.length===0 && root.query.trim()===""
                            text: "Try  “ghostty”  •  “zed”  •  “firefox”"
                            color: colors.alpha(colors.outline,0.4); font.family: colors.fontSans; font.pixelSize: 10
                        }
                    }
                }

                // TAB 1: QUEUE / INSTALL
                ColumnLayout {
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: root.selectedList.length===0 ? "No packages queued" : root.selectedList.length+" package"+(root.selectedList.length>1?"s":"")+" queued" + (totalQueuedSizeStr? " · "+totalQueuedSizeStr : ""); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; Layout.fillWidth:true }
                        Rectangle {
                            visible: root.selectedList.length>0 && !root.installing
                            width: clearQTxt.implicitWidth+14; height: 28; radius: 9
                            color: clearQMa.containsMouse?colors.alpha(colors.surfaceVariant,0.6):colors.alpha(colors.surface,0.6)
                            border.width:1; border.color: colors.alpha(colors.outline,0.15)
                            Text { id: clearQTxt; anchors.centerIn: parent; text: "Clear"; color: colors.alpha(colors.outline,0.9); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                            MouseArea { id: clearQMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.clearQueue() }
                        }
                    }

                    ListView {
                        id: queueList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.installing
                        clip: true
                        model: root.selectedList
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            width: queueList.width
                            height: 44
                            radius: 10
                            color: colors.alpha(colors.surface, 0.55)
                            border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 10
                                spacing: 10
                                Rectangle { width: 8; height: 8; radius:4; color: modelData.source==="AUR"?colors.tertiary:colors.secondary }
                                Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.version; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 9 }
                                Rectangle {
                                    width: 44; height: 22; radius: 8
                                    color: modelData.source==="AUR"?colors.alpha(colors.tertiary,0.18):colors.alpha(colors.secondary,0.18)
                                    Text { anchors.centerIn: parent; text: modelData.source==="AUR"?"AUR":modelData.repo; color: modelData.source==="AUR"?colors.tertiary:colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                }
                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: rmMa.containsMouse?colors.alpha(colors.error,0.15):"transparent"
                                    Text { anchors.centerIn: parent; text: "󰅖"; color: rmMa.containsMouse?colors.error:colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 12 }
                                    MouseArea { id: rmMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.removeSelected(modelData.name) }
                                }
                            }
                        }
                    }
                    Text {
                        visible: !root.installing && root.selectedList.length===0
                        Layout.alignment: Qt.AlignHCenter
                        text: "Queue packages from Search → they appear here"
                        color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 10
                    }

                    // install progress area — nice bar + log (not raw scrollback only)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.installing
                        // animated progress bar — glass + shimmer
                        Rectangle {
                            Layout.fillWidth: true
                            height: 10
                            radius: 5
                            color: colors.alpha(colors.surfaceVariant, 0.35)
                            clip: true
                            Rectangle {
                                id: progFill
                                width: parent.width * root.installPct
                                height: parent.height
                                radius: 5
                                color: colors.primary
                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: root.installMode==="install" ? "Installing…" : root.installMode==="remove" ? "Removing…" : "Updating…"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold; Layout.fillWidth:true }
                            Text { text: Math.round(root.installPct*100)+"%"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                        }
                        // live log — scrollable, monospaced, not raw fullscreen dump
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 220
                            radius: 12
                            color: colors.alpha(colors.surface, 0.65)
                            border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            clip: true
                            Flickable {
                                id: logFlick
                                anchors.fill: parent
                                anchors.margins: 10
                                contentHeight: logText.implicitHeight
                                contentWidth: width
                                clip: true
                                flickableDirection: Flickable.VerticalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                onContentHeightChanged: if(contentHeight>height) contentY = Math.max(0, contentHeight - height)
                                Text {
                                    id: logText
                                    width: logFlick.width
                                    text: root.installLog || "Waiting for output…"
                                    color: colors.alpha(colors.foreground, 0.85)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    wrapMode: Text.Wrap
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                visible: !installProc.running
                                width: 90; height: 28; radius: 9
                                color: colors.alpha(colors.surface,0.6); border.width:1; border.color: colors.alpha(colors.outline,0.15)
                                Text { anchors.centerIn: parent; text: "Close"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; onClicked: {root.installing=false; root.installPct=0; root.installLog=""} }
                            }
                        }
                    }

                    // install button (hidden while installing)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 12
                        visible: !root.installing
                        color: root.selectedList.length===0 ? colors.alpha(colors.surfaceVariant,0.35) : installMa.containsMouse ? colors.alpha(colors.primary, 0.28) : colors.alpha(colors.primary, 0.18)
                        border.width:1
                        border.color: root.selectedList.length===0 ? colors.alpha(colors.outline,0.12) : colors.alpha(colors.primary, 0.45)
                        enabled: root.selectedList.length>0
                        opacity: root.selectedList.length===0 ? 0.55 : 1
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "󰄠"; color: root.selectedList.length===0?colors.alpha(colors.outline,0.6):colors.primary; font.family: colors.fontSans; font.pixelSize: 14 }
                            Text { text: "Install  ("+root.selectedList.length+")"; color: root.selectedList.length===0?colors.alpha(colors.outline,0.6):colors.primary; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold }
                            Text { visible: root.selectedList.length>0; text: "— pacman for repo, yay for AUR"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 8 }
                        }
                        MouseArea { id: installMa; anchors.fill: parent; hoverEnabled:true; enabled: root.selectedList.length>0; onClicked: root.startInstall() }
                    }
                    Text {
                        visible: !root.installing && root.selectedList.length>0
                        text: "Will run: pacman for official, yay for AUR  •  sudo prompt pops via PassPrompt (cached 5 min)"
                        color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter
                    }
                }

                // TAB 2: INSTALLED / UNINSTALL
                ColumnLayout {
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            height: 38
                            radius: 10
                            color: colors.alpha(colors.surface, 0.75)
                            border.width:1; border.color: instField.activeFocus ? colors.alpha(colors.primary,0.4) : colors.alpha(colors.outline,0.14)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 8
                                Text { text: ""; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 12 }
                                TextField {
                                    id: instField
                                    Layout.fillWidth: true
                                    placeholderText: "Filter installed…"
                                    placeholderTextColor: colors.alpha(colors.outline,0.45)
                                    color: colors.foreground
                                    font.family: colors.fontSans; font.pixelSize: 11
                                    background: null
                                    onTextChanged: root.instQuery=text
                                    Keys.onPressed: function(e){
                                        if(e.key===Qt.Key_Down){ if(root.installedFiltered.length>0){ root.instNav=Math.min(root.instNav+1, root.installedFiltered.length-1); instList.positionViewAtIndex(root.instNav, ListView.Contain); e.accepted=true } }
                                        else if(e.key===Qt.Key_Up){ if(root.installedFiltered.length>0){ root.instNav=Math.max(root.instNav-1,0); instList.positionViewAtIndex(root.instNav, ListView.Contain); e.accepted=true } }
                                        else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter || e.key===Qt.Key_Space){ var r=root.installedFiltered[root.instNav]; if(r) root.toggleUninstall(r); e.accepted=true }
                                        else if(e.key===Qt.Key_Escape){ root.open=false; e.accepted=true }
                                    }
                                }
                                Text { visible: instField.text!==""; text: "󰅖"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 12; MouseArea { anchors.fill: parent; onClicked: instField.text="" } }
                            }
                        }
                        Rectangle {
                            width: 28; height: 28; radius: 9
                            color: refreshInstMa.containsMouse?colors.alpha(colors.primary,0.12):colors.alpha(colors.surface,0.6)
                            border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                            MouseArea { id: refreshInstMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.refreshInstalled() }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [{k:0,l:"All"},{k:1,l:"Official"},{k:2,l:"AUR"}]
                            delegate: Rectangle {
                                required property var modelData
                                width: 78; height: 26; radius: 9
                                color: root.instFilter===modelData.k ? colors.alpha(colors.primary,0.20) : maF.containsMouse?colors.alpha(colors.surfaceVariant,0.4):colors.alpha(colors.surface,0.55)
                                border.width:1; border.color: root.instFilter===modelData.k ? colors.alpha(colors.primary,0.45) : colors.alpha(colors.outline,0.12)
                                Text { anchors.centerIn: parent; text: modelData.l; color: root.instFilter===modelData.k?colors.primary:colors.alpha(colors.foreground,0.8); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                MouseArea { id: maF; anchors.fill: parent; hoverEnabled:true; onClicked: root.instFilter=modelData.k }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: root.installedFiltered.length+" / "+root.installedAll.length; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 9 }
                        Text { visible: root.uninstallCount>0; text: "•  "+root.uninstallCount+" selected"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    }

                    // uninstall progress reuse same area when installing remove
                    ColumnLayout {
                        visible: root.installing && root.installMode==="remove"
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; height: 8; radius: 4
                            color: colors.alpha(colors.surfaceVariant,0.35)
                            Rectangle { width: parent.width*root.installPct; height: parent.height; radius:4; color: colors.error; Behavior on width { NumberAnimation { duration: 250 } } }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 140; radius: 10
                            color: colors.alpha(colors.surface,0.6); border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            clip: true
                            Flickable {
                                anchors.fill: parent; anchors.margins: 8
                                contentHeight: rmLog.implicitHeight; clip:true; boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                onContentHeightChanged: if(contentHeight>height) contentY = Math.max(0, contentHeight-height)
                                Text { id: rmLog; width: parent.width; text: root.installLog; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; wrapMode: Text.Wrap }
                            }
                        }
                    }

                    ListView {
                        id: instList
                        visible: !(root.installing && root.installMode==="remove")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.installedFiltered
                        currentIndex: root.instNav
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: instList.width
                            height: 42
                            radius: 10
                            color: modelData.name && root.isUninstallSelected(modelData.name) ? colors.alpha(colors.error, 0.12) : index===root.instNav ? colors.alpha(colors.error, 0.08) : maI.containsMouse ? colors.alpha(colors.surfaceVariant,0.28) : colors.alpha(colors.surface,0.45)
                            border.width:1; border.color: modelData.name && root.isUninstallSelected(modelData.name) ? colors.alpha(colors.error,0.4) : index===root.instNav ? colors.alpha(colors.error, 0.30) : colors.alpha(colors.outline,0.12)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 10
                                Rectangle {
                                    width: 22; height: 22; radius: 6
                                    color: modelData.name && root.isUninstallSelected(modelData.name) ? colors.error : "transparent"
                                    border.width:1; border.color: modelData.name && root.isUninstallSelected(modelData.name) ? colors.error : colors.alpha(colors.outline,0.35)
                                    Text { anchors.centerIn: parent; visible: modelData.name && root.isUninstallSelected(modelData.name); text: ""; color: "white"; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleUninstall(modelData) }
                                }
                                Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { text: modelData.version; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 9; elide: Text.ElideRight }
                                Rectangle {
                                    width: 52; height: 18; radius: 9
                                    color: modelData.source==="AUR"?colors.alpha(colors.tertiary,0.15):colors.alpha(colors.secondary,0.15)
                                    Text { anchors.centerIn: parent; text: modelData.source==="AUR"?"AUR":"official"; color: modelData.source==="AUR"?colors.tertiary:colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                }
                            }
                            MouseArea { id: maI; anchors.fill: parent; hoverEnabled:true; onEntered: if(root.allowHover) root.instNav=index; onPositionChanged: if(!root.allowHover) root.allowHover=true; onClicked: root.toggleUninstall(modelData) }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        radius: 11
                        visible: !(root.installing && root.installMode==="remove")
                        color: root.uninstallCount===0 ? colors.alpha(colors.surfaceVariant,0.35) : rmAllMa.containsMouse?colors.alpha(colors.error,0.22):colors.alpha(colors.error,0.14)
                        border.width:1; border.color: root.uninstallCount===0?colors.alpha(colors.outline,0.12):colors.alpha(colors.error,0.4)
                        enabled: root.uninstallCount>0
                        opacity: root.uninstallCount===0 ? 0.55 : 1
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text { text: "󰆴"; color: root.uninstallCount===0?colors.alpha(colors.outline,0.6):colors.error; font.family: colors.fontSans; font.pixelSize: 13 }
                            Text { text: "Remove selected  ("+root.uninstallCount+")"; color: root.uninstallCount===0?colors.alpha(colors.outline,0.6):colors.error; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.ExtraBold }
                        }
                        MouseArea { id: rmAllMa; anchors.fill: parent; hoverEnabled:true; enabled: root.uninstallCount>0; onClicked: root.startRemove() }
                    }
                    Text { visible: !(root.installing && root.installMode==="remove"); text: "Batch remove — runs:  pkexec pacman -Rns"; color: colors.alpha(colors.outline,0.45); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                }

                // TAB 3: UPDATES
                ColumnLayout {
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: root.updatesList.length===0 ? "Up to date" : root.updatesList.length+" update"+(root.updatesList.length>1?"s":"")+" available"; color: root.updatesList.length===0?colors.alpha(colors.outline,0.7):colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold; Layout.fillWidth:true }
                        Text { text: root.lastChecked ? "checked "+root.lastChecked : ""; color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 8 }
                        Rectangle {
                            width: 68; height: 26; radius: 9
                            color: updRefreshMa.containsMouse?colors.alpha(colors.primary,0.15):colors.alpha(colors.surface,0.6)
                            border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            Text { anchors.centerIn: parent; text: "Refresh"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                            MouseArea { id: updRefreshMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.refreshUpdates() }
                        }
                    }

                    // update progress
                    ColumnLayout {
                        visible: root.installing && root.installMode==="update"
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; height: 8; radius: 4
                            color: colors.alpha(colors.surfaceVariant,0.35)
                            Rectangle { width: parent.width*root.installPct; height: parent.height; radius:4; color: colors.primary; Behavior on width { NumberAnimation { duration:250 } } }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 160; radius:10
                            color: colors.alpha(colors.surface,0.6); border.width:1; border.color: colors.alpha(colors.outline,0.12)
                            clip: true
                            Flickable {
                                anchors.fill: parent; anchors.margins: 8
                                contentHeight: updLog.implicitHeight; clip:true
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                onContentHeightChanged: if(contentHeight>height) contentY=Math.max(0,contentHeight-height)
                                Text { id: updLog; width: parent.width; text: root.installLog; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; wrapMode: Text.Wrap }
                            }
                        }
                    }

                    ListView {
                        id: updList
                        visible: !(root.installing && root.installMode==="update")
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.updatesList
                        currentIndex: root.updNav
                        spacing: 5
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: updList.width
                            height: 48
                            radius: 10
                            color: modelData.name && root.isUpdateSelected(modelData.name) ? colors.alpha(colors.primary,0.14) : index===root.updNav ? colors.alpha(colors.primary, 0.08) : maU.containsMouse ? colors.alpha(colors.surfaceVariant,0.28) : colors.alpha(colors.surface,0.45)
                            border.width:1; border.color: modelData.name && root.isUpdateSelected(modelData.name) ? colors.alpha(colors.primary,0.4) : index===root.updNav ? colors.alpha(colors.primary, 0.30) : colors.alpha(colors.outline,0.12)
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10; anchors.rightMargin: 10
                                spacing: 10
                                Rectangle {
                                    width: 22; height: 22; radius: 6
                                    color: modelData.name && root.isUpdateSelected(modelData.name) ? colors.primary : "transparent"
                                    border.width:1; border.color: modelData.name && root.isUpdateSelected(modelData.name) ? colors.primary : colors.alpha(colors.outline,0.35)
                                    Text { anchors.centerIn: parent; visible: modelData.name && root.isUpdateSelected(modelData.name); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleUpdate(modelData) }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                    Text { text: modelData.oldVer + "  →  " + modelData.newVer; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 9 }
                                }
                                Rectangle {
                                    width: 52; height: 18; radius: 9
                                    color: modelData.source==="AUR"?colors.alpha(colors.tertiary,0.15):colors.alpha(colors.secondary,0.15)
                                    Text { anchors.centerIn: parent; text: modelData.source==="AUR"?"AUR":"official"; color: modelData.source==="AUR"?colors.tertiary:colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                                }
                            }
                            MouseArea { id: maU; anchors.fill: parent; hoverEnabled:true; onEntered: if(root.allowHover) root.updNav=index; onPositionChanged: if(!root.allowHover) root.allowHover=true; onClicked: root.toggleUpdate(modelData) }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.updatesList.length===0 && !(root.installing && root.installMode==="update")
                            text: "No updates — you're current"
                            color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 11
                        }
                    }

                    RowLayout {
                        visible: !(root.installing && root.installMode==="update")
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 11
                            color: root.updateSelectedCount===0 ? colors.alpha(colors.surfaceVariant,0.35) : selMa.containsMouse?colors.alpha(colors.primary,0.22):colors.alpha(colors.primary,0.15)
                            border.width:1; border.color: root.updateSelectedCount===0?colors.alpha(colors.outline,0.12):colors.alpha(colors.primary,0.4)
                            enabled: root.updateSelectedCount>0
                            opacity: root.updateSelectedCount===0?0.55:1
                            Text { anchors.centerIn: parent; text: "Update selected ("+root.updateSelectedCount+")"; color: root.updateSelectedCount===0?colors.alpha(colors.outline,0.6):colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                            MouseArea { id: selMa; anchors.fill: parent; hoverEnabled:true; enabled: root.updateSelectedCount>0; onClicked: root.startUpdate(false) }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            radius: 11
                            color: root.updatesList.length===0 ? colors.alpha(colors.surfaceVariant,0.35) : allMa.containsMouse?colors.alpha(colors.primary,0.28):colors.alpha(colors.primary,0.20)
                            border.width:1; border.color: root.updatesList.length===0?colors.alpha(colors.outline,0.12):colors.alpha(colors.primary,0.5)
                            enabled: root.updatesList.length>0
                            opacity: root.updatesList.length===0?0.55:1
                            Text { anchors.centerIn: parent; text: "Update all"; color: root.updatesList.length===0?colors.alpha(colors.outline,0.6):colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                            MouseArea { id: allMa; anchors.fill: parent; hoverEnabled:true; enabled: root.updatesList.length>0; onClicked: root.startUpdate(true) }
                        }
                    }
                    Text { visible: !(root.installing && root.installMode==="update"); text: "Select packages or update all  •  pacman for repo, yay for AUR"; color: colors.alpha(colors.outline,0.45); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // footer hint
            Text {
                text: "↑↓ navigate  •  Space/Enter toggle  •  Esc closes  •  Hyprland window — drag & float"
                color: colors.alpha(colors.outline, 0.42)
                font.family: colors.fontSans; font.pixelSize: 8
                Layout.alignment: Qt.AlignHCenter
            }


            }

    }
}
