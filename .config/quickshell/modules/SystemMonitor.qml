import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// System Monitor — window with nice graphs, visible system colors, kill processes.
// Opens when clicking CPU or RAM pill, or `quickshell -p ~/.config/quickshell ipc call sysmon toggle`.
PanelWindow {
    id: root
    property var colors
    property bool open: false

    property var cpuHistory: []
    property var memHistory: []
    property int cpuUsage: 0
    property real memPct: 0
    property real memUsed: 0
    property real memTotal: 0
    property var processes: [] // {pid, cpu, mem, name}

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true

    IpcHandler { target: "sysmon"; function toggle(): void { root.open = !root.open } }

    function killPid(pid){
        Quickshell.execDetached(["sh","-c","kill "+pid+" 2>/dev/null || kill -9 "+pid])
        // refresh list after a moment
        procTimer.restart()
    }

    // backdrop
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.45 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 740
        height: 520
        radius: 18
        color: colors.alpha(colors.background, 0.97)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.25)
        focus: root.open
        Keys.onEscapePressed: root.open = false
        transform: Translate { id: slide }
        Component.onCompleted: slide.y = 20
        onVisibleChanged: {
            if (visible) { slide.y = 20; slideIn.restart() }
        }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "y"; from: 20; to: 0; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 200 }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "System Monitor"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth: true }
                Text { text: "CPU "+root.cpuUsage+"%  •  RAM "+Math.round(root.memPct)+"%"; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse ? colors.alpha(colors.error,0.15) : "transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.error:colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // graphs row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                // CPU graph
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    radius: 12
                    color: colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.secondary,0.25)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        Text { text: "CPU"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        Text { text: root.cpuUsage+"%"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 18; font.weight: Font.ExtraBold }
                        Canvas {
                            id: cpuCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=root.cpuHistory; if(h.length<2) return
                                var max=100
                                var n=h.length
                                function px(i){ return (i/(n-1))*width }
                                function py(v){ return height-2 - (v/max)*(height-6) }
                                ctx.beginPath(); ctx.moveTo(0,height)
                                for(var i=0;i<n;i++) ctx.lineTo(px(i), py(h[i]))
                                ctx.lineTo(px(n-1),height); ctx.closePath()
                                ctx.fillStyle=colors.alpha(colors.secondary,0.18); ctx.fill()
                                ctx.beginPath()
                                for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j]))
                                ctx.strokeStyle=colors.secondary; ctx.lineWidth=1.6; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: root; function onCpuHistoryChanged(){ cpuCanvas.requestPaint() } }
                        }
                    }
                }
                // RAM graph
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    radius: 12
                    color: colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.tertiary,0.25)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        Text { text: "MEMORY"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        Text { text: root.memUsed.toFixed(1)+" / "+root.memTotal.toFixed(1)+" GB"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Canvas {
                            id: memCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=root.memHistory; if(h.length<2) return
                                var max=100
                                var n=h.length
                                function px(i){ return (i/(n-1))*width }
                                function py(v){ return height-2 - (v/max)*(height-6) }
                                ctx.beginPath(); ctx.moveTo(0,height)
                                for(var i=0;i<n;i++) ctx.lineTo(px(i), py(h[i]))
                                ctx.lineTo(px(n-1),height); ctx.closePath()
                                ctx.fillStyle=colors.alpha(colors.tertiary,0.18); ctx.fill()
                                ctx.beginPath()
                                for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j]))
                                ctx.strokeStyle=colors.tertiary; ctx.lineWidth=1.6; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: root; function onMemHistoryChanged(){ memCanvas.requestPaint() } }
                        }
                    }
                }
                // Network mini
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    radius: 12
                    color: colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.primary,0.25)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4
                        Text { text: "NETWORK"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        NetRate { id: netRate }
                        Text { text: "↓ "+netRate.fmt(netRate.rxKbs)+"  ↑ "+netRate.fmt(netRate.txKbs); color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.DemiBold }
                        Canvas {
                            id: netCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=netRate.rxHistory; if(h.length<2) return
                                var max=100; for(var i=0;i<h.length;i++) max=Math.max(max,h[i])
                                var n=h.length
                                function px(i){ return (i/(n-1))*width }
                                function py(v){ return height-2 - (v/max)*(height-6) }
                                ctx.beginPath(); ctx.moveTo(0,height)
                                for(var i=0;i<n;i++) ctx.lineTo(px(i), py(h[i]))
                                ctx.lineTo(px(n-1),height); ctx.closePath()
                                ctx.fillStyle=colors.alpha(colors.primary,0.18); ctx.fill()
                                ctx.beginPath()
                                for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j]))
                                ctx.strokeStyle=colors.primary; ctx.lineWidth=1.6; ctx.lineJoin="round"; ctx.stroke()
                            }
                            Connections { target: netRate; function onRxHistoryChanged(){ netCanvas.requestPaint() } }
                        }
                    }
                }
            }

            // process header
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "PROCESSES"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.fillWidth: true }
                Text { text: root.processes.length+" running"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                Rectangle {
                    width: 56; height: 22; radius: 8
                    color: refreshMa.containsMouse?colors.alpha(colors.primary,0.15):"transparent"
                    Text { anchors.centerIn: parent; text: "↻"; color: colors.primary; font.pixelSize: 12 }
                    MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled:true; onClicked: psProc.running=true }
                }
            }

            // process list header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "PID"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 50 }
                Text { text: "NAME"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.fillWidth: true }
                Text { text: "CPU%"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                Text { text: "MEM%"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                Item { Layout.preferredWidth: 50 }
            }

            ListView {
                id: procList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.processes
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: procList.width
                    height: 32
                    radius: 8
                    color: maProc.containsMouse ? colors.alpha(colors.surfaceVariant,0.4) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8; anchors.rightMargin: 8
                        spacing: 8
                        Text { text: modelData.pid; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 50 }
                        Text { text: modelData.name; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.cpu; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                        Text { text: modelData.mem; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight }
                        Rectangle {
                            Layout.preferredWidth: 44; Layout.preferredHeight: 20; radius: 6
                            color: killMa.containsMouse ? colors.alpha(colors.error,0.9) : colors.alpha(colors.error,0.15)
                            border.width:1; border.color: colors.alpha(colors.error,0.4)
                            Text { anchors.centerIn: parent; text: "Kill"; color: killMa.containsMouse?colors.background:colors.error; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                            MouseArea { id: killMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.killPid(modelData.pid) }
                        }
                    }
                    MouseArea { id: maProc; anchors.fill: parent; hoverEnabled:true }
                }
            }
        }
    }

    // data collectors
    property int _prevTotal: 0
    property int _prevIdle: 0
    Process {
        id: cpuProc
        command: ["sh","-c","grep '^cpu ' /proc/stat"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var f=text.trim().split(/\s+/).slice(1).map(Number)
                var idle=f[3]+f[4]
                var total=f.reduce((a,b)=>a+b,0)
                if (root._prevTotal>0){
                    var dTotal=total-root._prevTotal, dIdle=idle-root._prevIdle
                    var u=Math.round(100*(1-dIdle/dTotal))
                    root.cpuUsage=u
                    var h=root.cpuHistory.slice(); h.push(u); if(h.length>40) h.shift(); root.cpuHistory=h
                }
                root._prevIdle=idle; root._prevTotal=total
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
        command: ["sh","-c","ps -eo pid,pcpu,pmem,comm --sort=-%cpu | head -n 40"]
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
    Timer { id: pollTimer; interval: 2000; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: { cpuProc.running=true; memProc.running=true } }
    Timer { id: procTimer; interval: 3000; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: psProc.running=true }
}
