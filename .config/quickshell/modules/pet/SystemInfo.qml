import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick

// SystemInfo — real surface awareness for Hornet
// polls CPU/MEM/temp/battery + Hyprland visible window geometry (hyprctl + Hyprland.toplevels) + bar
// exposes freeSpots & surfaces: {x,y,width,surface,name} in Pet window-local coords (0,54 screen -> 0 window)
Item {
    id: root
    property int cpuPct: 0
    property int memPct: 0
    property int tempC: 0
    property int batPct: 0
    property bool batCharging: false
    property string uptime: ""
    property string clock: ""
    property int toplevelCount: 0
    property string focusedApp: ""
    property string shellInfo: "quickshell ShellRoot + Bar + 20 modules, Hyprland IPC, LocalStorage, Overlay mask"
    property var freeSpots: []
    property var surfaces: []
    property var lastClients: []

    property int _prevTotal: 0
    property int _prevIdle: 0
    Process { id: cpuProc; command: ["sh","-c","grep '^cpu ' /proc/stat"]; stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
        var f=text.trim().split(/\s+/).slice(1).map(Number); var idle=f[3]+f[4], total=f.reduce((a,b)=>a+b,0)
        if (root._prevTotal>0) root.cpuPct = Math.round(100*(1-(idle-root._prevIdle)/(total-root._prevTotal)))
        root._prevIdle=idle; root._prevTotal=total } } }
    Process { id: memProc; command: ["sh","-c","grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]; stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
        var vals={}; text.trim().split("\n").forEach(function(l){ var p=l.split(":"); if(p.length===2) vals[p[0]]=parseInt(p[1]) })
        if (vals["MemTotal"]) root.memPct = Math.round(100*(vals["MemTotal"]-vals["MemAvailable"])/vals["MemTotal"]) } } }
    Process { id: tempProc; command: ["sh","-c","cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]; stdout: StdioCollector { waitForEnd:true; onStreamFinished: { root.tempC = Math.round(parseInt(text.trim())/1000)||0 } } }
    Process { id: upProc; command: ["sh","-c","uptime -p 2>/dev/null | head -c 60; echo -n '|'; date +%H:%M"]; stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
        var p=text.trim().split("|"); root.uptime=p[0]||""; root.clock=p[1]||"" } } }
    readonly property var batDev: UPower.displayDevice
    onBatDevChanged: updateBat()
    function updateBat(){ if(batDev){ root.batPct=Math.round(batDev.percentage*100); root.batCharging=batDev.state===UPowerDeviceState.Charging } }
    Component.onCompleted: updateBat()
    Timer { interval: 4000; running:true; repeat:true; triggeredOnStart:true; onTriggered: { cpuProc.running=true; memProc.running=true; tempProc.running=true; upProc.running=true; updateBat(); refreshSpots() } }

    // hyprctl clients -> real visible window geometry (more reliable than Hyprland.toplevels for tiled)
    Process {
        id: clientsProc
        command: ["sh","-c","hyprctl clients -j 2>/dev/null | head -c 20000"]
        stdout: StdioCollector { id: clientsOut; waitForEnd:true; onStreamFinished: {
            try {
                var data = JSON.parse(text)
                var vis=[]
                for (var i=0;i<data.length;i++) {
                    var c=data[i]
                    // only mapped, not hidden, not special workspace, size >100
                    if (!c.mapped || c.hidden || c.workspace.name.indexOf("special")===0) continue
                    if (!c.at || !c.size || c.size[0]<100 || c.size[1]<100) continue
                    vis.push({at:c.at, size:c.size, cls:c.class, title:c.title, workspace:c.workspace.name})
                }
                root.lastClients = vis
                refreshSpots()
            } catch(e) { }
        }}
    }
    Timer { interval: 5500; running:true; repeat:true; triggeredOnStart:true; onTriggered: clientsProc.running = true }

    function refreshSpots() {
        var spots=[]; var surfs=[]
        var W = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.width : 1920
        var H = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.height : 1080
        var scale = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.scale : 1.2
        var lw = Math.round(W/scale)
        var lh = Math.round(H/scale)
        var petH = 128, petW = 128
        var barH = 54
        var winH = lh - barH // Pet window height 846
        surfs.push({x:0, y:0, width:lw, height:barH, surface:"bar", name:"bar"})
        spots.push({x:12, y: winH - petH - 6, name:"floor-left", surface:"floor"})
        spots.push({x:lw-140, y: winH - petH - 6, name:"floor-right", surface:"floor"})
        spots.push({x:Math.round(lw/2-64), y: winH - petH - 6, name:"floor-center", surface:"floor"})
        spots.push({x:12, y:12, name:"ceiling-left", surface:"ceiling"})
        spots.push({x:lw-140, y:12, name:"ceiling-right", surface:"ceiling"})
        spots.push({x:Math.round(lw/2-64), y:12, name:"ceiling-center", surface:"ceiling"})
        spots.push({x:Math.round(lw/2-64), y:8, name:"bar-perch", surface:"bar"})
        // Hyprland.toplevels fallback (if any)
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        // Use hyprctl clients as primary for visible windows (more accurate at/size)
        var clients = root.lastClients.length ? root.lastClients : []
        // dedupe by at+size
        var seen={}
        var allWins=[]
        for (var i=0;i<clients.length;i++) {
            var c=clients[i]
            var key=c.at[0]+","+c.at[1]+","+c.size[0]+","+c.size[1]
            if (seen[key]) continue; seen[key]=true
            allWins.push(c)
        }
        // also add any Hyprland.toplevels not in clients
        for (var j=0;j<Math.min(tls.length,8);j++) {
            var tl=tls[j]; var o=tl.lastIpcObject
            if (!o || !o.at || !o.size) continue
            var k2=o.at[0]+","+o.at[1]+","+o.size[0]+","+o.size[1]
            if (seen[k2]) continue
            allWins.push({at:o.at, size:o.size, cls:o.class||o.initialClass||"", title:o.title||""})
        }
        for (var w=0; w<Math.min(allWins.length,6); w++) {
            var win=allWins[w]
            var wx=win.at[0], wyScreen=win.at[1], ww=win.size[0], wh=win.size[1]
            var wy = wyScreen - barH // window-local y
            // window top perch — pet sits just below top bar, inside window (visible)
            var topY = wy + 12
            if (topY >= 8 && topY <= winH - petH - 8) {
                spots.push({x: Math.max(4, Math.min(Math.round(wx + ww/2 - petW/2), lw-petW-4)), y: topY, name:"win-top-"+(win.cls||"win"), surface:"window-top"})
                surfs.push({x: wx, y: wy, width: ww, height: 22, surface:"window-top", name:"win-top-"+(win.cls||"win")})
            }
            // window bottom perch (pet stands on bottom edge)
            var botY = wy + wh - petH - 4
            if (botY >= 8 && botY <= winH - petH) {
                spots.push({x: Math.max(4, Math.min(Math.round(wx + ww/2 - petW/2), lw-petW-4)), y: botY, name:"win-bottom-"+(win.cls||"win"), surface:"window"})
                surfs.push({x: wx, y: wy+wh-22, width: ww, height: 22, surface:"window-bottom", name:"win-bottom-"+(win.cls||"win")})
            }
            // left wall — pet clings inside left edge
            var lx = wx + 8
            var ly = wy + Math.round(wh/2 - petH/2)
            if (lx >= 4 && lx <= lw-petW-4 && ly >= 8 && ly <= winH-petH-8) {
                spots.push({x: lx, y: ly, name:"win-left-"+(win.cls||"win"), surface:"wall"})
                surfs.push({x: wx, y: wy, width: 18, height: wh, surface:"wall", name:"win-left-"+(win.cls||"win")})
            }
            // right wall — inside right edge
            var rx = wx + ww - petW - 8
            if (rx >= 4 && rx <= lw-petW-4 && ly >= 8 && ly <= winH-petH-8) {
                spots.push({x: rx, y: ly, name:"win-right-"+(win.cls||"win"), surface:"wall"})
                surfs.push({x: wx+ww-18, y: wy, width: 18, height: wh, surface:"wall", name:"win-right-"+(win.cls||"win")})
            }
            if (wy >= 8 && wy <= winH-40) {
                surfs.push({x: wx, y: wy, width: ww, height: 18, surface:"ceiling", name:"win-ceiling-"+(win.cls||"win")})
            }
        }
        var act = Hyprland.activeToplevel
        if (act && act.lastIpcObject && act.lastIpcObject.at) {
            var a=act.lastIpcObject
            var ax=a.at[0], ay=a.at[1]-barH, aw=a.size[0], ah=a.size[1]
            var cx = Math.round(ax + aw/2 - petW/2), cy = Math.round(ay + ah/2 - petH/2)
            if (cx>=4 && cx<=lw-petW-4 && cy>=8 && cy<=winH-petH-8) {
                spots.push({x:cx, y:cy, name:"active-center", surface:"window"})
                surfs.push({x:ax, y:ay, width:aw, height:ah, surface:"window", name:"active"})
            }
        }
        root.toplevelCount = allWins.length
        root.focusedApp = act && act.lastIpcObject ? (act.lastIpcObject.class||act.title||"") : ""
        root.freeSpots = spots
        root.surfaces = surfs
        // console.log("[SystemInfo] spots "+spots.length+" surfaces "+surfs.length+" wins "+allWins.length)
    }

    function isOnSurface(y, h) {
        for (var i=0;i<surfaces.length;i++) {
            var s=surfaces[i]
            if (Math.abs(y - s.y) < 28 && s.surface !== "wall") return true
            if (s.surface === "wall" && Math.abs(y - s.y) < 60) return true
        }
        var lh2 = Hyprland.focusedMonitor ? Math.round(Hyprland.focusedMonitor.height / Hyprland.focusedMonitor.scale - 54) : 846
        if (Math.abs(y - (lh2 - 128 -6)) < 30) return true
        if (y < 32) return true
        if (Math.abs(y - 8) < 20) return true
        return false
    }
    function nearestSurface(x, y) {
        var best=null, bestD=1e9
        for (var i=0;i<surfaces.length;i++) {
            var s=surfaces[i]
            var sx = s.x + s.width/2 - 64, sy = s.y
            var d = Math.hypot(x - sx, y - sy)
            if (d < bestD) { bestD=d; best=s }
        }
        return best
    }
}
