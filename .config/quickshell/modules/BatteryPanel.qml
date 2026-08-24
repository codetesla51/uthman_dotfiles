import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Battery Panel — nice battery UI, change performance, calculate life & usage.
PanelWindow {
    id: root
    property var colors
    property bool open: false

    readonly property var dev: UPower.displayDevice
    readonly property int pct: dev ? Math.round(dev.percentage*100) : 0
    readonly property bool charging: dev ? (dev.state===UPowerDeviceState.Charging||dev.state===UPowerDeviceState.PendingCharge) : false
    readonly property bool full: dev ? dev.state===UPowerDeviceState.FullyCharged : false
    readonly property string stateStr: {
        if (!dev) return "No battery"
        if (dev.state===UPowerDeviceState.Charging) return "Charging"
        if (dev.state===UPowerDeviceState.Discharging) return "Discharging"
        if (dev.state===UPowerDeviceState.FullyCharged) return "Full"
        if (dev.state===UPowerDeviceState.PendingCharge) return "Pending"
        return "Unknown"
    }
    readonly property string timeStr: {
        if (!dev) return "—"
        if (dev.state===UPowerDeviceState.FullyCharged) return "Full"
        if (charging && dev.timeToFull>0) return fmtTime(dev.timeToFull)
        if (!charging && dev.timeToEmpty>0) return fmtTime(dev.timeToEmpty)
        if (dev.changeRate!==0 && dev.energy>0) {
            var hrs = dev.energy / Math.abs(dev.changeRate)
            return fmtTime(hrs*3600)
        }
        // fallback: estimate from capacity even when rate is 0 (fully charged on AC)
        if (dev.energyCapacity>0) return "~"+fmtTime(dev.energyCapacity/10*3600)
        return "—"
    }
    function fmtTime(s){
        if(s<=0) return "—"
        var h=Math.floor(s/3600), m=Math.floor((s%3600)/60)
        if(h>0) return h+"h "+m+"m"
        return m+"m"
    }

    property var pctHistory: []
    Timer {
        interval: 5000; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: {
            var h=pctHistory.slice(); h.push(pct); if(h.length>30) h.shift(); pctHistory=h
            // also poll power profile
            profileProc.running=true
        }
    }

    property string curProfile: "unknown"
    Process {
        id: profileProc
        command: ["sh","-c","powerprofilesctl get 2>/dev/null || echo unknown"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.curProfile = text.trim()
        }
    }
    function setProfile(p){
        Quickshell.execDetached(["sh","-c","powerprofilesctl set "+p+" 2>/dev/null || notify-send -u low 'Power profiles' 'daemon not running'"])
        curProfile=p
    }

    anchors { top:true; bottom:true; left:true; right:true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    IpcHandler { target: "battery"; function toggle(): void { root.open = !root.open } }

    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open?0.25:0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open=false }
    }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right }
        anchors.topMargin: 52; anchors.rightMargin: 8
        width: 400
        height: Math.min(620, col.implicitHeight+28)
        radius: 16
        color: colors.alpha(colors.background,0.96)
        border.width: 1; border.color: colors.alpha(colors.outline,0.25)
        focus: root.open
        Keys.onEscapePressed: root.open=false
        transform: Translate { id: slide }
        Component.onCompleted: slide.x=width+8
        onVisibleChanged: { if(visible){ slide.x=width+8; slideIn.restart() } }
        ParallelAnimation { id: slideIn; NumberAnimation { target: slide; property: "x"; from: card.width+8; to:0; duration: 250; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Battery"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth:true }
                Text { text: root.stateStr; color: root.charging?colors.secondary:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // big circular + stats
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Item {
                    width: 110; height: 110
                    Canvas {
                        id: batRing
                        anchors.fill: parent
                        property real pct: root.pct/100
                        onPctChanged: requestPaint()
                        onPaint: {
                            var ctx=getContext("2d"); ctx.reset()
                            var cx=width/2, cy=height/2, r=48
                            ctx.beginPath(); ctx.arc(cx,cy,r,0,Math.PI*2); ctx.strokeStyle=colors.alpha(colors.outline,0.15); ctx.lineWidth=8; ctx.stroke()
                            ctx.beginPath(); ctx.arc(cx,cy,r, -Math.PI/2, -Math.PI/2 + pct*Math.PI*2); ctx.strokeStyle= pct>0.3 ? (root.charging?colors.secondary:colors.primary) : colors.error; ctx.lineWidth=8; ctx.lineCap="round"; ctx.stroke()
                        }
                        Connections { target: root; function onPctChanged(){ batRing.requestPaint() } }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        Text { text: root.pct+"%"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 20; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                        Text { text: root.charging?"charging":""+(root.full?"full":""); color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    GridLayout {
                        columns: 2
                        columnSpacing: 12; rowSpacing: 6
                        Layout.fillWidth: true
                        Text { text: "Health"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                        Text { text: dev ? (dev.healthSupported ? Math.round(dev.healthPercentage)+"%" : "100%") : "—"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                        Text { text: "Capacity"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                        Text { text: dev ? (dev.energy.toFixed(1)+" / "+dev.energyCapacity.toFixed(1)+" Wh") : "—"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                        Text { text: "Rate"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                        Text { text: dev ? (dev.changeRate.toFixed(1)+" W") : "—"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                        Text { text: "Voltage"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                        Text { text: dev ? (dev.energy>0 ? (dev.energy/dev.percentage*100).toFixed(1)+" V" : "—") : "—"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: "Remaining"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.fillWidth: true }
                        Text { text: root.timeStr; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.alignment: Qt.AlignRight; horizontalAlignment: Text.AlignRight }
                    }
                }
            }

            // usage history graph
            Rectangle {
                Layout.fillWidth: true
                height: 80
                radius: 12
                color: colors.alpha(colors.surface,0.5)
                border.width:1; border.color: colors.alpha(colors.outline,0.12)
                Canvas {
                    id: histCanvas
                    anchors.fill: parent
                    anchors.margins: 8
                    onPaint: {
                        var ctx=getContext("2d"); ctx.reset()
                        var h=root.pctHistory; if(h.length<2) return
                        var n=h.length; function px(i){return (i/(n-1))*width} function py(v){return height-4 - (v/100)*(height-8)}
                        ctx.beginPath(); ctx.moveTo(0,height); for(var i=0;i<n;i++) ctx.lineTo(px(i),py(h[i])); ctx.lineTo(px(n-1),height); ctx.closePath(); ctx.fillStyle=colors.alpha(colors.tertiary,0.20); ctx.fill()
                        ctx.beginPath(); for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j])); ctx.strokeStyle=colors.tertiary; ctx.lineWidth=1.6; ctx.lineJoin="round"; ctx.stroke()
                    }
                    Connections { target: root; function onPctHistoryChanged(){ histCanvas.requestPaint() } }
                }
            }

            // performance profiles — current is highlighted + text above
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "PERFORMANCE"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.fillWidth: true }
                    Text { text: "Current: "+root.curProfile; color: root.curProfile==="unknown" ? colors.alpha(colors.outline,0.6) : colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.capitalization: Font.Capitalize }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [{id:"power-saver", label:"Saver", icon:"󰌪"}, {id:"balanced", label:"Balanced", icon:"󰾅"}, {id:"performance", label:"Turbo", icon:"󰓅"}]
                        delegate: Rectangle {
                            required property var modelData
                            property bool disabled: root.curProfile==="unknown"
                            Layout.fillWidth: true
                            height: 48
                            radius: 12
                            opacity: disabled ? 0.45 : 1
                            color: root.curProfile===modelData.id ? colors.alpha(colors.primary,0.18) : colors.alpha(colors.surface,0.6)
                            border.width:1; border.color: root.curProfile===modelData.id ? colors.alpha(colors.primary,0.4) : colors.alpha(colors.outline,0.12)
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                Text { text: modelData.icon; color: root.curProfile===modelData.id ? colors.primary : colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter }
                                Text { text: modelData.label; color: root.curProfile===modelData.id ? colors.primary : colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                            }
                            MouseArea { anchors.fill: parent; enabled: !disabled; onClicked: root.setProfile(modelData.id) }
                        }
                    }
                }
                Text {
                    visible: root.curProfile==="unknown"
                    text: "power-profiles-daemon not running"
                    color: colors.alpha(colors.outline,0.5)
                    font.family:"FiraCode Nerd Font"; font.pixelSize: 8
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
