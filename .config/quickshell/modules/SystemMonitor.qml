import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

// System Monitor — POWER USER edition. Large, visible, kill anything.
// Opens via CPU/RAM pill click or `quickshell -p ~/.config/quickshell ipc call sysmon toggle`
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string filter: ""
    property string sortBy: "mem"
    property int topN: 20


    property var cpuHistory: []
    property var memHistory: []
    property int cpuUsage: 0
    property var cpuCores: [] // per-core %
    property real memPct: 0
    property real memUsed: 0
    property real memTotal: 0
    property var processes: []
    property var filteredProcesses: {
        var f = filter.trim().toLowerCase()
        var list = f === "" ? processes : processes.filter(function(p){ return p.name.toLowerCase().includes(f) || p.pid.includes(f) })
        // sort
        list = list.slice()
        if (sortBy === "cpu") list.sort(function(a,b){ return parseFloat(b.cpu)-parseFloat(a.cpu) })
        else if (sortBy === "mem") list.sort(function(a,b){ return parseFloat(b.mem)-parseFloat(a.mem) })
        else if (sortBy === "pid") list.sort(function(a,b){ return parseInt(a.pid)-parseInt(b.pid) })
        if (topN>0) list = list.slice(0, topN)
        return list
    }
    title: "System Monitor"
    implicitWidth: 860
    implicitHeight: 580
    minimumSize: Qt.size(700, 480)
    maximumSize: Qt.size(1000, 700)
    color: "transparent"
    visible: root.open


    IpcHandler { target: "sysmon"; function toggle(): void { root.open = !root.open } }

    // stats-only — no kill, just cool graphs

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 20
        color: colors.alpha(colors.background, 0.65)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.12)
        focus: root.open
        Keys.onEscapePressed: root.open = false



        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // header — power-user, visible, not cramped
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: 12
                color: colors.alpha(colors.surface,0.6)
                border.width: 1; border.color: colors.alpha(colors.outline,0.15)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 12
                    Text { text: "◉ SYSTEM MONITOR"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold; font.letterSpacing: 1.2 }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: 1
                        Layout.alignment: Qt.AlignVCenter
                        Text { text: "CPU  "+root.cpuUsage+"%"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignRight }
                        Text { text: "RAM  "+Math.round(root.memPct)+"%"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignRight }
                    }
                    Rectangle { width: 1; height: 28; color: colors.alpha(colors.outline,0.15) }
                    Text { text: root.memUsed.toFixed(1)+"G / "+root.memTotal.toFixed(1)+"G"; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.alignment: Qt.AlignVCenter }
                }

            }

            // graphs row — visible, system colors, big
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                // CPU
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 14
                    color: colors.alpha(colors.surface,0.55)
                    border.width:1; border.color: colors.alpha(colors.secondary,0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "CPU"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold; font.letterSpacing: 1.4; Layout.fillWidth: true }
                            Text { text: root.cpuUsage+"%"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 20; font.weight: Font.ExtraBold }
                        }
                        // per-core — circular, go all in
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: root.cpuCores.length>0
                            Repeater {
                                model: root.cpuCores
                                delegate: Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 52
                                    Canvas {
                                antialiasing: true
                                
                                        id: coreRing
                                        anchors.centerIn: parent
                                        width: 44; height: 44
                                        property real pct: modelData/100
                                        onPctChanged: requestPaint()
                                        onPaint: {
                                            var ctx=getContext("2d"); ctx.reset()
                                            var cx=width/2, cy=height/2, r=18
                                            ctx.beginPath(); ctx.arc(cx,cy,r,0,Math.PI*2); ctx.strokeStyle=colors.alpha(colors.outline,0.15); ctx.lineWidth=3; ctx.stroke()
                                            ctx.beginPath(); ctx.arc(cx,cy,r, -Math.PI/2, -Math.PI/2 + pct*Math.PI*2); ctx.strokeStyle=colors.secondary; ctx.lineWidth=3; ctx.lineCap="round"; ctx.stroke()
                                        }
                                        Connections { target: root; function onCpuCoresChanged(){ coreRing.requestPaint() } }
                                    }
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 0
                                        Text { text: modelData+"%"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                                        Text { text: "C"+index; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter }
                                    }
                                }
                            }
                        }
                        Canvas {
                                antialiasing: true
                                
                            id: cpuCanvas
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=root.cpuHistory; if(h.length<2) return
                                var n=h.length; function px(i){return (i/(n-1))*width} function py(v){return height-2 - (v/100)*(height-6)}
                                ctx.beginPath(); ctx.moveTo(0,height); for(var i=0;i<n;i++) ctx.lineTo(px(i),py(h[i])); ctx.lineTo(px(n-1),height); ctx.closePath(); ctx.fillStyle=colors.alpha(colors.secondary,0.14); ctx.fill()
                                ctx.beginPath(); for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j])); ctx.strokeStyle=colors.secondary; ctx.lineWidth=1.4; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: root; function onCpuHistoryChanged(){ cpuCanvas.requestPaint() } }
                        }

                    }
                }
                // MEM
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 14
                    color: colors.alpha(colors.surface,0.55)
                    border.width:1; border.color: colors.alpha(colors.tertiary,0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "MEMORY"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold; font.letterSpacing: 1.4; Layout.fillWidth: true }
                            Text { text: root.memUsed.toFixed(1)+" / "+root.memTotal.toFixed(1)+" GB"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                        }
                        Text { text: Math.round(root.memPct)+"% used"; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                        Canvas {
                                antialiasing: true
                                
                            id: memCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=root.memHistory; if(h.length<2) return
                                var n=h.length; function px(i){return (i/(n-1))*width} function py(v){return height-2 - (v/100)*(height-6)}
                                ctx.beginPath(); ctx.moveTo(0,height); for(var i=0;i<n;i++) ctx.lineTo(px(i),py(h[i])); ctx.lineTo(px(n-1),height); ctx.closePath(); ctx.fillStyle=colors.alpha(colors.tertiary,0.20); ctx.fill()
                                ctx.beginPath(); for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j])); ctx.strokeStyle=colors.tertiary; ctx.lineWidth=2.2; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: root; function onMemHistoryChanged(){ memCanvas.requestPaint() } }
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 6; radius: 3
                            color: colors.alpha(colors.surfaceVariant,0.5)
                            Rectangle { width: parent.width * (root.memPct/100); height: parent.height; radius: 3; color: colors.tertiary }
                        }

                    }
                }
                // NET
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 14
                    color: colors.alpha(colors.surface,0.55)
                    border.width:1; border.color: colors.alpha(colors.primary,0.35)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        Text { text: "NETWORK"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold; font.letterSpacing: 1.4 }
                        NetRate { id: netRate }
                        Text { text: "↓ "+netRate.fmt(netRate.rxKbs)+"   ↑ "+netRate.fmt(netRate.txKbs); color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                        Canvas {
                                antialiasing: true
                                
                            id: netCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=netRate.rxHistory; if(h.length<2) return
                                var max=100; for(var i=0;i<h.length;i++) max=Math.max(max,h[i])
                                var n=h.length; function px(i){return (i/(n-1))*width} function py(v){return height-2 - (v/max)*(height-6)}
                                ctx.beginPath(); ctx.moveTo(0,height); for(var i=0;i<n;i++) ctx.lineTo(px(i),py(h[i])); ctx.lineTo(px(n-1),height); ctx.closePath(); ctx.fillStyle=colors.alpha(colors.primary,0.20); ctx.fill()
                                ctx.beginPath(); for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j])); ctx.strokeStyle=colors.primary; ctx.lineWidth=2.2; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: netRate; function onRxHistoryChanged(){ netCanvas.requestPaint() } }
                        }
                        Text { text: "total ↓ "+netRate.fmtTotal(netRate.totalRxMb)+"  ↑ "+netRate.fmtTotal(netRate.totalTxMb); color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                    }
                }
            }

            // toolbar — search + sort + kill controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                TextField {
                    id: filterField
                    Layout.fillWidth: true
                    implicitHeight: 38
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 8
                    bottomPadding: 8
                    placeholderText: "  Filter processes…"
                    placeholderTextColor: colors.alpha(colors.outline,0.5)
                    color: colors.foreground
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    background: Rectangle {
                        radius: 12
                        color: colors.alpha(colors.surface,0.8)
                        border.width: 1
                        border.color: filterField.activeFocus ? colors.alpha(colors.primary,0.5) : colors.alpha(colors.outline,0.2)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    onTextChanged: root.filter = text
                }
                Repeater {
                    model: [{k:"cpu", l:"CPU"},{k:"mem", l:"MEM"},{k:"pid", l:"PID"}]
                    delegate: Rectangle {
                        required property var modelData
                        width: 52; height: 28; radius: 8
                        color: root.sortBy===modelData.k ? colors.alpha(colors.primary,0.25) : colors.alpha(colors.surface,0.6)
                        border.width:1; border.color: root.sortBy===modelData.k ? colors.alpha(colors.primary,0.4) : colors.alpha(colors.outline,0.12)
                        Text { anchors.centerIn: parent; text: modelData.l; color: root.sortBy===modelData.k?colors.primary:colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; onClicked: root.sortBy = modelData.k }
                    }
                }
                Text { text: root.filteredProcesses.length+" / "+root.processes.length; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                Rectangle {
                    width: 28; height: 28; radius: 8
                    color: refreshMa.containsMouse?colors.alpha(colors.primary,0.15):"transparent"
                    Text { anchors.centerIn: parent; text: "↻"; color: colors.primary; font.pixelSize: 14 }
                    MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled:true; onClicked: psProc.running=true }
                }
            }
            // top N filter — power-user
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "TOP RAM EATERS"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                Repeater {
                    model: [10,20,40,0]
                    delegate: Rectangle {
                        required property var modelData
                        width: 44; height: 22; radius: 7
                        color: root.topN===modelData ? colors.alpha(colors.primary,0.22) : colors.alpha(colors.surface,0.6)
                        border.width:1; border.color: root.topN===modelData ? colors.alpha(colors.primary,0.4) : colors.alpha(colors.outline,0.12)
                        Text { anchors.centerIn: parent; text: modelData===0?"All":modelData; color: root.topN===modelData?colors.primary:colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                        MouseArea { anchors.fill: parent; onClicked: root.topN = modelData }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // process header — power-user columns
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "PID"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.preferredWidth: 70 }
                Text { text: "COMMAND"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.fillWidth: true }
                Text { text: "CPU%"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                Text { text: "MEM%"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }

            }

            ListView {
                id: procList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filteredProcesses
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: procList.width
                    height: 32
                    radius: 10
                    color: maProc.containsMouse ? colors.alpha(colors.primary,0.08) : index%2===0 ? colors.alpha(colors.surface,0.35) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 8
                        spacing: 8
                        Text { text: modelData.pid; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 60 }
                        Text { text: modelData.name; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                        Rectangle { width: 48; height: 14; radius: 7; color: colors.alpha(colors.secondary, parseFloat(modelData.cpu)/100*0.35+0.08); Text { anchors.centerIn: parent; text: modelData.cpu+"%"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold } }
                        Rectangle { width: 48; height: 14; radius: 7; color: colors.alpha(colors.tertiary, parseFloat(modelData.mem)/100*0.35+0.08); Text { anchors.centerIn: parent; text: modelData.mem+"%"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold } }
                    }
                    MouseArea { id: maProc; anchors.fill: parent; hoverEnabled:true }
                }
            }
        }
    }

    // data collectors — with per-core
    property int _prevTotal: 0
    property int _prevIdle: 0
    property var _prevPerCore: []
    Process {
        id: cpuProc
        command: ["sh","-c","grep '^cpu' /proc/stat"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                // first line is aggregate, rest are cores
                var allUsages=[]
                for(var li=0; li<lines.length; li++){
                    var f=lines[li].trim().split(/\s+/).slice(1).map(Number)
                    if(f.length<4) continue
                    var idle=f[3]+(f[4]||0), total=f.reduce((a,b)=>a+b,0)
                    if(li===0){
                        if(root._prevTotal>0){
                            var dT=total-root._prevTotal, dI=idle-root._prevIdle
                            var u=Math.round(100*(1-dI/dT))
                            root.cpuUsage=u
                            var h=root.cpuHistory.slice(); h.push(u); if(h.length>40) h.shift(); root.cpuHistory=h
                        }
                        root._prevIdle=idle; root._prevTotal=total
                    } else {
                        var prev=root._prevPerCore[li-1]
                        if(prev){
                            var dTc=total-prev.total, dIc=idle-prev.idle
                            var cu=Math.round(100*(1-dIc/dTc))
                            allUsages.push(cu)
                        } else {
                            allUsages.push(0)
                        }
                        if(!root._prevPerCore[li-1]) root._prevPerCore[li-1]={}
                        root._prevPerCore[li-1]={total:total, idle:idle}
                    }
                }
                if(allUsages.length>0) root.cpuCores=allUsages
            }
        }
    }
    Process {
        id: memProc
        command: ["sh","-c","grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var vals={}; text.trim().split("\n").forEach(function(l){var p=l.split(":"); vals[p[0]]=parseInt(p[1])})
                if(vals["MemTotal"]){
                    var tot=vals["MemTotal"]/1048576, used=(vals["MemTotal"]-vals["MemAvailable"])/1048576
                    root.memTotal=tot; root.memUsed=used; root.memPct=100*used/tot
                    var h=root.memHistory.slice(); h.push(root.memPct); if(h.length>40) h.shift(); root.memHistory=h
                }
            }
        }
    }
    Process {
        id: psProc
        command: ["sh","-c","ps -eo pid,pcpu,pmem,comm --sort=-%cpu | head -n 60"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n").slice(1)
                var arr=[]
                for(var i=0;i<lines.length;i++){
                    var p=lines[i].trim().split(/\s+/)
                    if(p.length<4) continue
                    arr.push({pid:p[0], cpu:p[1], mem:p[2], name:p.slice(3).join(" ")})
                }
                root.processes=arr
            }
        }
    }
    Timer { id: pollTimer; interval: 1500; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: { cpuProc.running=true; memProc.running=true } }
    Timer { id: procTimer; interval: 2500; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: psProc.running=true }
}

