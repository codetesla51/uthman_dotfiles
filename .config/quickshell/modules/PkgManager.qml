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

    // tabs: 0 Search  1 Queue  2 Installed  3 Updates  4 Explore
    property int tab: 4
    // explore — curated app-store picks (all real repo/AUR packages).
    // Browse-first: rows queue through toggleSelect, install via quickInstall,
    // exactly like search rows, so no new backend paths.
    property string exploreCat: "All"
    readonly property var exploreApps: [
        // essentials
        {n:"networkmanager", d:"Network connections", s:"repo", c:"Essentials"},
        {n:"bluez", d:"Bluetooth stack", s:"repo", c:"Essentials"},
        {n:"bluez-utils", d:"Bluetooth tools", s:"repo", c:"Essentials"},
        {n:"pipewire", d:"Audio and video server", s:"repo", c:"Essentials"},
        {n:"wireplumber", d:"PipeWire session manager", s:"repo", c:"Essentials"},
        {n:"cups", d:"Printing system", s:"repo", c:"Essentials"},
        {n:"power-profiles-daemon", d:"Power profiles", s:"repo", c:"Essentials"},
        // gaming
        {n:"steam", d:"Game store and runtime", s:"repo", c:"Gaming"},
        {n:"lutris", d:"Game library manager", s:"repo", c:"Gaming"},
        {n:"heroic-games-launcher-bin", d:"Epic and GOG client", s:"AUR", c:"Gaming"},
        {n:"prismlauncher", d:"Minecraft launcher", s:"repo", c:"Gaming"},
        {n:"retroarch", d:"Retro emulator frontend", s:"repo", c:"Gaming"},
        {n:"mangohud", d:"In-game overlay stats", s:"repo", c:"Gaming"},
        {n:"gamemode", d:"Automatic performance tuning", s:"repo", c:"Gaming"},
        {n:"wine", d:"Windows compatibility layer", s:"repo", c:"Gaming"},
        {n:"protonup-qt-bin", d:"Manage Proton versions", s:"AUR", c:"Gaming"},
        // tools
        {n:"yazi", d:"Terminal file manager", s:"repo", c:"Tools"},
        {n:"btop", d:"System monitor", s:"repo", c:"Tools"},
        {n:"fzf", d:"Fuzzy finder", s:"repo", c:"Tools"},
        {n:"zoxide", d:"Smarter cd", s:"repo", c:"Tools"},
        {n:"starship", d:"Shell prompt", s:"repo", c:"Tools"},
        {n:"eza", d:"Modern ls replacement", s:"repo", c:"Tools"},
        {n:"bat", d:"Cat with highlighting", s:"repo", c:"Tools"},
        {n:"lazygit", d:"Git terminal UI", s:"repo", c:"Tools"},
        {n:"github-cli", d:"GitHub from the terminal", s:"repo", c:"Tools"},
        {n:"tmux", d:"Terminal multiplexer", s:"repo", c:"Tools"},
        // media
        {n:"mpv", d:"Minimal video player", s:"repo", c:"Media"},
        {n:"obs-studio", d:"Recording and streaming", s:"repo", c:"Media"},
        {n:"audacity", d:"Audio editor", s:"repo", c:"Media"},
        {n:"imv", d:"Keyboard image viewer", s:"repo", c:"Media"},
        {n:"celluloid", d:"GTK video frontend", s:"repo", c:"Media"},
        // browsers
        {n:"firefox", d:"Private web browser", s:"repo", c:"Browsers"},
        {n:"chromium", d:"Open-source Chrome", s:"repo", c:"Browsers"},
        {n:"zen-browser-bin", d:"Customizable Firefox fork", s:"AUR", c:"Browsers"},
        {n:"brave-bin", d:"Privacy browser", s:"AUR", c:"Browsers"},
        // creative
        {n:"gimp", d:"Image editor", s:"repo", c:"Creative"},
        {n:"inkscape", d:"Vector graphics", s:"repo", c:"Creative"},
        {n:"blender", d:"3D creation suite", s:"repo", c:"Creative"},
        {n:"krita", d:"Digital painting", s:"repo", c:"Creative"}
    ]
    readonly property var exploreCats: ["All", "Essentials", "Gaming", "Tools", "Media", "Browsers", "Creative"]
    property var exploreList: []
    function explorePkg(a) { return {name: a.n, version: "", desc: a.d, source: a.s === "AUR" ? "AUR" : "official", repo: a.s === "AUR" ? "aur" : "repo"} }
    function shuffleExplore() {
        var pool = exploreApps.filter(function(a){
            return exploreCat === "All" || a.c === exploreCat
        })
        for (var i = pool.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1))
            var t = pool[i]; pool[i] = pool[j]; pool[j] = t
        }
        exploreList = pool
    }
    function isInstalledName(n) {
        for (var i = 0; i < installedAll.length; i++) if (installedAll[i].name === n) return true
        return false
    }
    property string query: ""
    property var searchResults: []
    property int srcFilter: 0 // 0 all 1 repo 2 aur (prototype source chips)
    readonly property var searchFiltered: {
        if (srcFilter === 1) return searchResults.filter(function(p){ return p.source !== "AUR" })
        if (srcFilter === 2) return searchResults.filter(function(p){ return p.source === "AUR" })
        return searchResults
    }
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
    property bool installFailed: false
    property bool installDone: false
    property int installExit: 0
    property string installPhase: ""
    property string installSummary: ""
    property string installError: ""
    property int transCur: 0
    property int transTot: 0
    property real dlFrac: 0
    property double installT0: 0
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
    visible: root.open || closeAnim.running

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

    onOpenChanged: if (open) { refreshInstalled(); refreshUpdates(); searchNav=0; instNav=0; updNav=0; allowHover=false; shuffleExplore(); if(root.tab===0) Qt.callLater(function(){ searchField.forceActiveFocus() }); openAnim.restart() } else closeAnim.restart()
    onTabChanged: { searchNav=0; instNav=0; updNav=0; allowHover=false; if(open) { if(tab===0) Qt.callLater(function(){ searchField.forceActiveFocus() }); else if(tab===2) Qt.callLater(function(){ instField.forceActiveFocus() }); else card.forceActiveFocus() } }
    onSearchResultsChanged: searchNav=0
    onSrcFilterChanged: searchNav=0
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
        // fetch download sizes for visible results (batched, single call each)
        if(searchResults.length>0) fetchSizes(searchResults.slice(0,30))
    }
    function fetchSizes(pkgs){
        if(!pkgs || pkgs.length===0) return
        var offNames=[], aurNames=[]
        for(var i=0;i<pkgs.length;i++){
            var n=pkgs[i].name
            if(!n || sizeMap.hasOwnProperty(n)) continue
            if(!/^[A-Za-z0-9@._+-]+$/.test(n)) continue
            if(pkgs[i].source==="AUR") aurNames.push(n)
            else offNames.push(n)
        }
        if(offNames.length>0){
            sizeProcOff.command=["sh","-c","$HOME/.config/quickshell/scripts/pkg-sizes.sh off "+offNames.join(" ")]
            sizeProcOff.running=true
        }
        if(aurNames.length>0){
            sizeProcAur.command=["sh","-c","$HOME/.config/quickshell/scripts/pkg-sizes.sh aur "+aurNames.join(" ")]
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
    function resetInstallState(mode) {
        installMode=mode
        installLog=""; installPct=0.05; installing=true
        installFailed=false; installDone=false; installExit=0
        installPhase="Starting"; installSummary=""; installError=""
        transCur=0; transTot=0; dlFrac=0
        installT0=Date.now()
    }
    function quickInstall(pkg) {
        if(!pkg || installing) return
        if(!isSelected(pkg.name)) toggleSelect(pkg)
        tab=1
        startInstall()
    }
    function startInstall() {
        if(needPass("install")) return
        var cmd=buildInstallCmd()
        if(!cmd) return
        resetInstallState("install")
        installLog=":: Installing "+selectedList.length+" package(s)\n"
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }
    function startRemove() {
        if(needPass("remove")) return
        var cmd=buildRemoveCmd()
        if(!cmd) return
        resetInstallState("remove")
        installLog=":: Removing "+uninstallCount+" package(s)\n"
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }
    function startUpdate(all) {
        if(needPass(all ? "updateAll" : "update")) return
        var cmd=buildUpdateCmd(all)
        if(!cmd) return
        resetInstallState("update")
        installLog=":: Updating\n"
        installProc.command=["sh","-c", cmd]
        installProc.running=true
    }
    function noteInstallLine(line) {
        if(!line) return
        installLog += line + "\n"
        if(installLog.length>12000) installLog = installLog.slice(-12000)
        var low=line.toLowerCase()
        // error collection (shown on failure, does not stop the run)
        if(low.indexOf("error:")!==-1 || low.indexOf("failed")!==-1 || low.indexOf("conflicting files")!==-1 || low.indexOf("could not satisfy")!==-1 || low.indexOf("invalid or corrupted")!==-1 || low.indexOf("permission denied")!==-1 || low.indexOf("incorrect password")!==-1 || low.indexOf("sorry, try again")!==-1 || low.indexOf("target not found")!==-1 || low.indexOf("authentication failure")!==-1) {
            if(installError==="") installError=line.trim().slice(0,220)
        }
        // phase detection — keeps label truthful during long yay builds
        if(line.indexOf("___AUR_START___")!==-1) { installPhase="AUR packages"; transCur=0; transTot=0; dlFrac=0 }
        else if(low.indexOf("making package")!==-1 || low.indexOf("retrieving sources")!==-1 || low.indexOf("building")!==-1 || line.indexOf("==>")!==-1) {
            installPhase="Building AUR"
            if(installPct<0.9) installPct=Math.min(0.9, installPct+0.01)
        }
        else if(low.indexOf("resolving dependencies")!==-1) { installPhase="Resolving"; if(installPct<0.08) installPct=0.08 }
        else if(low.indexOf("looking for conflicting")!==-1) { installPhase="Checking conflicts"; if(installPct<0.12) installPct=0.12 }
        else if(low.indexOf("checking keyring")!==-1 || low.indexOf("checking package integrity")!==-1 || low.indexOf("checking for file conflicts")!==-1 || low.indexOf("checking available disk")!==-1 || low.indexOf("loading package")!==-1) { installPhase="Checking"; if(installPct<0.15) installPct=0.15 }
        else if(low.indexOf("total download size")!==-1) { installPhase="Downloading" }
        // transaction progress ( 1/5 )
        var m=line.match(/\(\s*(\d+)\s*\/\s*(\d+)\s*\)/)
        if(m) {
            var cur=parseInt(m[1]); var tot=parseInt(m[2])
            if(tot>0 && cur>0) {
                transCur=cur; transTot=tot; dlFrac=0
                installPhase="Installing "+cur+"/"+tot
                var cand=0.2+0.75*((cur-1)/tot)
                if(cand>installPct) installPct=cand
            }
            return
        }
        var pm=line.match(/(\d{1,3})(?:\.\d+)?\s*%/)
        if(pm) {
            var dl=parseInt(pm[1])/100
            if(dl<0) dl=0
            if(dl>1) dl=1
            installPhase = transTot>0 ? ("Installing "+transCur+"/"+transTot) : "Downloading"
            if(transTot>0 && transCur>0) {
                if(dl>dlFrac) dlFrac=dl
                var c2=0.2+0.75*((transCur-1+dlFrac)/transTot)
                if(c2>installPct) installPct=c2
            } else {
                // pre-transaction downloads: many files each 0-100%, so nudge forward to stay alive
                var absP=0.08+dl*0.15
                if(absP>installPct) installPct=absP
                else if(installPct<0.35) installPct=Math.min(0.35, installPct+0.008)
            }
        }
    }
    function finishInstall(code) {
        installExit=code
        installDone=true
        var secs=Math.max(1, Math.round((Date.now()-installT0)/1000))
        if(code===0 && installError==="") {
            installFailed=false
            installPct=1.0
            installPhase="Done"
            installSummary="Completed in "+secs+"s"
            installLog += "\n— done ("+secs+"s) —\n"
        } else {
            installFailed=true
            installPhase="Failed"
            if(lowIsAuth(installLog)) {
                installSummary="sudo auth failed (exit "+code+") — retry, password cleared"
                sudoPass=""
            } else if(installError!=="") {
                installSummary="Failed (exit "+code+") — "+installError
            } else {
                installSummary="Failed (exit "+code+") — see log"
            }
            installLog += "\n— failed (exit "+code+", "+secs+"s) —\n"
        }
        refreshTimer.restart()
    }
    function lowIsAuth(log) {
        var l=log.toLowerCase()
        return l.indexOf("incorrect password")!==-1 || l.indexOf("sorry, try again")!==-1 || l.indexOf("no password was provided")!==-1 || l.indexOf("authentication failure")!==-1
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
            onRead: function(line){ root.noteInstallLine(line) }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: function(line){ root.noteInstallLine(line) }
        }
        onExited: function(code){ if(root.installing) root.finishInstall(code) }
    }
    Timer { id: refreshTimer; interval: 1200; onTriggered: { root.refreshInstalled(); root.refreshUpdates() } }
    Timer { id: searchDebounce; interval: 380; onTriggered: if(root.query.trim().length>=1) searchProc.running=true; else {searchResults=[]; searching=false} }

    // card
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: {
            if(root.installing) return
            root.open=false
        }
        Keys.onPressed: function(e){
            if(root.installing) return
            if(e.key===Qt.Key_Slash && root.tab===0){ searchField.forceActiveFocus(); e.accepted=true; return }
            if(e.key===Qt.Key_Tab && root.tab===0){ searchField.forceActiveFocus(); e.accepted=true; return }
            if(e.key>=Qt.Key_1 && e.key<=Qt.Key_5){ root.tab=e.key-Qt.Key_1; e.accepted=true; return }
            if(root.tab===0 && root.searchFiltered.length>0){
                if(e.key===Qt.Key_Down){ root.searchNav=Math.min(root.searchNav+1, root.searchFiltered.length-1); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Up){ root.searchNav=Math.max(root.searchNav-1,0); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true }
                else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter){ var p=root.searchFiltered[root.searchNav]; if(p) root.toggleSelect(p); e.accepted=true }
                else if(e.key===Qt.Key_Space){ var q=root.searchFiltered[root.searchNav]; if(q) root.toggleSelect(q); e.accepted=true }
                else if(e.key===Qt.Key_D){ var d=root.searchFiltered[root.searchNav]; if(d) root.quickInstall(d); e.accepted=true }
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

        component Kbd: Rectangle {
            id: kbd
            property string t: ""
            implicitWidth: kbdTxt.implicitWidth + 14
            implicitHeight: 20
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
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // header — logo tile + title + status + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    width: 34; height: 34; radius: 12
                    color: colors.primary
                    Text { anchors.centerIn: parent; text: "󰏖"; color: colors.background; font.family: colors.fontSans; font.pixelSize: 18 }
                }
                Text { text: "Packages"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 20; font.weight: Font.Bold }
                Item { Layout.fillWidth: true }
                Text { text: root.installedAll.length + " installed · " + root.updatesList.length + " updates"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11 }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width:1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // tabs — 4 pills with counts, accent underline on the active one
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: [
                        {l:"Search", c: root.searchFiltered.length},
                        {l:"Queue", c: root.selectedList.length},
                        {l:"Installed", c: root.installedAll.length},
                        {l:"Updates", c: root.updatesList.length},
                        {l:"Explore", c: root.exploreApps.length}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 40
                        radius: 13
                        color: root.tab===index ? colors.alpha(colors.primary, 0.16) : tabMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : colors.alpha(colors.surface, 0.55)
                        border.width:1
                        border.color: root.tab===index ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.14)
                        scale: tabMa.containsMouse && !root.installing ? 1.02 : 1
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
                                color: root.tab===index ? colors.primary : colors.alpha(colors.surfaceVariant, 0.5)
                                Text { id: cnt; anchors.centerIn: parent; text: modelData.c; color: root.tab===index ? colors.background : colors.alpha(colors.outline,0.9); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                            }
                        }
                        MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled:true; onClicked: if(!root.installing) root.tab=index }
                    }
                }
            }

            // job view swaps over the tab body while a transaction runs
            ColumnLayout {
                id: jobBox
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                visible: root.installing
                Canvas {
                    id: pacCanvas
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    property real mouth: 0
                    onVisibleChanged: if (visible) requestPaint()
                    Connections { target: root; function onInstallPctChanged() { pacCanvas.requestPaint() } }
                    Timer { interval: 120; running: root.installing && !root.installDone; repeat: true
                        onTriggered: { pacCanvas.mouth += 0.55; pacCanvas.requestPaint() } }
                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width, h = height, cy = h / 2
                        ctx.clearRect(0, 0, w, h)
                        var n = Math.max(1, Math.floor(w / 20))
                        var eaten = Math.floor(Math.min(1, Math.max(0, root.installPct)) * n)
                        ctx.fillStyle = String(colors.outline)
                        for (var i = eaten; i < n; i++) {
                            ctx.beginPath()
                            ctx.arc(10 + i * 20, cy, 2, 0, 2 * Math.PI)
                            ctx.fill()
                        }
                        var px = Math.min(w - 12, Math.max(12, root.installPct * w))
                        var half = root.installDone ? 0 : 0.15 + 0.35 * Math.abs(Math.sin(pacCanvas.mouth))
                        ctx.fillStyle = String(root.installFailed ? colors.error : colors.primary)
                        ctx.beginPath()
                        ctx.moveTo(px, cy)
                        ctx.arc(px, cy, 10, half, 2 * Math.PI - half)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text { text: root.installDone ? (root.installFailed ? "Failed" : "Done") : (root.installPhase!=="" ? root.installPhase : "Working…"); color: root.installFailed ? colors.error : colors.primary; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { visible: root.transTot>0; text: root.transCur + "/" + root.transTot; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 11 }
                    Text { text: Math.round(root.installPct*100)+"%"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.Bold }
                }
                Text { visible: root.installDone && root.installSummary!==""; text: root.installSummary; color: root.installFailed ? colors.error : colors.alpha(colors.outline, 0.75); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                            font.pixelSize: 10
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: root.installing && !root.installDone
                        width: 90; height: 34; radius: 10
                        color: cancelMa.containsMouse ? colors.alpha(colors.error,0.18) : colors.alpha(colors.surface,0.6); border.width:1; border.color: colors.alpha(colors.error,0.4)
                        Text { anchors.centerIn: parent; text: "Cancel"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled:true; onClicked: installProc.running=false }
                    }
                    Rectangle {
                        visible: root.installDone
                        width: 130; height: 34; radius: 10
                        color: colors.alpha(colors.surface,0.6); border.width:1; border.color: colors.alpha(colors.outline,0.15)
                        Text { anchors.centerIn: parent; text: root.installFailed ? "Dismiss" : "Done — Close"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; onClicked: { if(!root.installFailed && root.installMode==="install") root.clearQueue(); root.installing=false; root.installDone=false; root.installFailed=false; root.installPct=0; root.installLog=""; root.installSummary=""; root.installPhase="" } }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.installing
                currentIndex: root.tab

                // TAB 0: SEARCH
                ColumnLayout { spacing: 10
                    Rectangle {
                        Layout.fillWidth: true; height: 44; radius: 14
                        color: colors.alpha(colors.surface, 0.75)
                        border.width:1
                        border.color: searchField.activeFocus ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.15)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7; anchors.rightMargin: 10
                            spacing: 10
                            Rectangle { width: 30; height: 30; radius: 9; color: colors.primary
                                Text { anchors.centerIn: parent; text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 14 } }
                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                placeholderText: "Search pacman + AUR…"
                                placeholderTextColor: colors.alpha(colors.outline, 0.45)
                                color: colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 13
                                background: null
                                selectByMouse: true
                                onTextChanged: { root.query=text; root.searchNav=0; searchDebounce.restart() }
                                Keys.onPressed: function(e){
                                    if(e.key===Qt.Key_Escape){ card.forceActiveFocus(); e.accepted=true }
                                    else if(e.key===Qt.Key_Down){ if(root.searchFiltered.length>0){ root.searchNav=Math.min(root.searchNav+1, root.searchFiltered.length-1); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true } }
                                    else if(e.key===Qt.Key_Up){ if(root.searchFiltered.length>0){ root.searchNav=Math.max(root.searchNav-1,0); searchList.positionViewAtIndex(root.searchNav, ListView.Contain); e.accepted=true } }
                                    else if(e.key===Qt.Key_Return || e.key===Qt.Key_Enter || e.key===Qt.Key_Space){ var p=root.searchFiltered[root.searchNav]; if(p){ root.toggleSelect(p)} else if(root.searchFiltered.length>0) root.toggleSelect(root.searchFiltered[0]); e.accepted=true }
                                    else if(e.key===Qt.Key_D && e.modifiers===Qt.ControlModifier){ var dd=root.searchFiltered[root.searchNav]; if(dd) root.quickInstall(dd); else if(root.searchFiltered.length>0) root.quickInstall(root.searchFiltered[0]); e.accepted=true }
                                }
                            }
                            Text {
                                visible: root.searching
                                text: ""
                                color: colors.primary
                                font.family: colors.fontSans; font.pixelSize: 13
                                RotationAnimation on rotation { running: root.searching; loops: Animation.Infinite; from:0; to:360; duration: 700 }
                            }
                            Text {
                                visible: !root.searching && searchField.text!==""
                                text: "󰅖"
                                color: clrMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.6)
                                font.family: colors.fontSans; font.pixelSize: 14
                                MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled:true; onClicked: {searchField.text=""; root.query=""; root.searchResults=[]} }
                            }
                            Kbd { t: "/" }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Source"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11 }
                        Repeater { model: ["All", "Repo", "AUR"]
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: chLbl.implicitWidth+20; height: 24; radius: 8
                                color: root.srcFilter===index ? colors.primary : "transparent"
                                border.width:1; border.color: root.srcFilter===index ? colors.primary : colors.alpha(colors.outline,0.2)
                                Text { id: chLbl; anchors.centerIn: parent; text: modelData; color: root.srcFilter===index ? colors.background : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; onClicked: { root.srcFilter=index; root.searchNav=0 } }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: root.searchFiltered.length + " results"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    }
                    ListView {
                        id: searchList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.searchFiltered
                        currentIndex: root.searchNav
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: searchList.width
                            height: 60
                            radius: 12
                            color: index===root.searchNav ? colors.alpha(colors.primary, 0.14) : (modelData.name && root.isSelected(modelData.name)) ? colors.alpha(colors.primary, 0.08) : hovS.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                            border.width: 1
                            border.color: index===root.searchNav ? colors.alpha(colors.primary, 0.45) : (modelData.name && root.isSelected(modelData.name)) ? colors.alpha(colors.primary, 0.3) : "transparent"
                            MouseArea { id: hovS; anchors.fill: parent; hoverEnabled: true; onClicked: { root.searchNav=index; root.toggleSelect(modelData) } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 10
                                spacing: 12
                                Rectangle {
                                    width: 20; height: 20; radius: 6
                                    Layout.alignment: Qt.AlignVCenter
                                    color: (modelData.name && root.isSelected(modelData.name)) ? colors.primary : "transparent"
                                    border.width: 1.5
                                    border.color: (modelData.name && root.isSelected(modelData.name)) ? colors.primary : colors.alpha(colors.outline, 0.5)
                                    Text { anchors.centerIn: parent; visible: modelData.name && root.isSelected(modelData.name); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    RowLayout { spacing: 6
                                        Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                                        Text { text: modelData.version; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 11 }
                                        Rectangle { visible: modelData.source==="AUR"; height: 16; width: aurT.implicitWidth+10; radius: 6; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.secondary,0.5)
                                            Text { id: aurT; anchors.centerIn: parent; text: "AUR"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 9 } }
                                        Rectangle { visible: modelData.source!=="AUR"; height: 16; width: repoT.implicitWidth+10; radius: 6; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                                            Text { id: repoT; anchors.centerIn: parent; text: modelData.repo; color: colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize: 9 } }
                                        Rectangle { visible: modelData.installed; height: 16; width: instT.implicitWidth+10; radius: 6; color: colors.alpha(colors.primary,0.15); border.width: 1; border.color: colors.alpha(colors.primary,0.4)
                                            Text { id: instT; anchors.centerIn: parent; text: "installed"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold } }
                                    }
                                    Text { text: modelData.desc || ""; color: colors.alpha(colors.outline,0.75); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Text { visible: root.sizeMap[modelData.name] !== undefined; text: "󰄠 " + (root.sizeMap[modelData.name] || ""); color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { visible: hovS.containsMouse; width: 26; height: 26; radius: 8; Layout.alignment: Qt.AlignVCenter
                                    color: dMa.containsMouse ? colors.alpha(colors.primary,0.25) : "transparent"; border.width: 1; border.color: colors.alpha(colors.primary,0.4)
                                    Text { anchors.centerIn: parent; text: "D"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.ExtraBold }
                                    MouseArea { id: dMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.quickInstall(modelData) } }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: root.selectedList.length + " queued" + (root.totalQueuedSizeStr ? " · " + root.totalQueuedSizeStr : ""); color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { visible: root.selectedList.length>0; width: 120; height: 42; radius: 12; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                            Text { anchors.centerIn: parent; text: "Review queue"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; onClicked: root.tab=1 } }
                    }
                }

                // TAB 1: QUEUE
                ColumnLayout { spacing: 10
                    ListView {
                        id: queueList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.selectedList
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: queueList.width
                            height: 54
                            radius: 12
                            color: hovQ.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                            border.width: 1; border.color: "transparent"
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 12
                                Rectangle { width: 20; height: 20; radius: 6; Layout.alignment: Qt.AlignVCenter; color: colors.primary; border.width: 1; border.color: colors.primary
                                    Text { anchors.centerIn: parent; text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold } }
                                ColumnLayout { Layout.fillWidth: true; spacing: 2
                                    RowLayout { spacing: 6
                                        Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                                        Text { text: modelData.version; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 11 } }
                                    Text { text: modelData.desc || ""; color: colors.alpha(colors.outline,0.75); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true } }
                                Text { visible: root.sizeMap[modelData.name] !== undefined; text: "󰄠 " + (root.sizeMap[modelData.name] || ""); color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter }
                            }
                            MouseArea { id: hovQ; anchors.fill: parent; hoverEnabled: true; onClicked: root.removeSelected(modelData.name) }
                        }
                    }
                    Text { visible: root.selectedList.length===0; text: "Nothing queued. Select packages in Search."; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: root.selectedList.length + " packages" + (root.totalQueuedSizeStr ? " · " + root.totalQueuedSizeStr + " download" : ""); color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { visible: root.selectedList.length>0; width: 90; height: 42; radius: 12; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                            Text { anchors.centerIn: parent; text: "Clear"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; onClicked: root.clearQueue() } }
                        Rectangle { width: 150; height: 42; radius: 12; enabled: root.selectedList.length>0; opacity: root.selectedList.length>0?1:0.45
                            color: root.selectedList.length>0 ? colors.primary : colors.alpha(colors.surfaceVariant,0.35)
                            Text { anchors.centerIn: parent; text: "󰄠 Install (" + root.selectedList.length + ")"; color: root.selectedList.length>0 ? colors.background : colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { anchors.fill: parent; enabled: root.selectedList.length>0; onClicked: root.startInstall() } }
                    }
                }

                // TAB 2: INSTALLED
                ColumnLayout { spacing: 10
                    Rectangle {
                        Layout.fillWidth: true; height: 44; radius: 14
                        color: colors.alpha(colors.surface, 0.75)
                        border.width:1
                        border.color: instField.activeFocus ? colors.alpha(colors.primary, 0.45) : colors.alpha(colors.outline, 0.15)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout { anchors.fill: parent; anchors.leftMargin: 7; anchors.rightMargin: 10; spacing: 10
                            Rectangle { width: 30; height: 30; radius: 9; color: colors.primary
                                Text { anchors.centerIn: parent; text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 14 } }
                            TextField {
                                id: instField
                                Layout.fillWidth: true
                                placeholderText: "Filter installed…"
                                placeholderTextColor: colors.alpha(colors.outline, 0.45)
                                color: colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 13
                                background: null
                                selectByMouse: true
                                onTextChanged: root.instQuery=text
                                Keys.onPressed: function(e){ if(e.key===Qt.Key_Escape){ card.forceActiveFocus(); e.accepted=true } }
                            }
                            Text { visible: instField.text!==""; text: "󰅖"; color: instClrMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 14
                                MouseArea { id: instClrMa; anchors.fill: parent; hoverEnabled:true; onClicked: instField.text="" } }
                        }
                    }
                    RowLayout { Layout.fillWidth: true; spacing: 6
                        Text { text: "Show"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11 }
                        Repeater { model: ["All", "Native", "Foreign"]
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: chLbl2.implicitWidth+20; height: 24; radius: 8
                                color: root.instFilter===index ? colors.primary : "transparent"
                                border.width:1; border.color: root.instFilter===index ? colors.primary : colors.alpha(colors.outline,0.2)
                                Text { id: chLbl2; anchors.centerIn: parent; text: modelData; color: root.instFilter===index ? colors.background : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; onClicked: root.instFilter=index }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: root.installedFiltered.length + " shown"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    }
                    ListView {
                        id: instList
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
                            height: 50
                            radius: 12
                            color: index===root.instNav ? colors.alpha(colors.primary, 0.14) : (modelData.name && root.isUninstallSelected(modelData.name)) ? colors.alpha(colors.error, 0.10) : hovI.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                            border.width: 1
                            border.color: index===root.instNav ? colors.alpha(colors.primary, 0.45) : (modelData.name && root.isUninstallSelected(modelData.name)) ? colors.alpha(colors.error, 0.4) : "transparent"
                            Rectangle { id: iCb; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                color: (modelData.name && root.isUninstallSelected(modelData.name)) ? colors.error : "transparent"
                                border.width: 1.5
                                border.color: (modelData.name && root.isUninstallSelected(modelData.name)) ? colors.error : colors.alpha(colors.outline, 0.5)
                                Text { anchors.centerIn: parent; visible: modelData.name && root.isUninstallSelected(modelData.name); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold } }
                            Text { anchors.left: iCb.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: 230
                                text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold; elide: Text.ElideRight }
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 282; width: 150
                                text: modelData.version; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 440
                                text: modelData.source==="official" ? "Native package" : "Foreign package"; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 11 }
                            Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                height: 16; width: repoT2.implicitWidth+10; radius: 6; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                                Text { id: repoT2; anchors.centerIn: parent; text: modelData.repo; color: colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize: 9 } }
                            MouseArea { id: hovI; anchors.fill: parent; hoverEnabled: true; onClicked: { root.instNav=index; root.toggleUninstall(modelData) } }
                        }
                    }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: root.uninstallCount + " selected · pacman -Rns"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { width: 150; height: 42; radius: 12; enabled: root.uninstallCount>0; opacity: root.uninstallCount>0?1:0.45
                            color: root.uninstallCount>0 ? colors.error : colors.alpha(colors.surfaceVariant,0.35)
                            Text { anchors.centerIn: parent; text: "󰅖 Remove (" + root.uninstallCount + ")"; color: root.uninstallCount>0 ? colors.background : colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { anchors.fill: parent; enabled: root.uninstallCount>0; onClicked: root.startRemove() } }
                    }
                }

                // TAB 3: UPDATES
                ColumnLayout { spacing: 10
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { visible: root.lastChecked!==""; text: "Checked " + root.lastChecked; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Item { visible: root.lastChecked===""; Layout.fillWidth: true }
                        Rectangle { width: 110; height: 34; radius: 10; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                            Text { anchors.centerIn: parent; text: "Refresh"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; onClicked: root.refreshUpdates() } }
                    }
                    ListView {
                        id: updList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.updatesList
                        currentIndex: root.updNav
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: updList.width
                            height: 54
                            radius: 12
                            color: index===root.updNav ? colors.alpha(colors.primary, 0.14) : (modelData.name && root.isUpdateSelected(modelData.name)) ? colors.alpha(colors.primary, 0.08) : hovU.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                            border.width: 1
                            border.color: index===root.updNav ? colors.alpha(colors.primary, 0.45) : (modelData.name && root.isUpdateSelected(modelData.name)) ? colors.alpha(colors.primary, 0.3) : "transparent"
                            Rectangle { id: uCb; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                color: (modelData.name && root.isUpdateSelected(modelData.name)) ? colors.primary : "transparent"
                                border.width: 1.5
                                border.color: (modelData.name && root.isUpdateSelected(modelData.name)) ? colors.primary : colors.alpha(colors.outline, 0.5)
                                Text { anchors.centerIn: parent; visible: modelData.name && root.isUpdateSelected(modelData.name); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold } }
                            Text { anchors.left: uCb.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; width: 220
                                text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold; elide: Text.ElideRight }
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 272; width: 260
                                text: modelData.oldVer + "  →  " + modelData.newVer; color: colors.alpha(colors.outline,0.75); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
                            Rectangle { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                height: 16; width: repoT3.implicitWidth+10; radius: 6; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.outline,0.25)
                                Text { id: repoT3; anchors.centerIn: parent; text: modelData.repo; color: colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize: 9 } }
                            MouseArea { id: hovU; anchors.fill: parent; hoverEnabled: true; onClicked: { root.updNav=index; root.toggleUpdate(modelData) } }
                        }
                    }
                    Text { visible: root.updatesList.length===0; text: "Everything is up to date."; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    RowLayout { Layout.fillWidth: true; spacing: 8
                        Text { text: root.updatesList.length + " updates"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                        Rectangle { width: 170; height: 42; radius: 12; enabled: root.updateSelectedCount>0; opacity: root.updateSelectedCount>0?1:0.45
                            color: "transparent"; border.width: 1; border.color: root.updateSelectedCount>0 ? colors.alpha(colors.primary,0.4) : colors.alpha(colors.outline,0.12)
                            Text { anchors.centerIn: parent; text: "Update selected (" + root.updateSelectedCount + ")"; color: root.updateSelectedCount>0 ? colors.primary : colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; enabled: root.updateSelectedCount>0; onClicked: root.startUpdate(false) } }
                        Rectangle { width: 130; height: 42; radius: 12; enabled: root.updatesList.length>0; opacity: root.updatesList.length>0?1:0.45
                            color: root.updatesList.length>0 ? colors.primary : colors.alpha(colors.surfaceVariant,0.35)
                            Text { anchors.centerIn: parent; text: "Update all"; color: root.updatesList.length>0 ? colors.background : colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { anchors.fill: parent; enabled: root.updatesList.length>0; onClicked: root.startUpdate(true) } }
                    }
                }

                // TAB 4: EXPLORE — curated app-store picks, shuffled per open
                ColumnLayout { spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater { model: root.exploreCats
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                width: chLbl3.implicitWidth+20; height: 24; radius: 8
                                color: root.exploreCat===modelData ? colors.primary : "transparent"
                                border.width:1; border.color: root.exploreCat===modelData ? colors.primary : colors.alpha(colors.outline,0.2)
                                Text { id: chLbl3; anchors.centerIn: parent; text: modelData; color: root.exploreCat===modelData ? colors.background : colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; onClicked: { root.exploreCat=modelData; root.shuffleExplore() } }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text { text: root.exploreList.length + " picks"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                    }
                    ListView {
                        id: expListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.exploreList
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: expListView.width
                            height: 56
                            radius: 12
                            color: (modelData.n && root.isSelected(modelData.n)) ? colors.alpha(colors.primary, 0.08) : hovE.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                            border.width: 1
                            border.color: (modelData.n && root.isSelected(modelData.n)) ? colors.alpha(colors.primary, 0.3) : "transparent"
                            MouseArea { id: hovE; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleSelect(root.explorePkg(modelData)) }
                            Rectangle { id: eCb; anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                color: (modelData.n && root.isSelected(modelData.n)) ? colors.primary : "transparent"
                                border.width: 1.5
                                border.color: (modelData.n && root.isSelected(modelData.n)) ? colors.primary : colors.alpha(colors.outline, 0.5)
                                Text { anchors.centerIn: parent; visible: modelData.n && root.isSelected(modelData.n); text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.Bold } }
                            ColumnLayout { anchors.left: eCb.right; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                RowLayout { spacing: 6
                                    Text { text: modelData.n; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                                    Rectangle { height: 16; width: eTag.implicitWidth+10; radius: 6; color: "transparent"; border.width: 1
                                        border.color: modelData.s==="AUR" ? colors.alpha(colors.secondary,0.5) : colors.alpha(colors.outline,0.25)
                                        Text { id: eTag; anchors.centerIn: parent; text: modelData.s; color: modelData.s==="AUR" ? colors.secondary : colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize: 9 } }
                                    Rectangle { visible: root.isInstalledName(modelData.n); height: 16; width: eInst.implicitWidth+10; radius: 6; color: colors.alpha(colors.primary,0.15); border.width: 1; border.color: colors.alpha(colors.primary,0.4)
                                        Text { id: eInst; anchors.centerIn: parent; text: "installed"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold } }
                                }
                                Text { text: modelData.d; color: colors.alpha(colors.outline,0.75); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Rectangle { visible: hovE.containsMouse && !root.isInstalledName(modelData.n); anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26; radius: 8; color: "transparent"; border.width: 1; border.color: colors.alpha(colors.primary,0.4)
                                Text { anchors.centerIn: parent; text: "D"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.ExtraBold }
                                MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.quickInstall(root.explorePkg(modelData)) } }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Pick to queue · D installs now · reshuffles every open"; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    }
                }
            }

            // footer key hints
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Item { Layout.fillWidth: true }
                Kbd { t: "/" } Text { text: "search"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Kbd { t: "↑↓" } Text { text: "move"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Kbd { t: "Space" } Text { text: "select"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Kbd { t: "D" } Text { text: "install"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Kbd { t: "1–5" } Text { text: "tabs"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Kbd { t: "Esc" } Text { text: "close"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
            }
        }

    }
}
