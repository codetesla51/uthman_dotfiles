import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick

// SystemInfo — makes Hornet actually aware of what's happening
// polls CPU/MEM/temp/battery/uptime + Hyprland workspaces/toplevels + quickshell arch
// exposes freeSpots: coordinates where pet can legally stay (floor/ceiling/window/bar)
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
    property string shellInfo: "quickshell ShellRoot + Bar + 20 modules, Hyprland IPC, LocalStorage"
    property var freeSpots: []

    // CPU
    property int _prevTotal: 0
    property int _prevIdle: 0
    Process {
        id: cpuProc
        command: ["sh","-c","grep '^cpu ' /proc/stat"]
        stdout: StdioCollector { id: cpuOut; waitForEnd:true; onStreamFinished: {
            var f=text.trim().split(/\s+/).slice(1).map(Number)
            var idle=f[3]+f[4], total=f.reduce((a,b)=>a+b,0)
            if (root._prevTotal>0) root.cpuPct = Math.round(100*(1-(idle-root._prevIdle)/(total-root._prevTotal)))
            root._prevIdle=idle; root._prevTotal=total
        }}
    }
    // MEM
    Process {
        id: memProc
        command: ["sh","-c","grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        stdout: StdioCollector { id: memOut; waitForEnd:true; onStreamFinished: {
            var vals={}; text.trim().split("\n").forEach(function(l){ var p=l.split(":"); if(p.length===2) vals[p[0]]=parseInt(p[1]) })
            if (vals["MemTotal"]) root.memPct = Math.round(100*(vals["MemTotal"]-vals["MemAvailable"])/vals["MemTotal"])
        }}
    }
    // temp
    Process {
        id: tempProc
        command: ["sh","-c","cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]
        stdout: StdioCollector { waitForEnd:true; onStreamFinished: { root.tempC = Math.round(parseInt(text.trim())/1000) || 0 } }
    }
    // uptime + clock
    Process {
        id: upProc
        command: ["sh","-c","uptime -p 2>/dev/null | head -c 60; echo -n '|'; date +%H:%M"]
        stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
            var p=text.trim().split("|")
            root.uptime=p[0]||""; root.clock=p[1]||""
        }}
    }
    // battery via UPower
    readonly property var batDev: UPower.displayDevice
    onBatDevChanged: updateBat()
    function updateBat(){ if(batDev){ root.batPct=Math.round(batDev.percentage*100); root.batCharging=batDev.state===UPowerDeviceState.Charging } }
    Component.onCompleted: updateBat()

    Timer { interval: 4000; running:true; repeat:true; triggeredOnStart:true; onTriggered: { cpuProc.running=true; memProc.running=true; tempProc.running=true; upProc.running=true; updateBat(); refreshSpots() } }

    // Hyprland workspaces/toplevels -> freeSpots
    function refreshSpots() {
        var spots=[]
        var W = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.width : 1600
        var H = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.height : 900
        // logical size: physical / scale
        var scale = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.scale : 1.2
        var lw = Math.round(W/scale)
        var lh = Math.round(H/scale)
        // floor + ceiling are always free
        spots.push({x:12, y: lh - 128 - 6, name:"floor-left", surface:"floor"})
        spots.push({x:lw-140, y: lh - 128 - 6, name:"floor-right", surface:"floor"})
        spots.push({x:Math.round(lw/2-64), y: lh - 128 - 6, name:"floor-center", surface:"floor"})
        spots.push({x:12, y:12, name:"ceiling-left", surface:"ceiling"})
        spots.push({x:lw-140, y:12, name:"ceiling-right", surface:"ceiling"})
        spots.push({x:Math.round(lw/2-64), y:12, name:"ceiling-center", surface:"ceiling"})
        // bar top (just below bar, y=60)
        spots.push({x:Math.round(lw/2-64), y:60, name:"bar-perch", surface:"bar"})
        // windows as perches: top edge of each toplevel
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        for (var i=0;i<Math.min(tls.length,6);i++) {
            var tl=tls[i]; var o=tl.lastIpcObject
            if (!o || !o.at || !o.size) continue
            var at=o.at, sz=o.size
            // window top perch: pet sits on top border
            var wx = Math.round(at[0] + sz[0]/2 - 64) // centered
            var wy = Math.round(at[1] - 54 - 64) // screen y -> window-local (bar 54)
            if (wy < 8) wy = 60
            if (wy > lh-140) wy = lh-140
            spots.push({x: Math.max(4,Math.min(wx,lw-132)), y: wy, name:"win-"+(o.class||"win"), surface:"window"})
        }
        // active window center perch
        var act = Hyprland.activeToplevel
        if (act && act.lastIpcObject && act.lastIpcObject.at) {
            var a=act.lastIpcObject
            spots.push({x: Math.round(a.at[0] + a.size[0]/2 -64), y: Math.round(a.at[1]-54 + a.size[1]/2 -64), name:"active-center", surface:"window"})
        }
        root.toplevelCount = tls.length
        root.focusedApp = act && act.lastIpcObject ? (act.lastIpcObject.class||act.title||"") : ""
        root.freeSpots = spots
    }

    // quick check: is y on a known surface? (avoid floating mid-air)
    function isOnSurface(y, h) {
        var lh2 = Hyprland.focusedMonitor ? Math.round(Hyprland.focusedMonitor.height / Hyprland.focusedMonitor.scale) : 900
        // floor, ceiling, bar, window tops are surfaces; else floating
        if (Math.abs(y - (lh2 - 128 -6)) < 30) return true // floor
        if (y < 32) return true // ceiling
        if (Math.abs(y - 60) < 20) return true // bar
        for (var i=0;i<freeSpots.length;i++) if (Math.abs(y - freeSpots[i].y) < 28) return true
        return false
    }
}
