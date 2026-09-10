import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// Control Center — bento-grid overlay popup (layershell).
// Now smaller (860×700), better sliders, full pet behavior, wifi graph fixed.
PanelWindow {
    id: root
    property var colors
    property bool open: false

    property real brightness: 0.62
    property real volume: 0.48
    property bool muted: false
    property var githubEvents: [
        { type: "PushEvent", repo: "uthman/dotfiles", msg: "feat: add package manager", time: "2h ago" },
        { type: "PullRequestEvent", repo: "uthman/dotfiles", msg: "opened PR #12", time: "5h ago" },
        { type: "PushEvent", repo: "uthman/habit", msg: "fix: heatmap off-by-one", time: "1d ago" }
    ]
    property var githubHeatCells: []
    property string weatherTemp: "23°"
    property string weatherFeel: "25°"
    property string weatherLoc: "Lagos"
    property string weatherCond: "Partly cloudy"
    property string weatherIcon: ""
    function condGlyph(c) {
        var t = String(c || "").toLowerCase()
        if (t.indexOf("thunder") !== -1 || t.indexOf("storm") !== -1) return ""
        if (t.indexOf("rain") !== -1 || t.indexOf("drizzle") !== -1 || t.indexOf("shower") !== -1) return ""
        if (t.indexOf("snow") !== -1 || t.indexOf("sleet") !== -1 || t.indexOf("hail") !== -1) return ""
        if (t.indexOf("fog") !== -1 || t.indexOf("mist") !== -1 || t.indexOf("haze") !== -1) return ""
        if (t.indexOf("clear") !== -1 || t.indexOf("sun") !== -1) return ""
        if (t.indexOf("cloud") !== -1 || t.indexOf("overcast") !== -1) return ""
        return ""
    }

    property var player: Mpris.players.values.find(function(p){ return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.playbackState === MprisPlaybackState.Playing
    property string npTitle: hasPlayer ? (player.trackTitle || "Unknown") : "Nothing playing"
    property string npArtist: {
        if (!hasPlayer) return ""
        var a = player.trackArtist
        return a && a.length>0 ? a : "Unknown artist"
    }
    property real npPos: {
        if (!hasPlayer || !player.length || player.length<=0) return 0.38
        return Math.max(0, Math.min(1, player.position / player.length))
    }
    property string npCur: {
        if (!hasPlayer || player.length<=0) return "1:22"
        var s = Math.floor(player.position); var m=Math.floor(s/60); s=s%60; return m+":"+(s<10?"0":"")+s
    }
    property string npTot: {
        if (!hasPlayer || player.length<=0) return "3:20"
        var s = Math.floor(player.length); var m=Math.floor(s/60); s=s%60; return m+":"+(s<10?"0":"")+s
    }
    property var cavaLevels: []

    // pet full behavior — reuse actual pet module assets, not just walking
    property var petActions: ({})
    property string petAssetsBase: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/assets/"
    property string petCurrentAction: "Stand"
    property var petCurrentFrames: ["shime1.png","shime1a.png"]
    property int petFrameIdx: 0
    property bool petFacingRight: false
    property var topActivities: [
        {app: "ghostty", secs: 5400},
        {app: "firefox", secs: 3200},
        {app: "code", secs: 1800},
        {app: "spotify", secs: 900}
    ]
    property var activityLast7: []
    property real activityMax: 1
    function fmtDurShort(s){ if(s<60) return s+"s"; var m=Math.floor(s/60); if(m<60) return m+"m"; var h=Math.floor(m/60); var rm=m%60; return h+"h"+(rm>0?" "+rm+"m":"") }
    function loadTopActivities(){
        try {
            var db=LocalStorage.openDatabaseSync("qs_screentime","1.0","screen time",1000000)
            var arr=[]
            db.transaction(function(tx){
                var rs=tx.executeSql("SELECT app, SUM(seconds) as s FROM app_time GROUP BY app ORDER BY s DESC LIMIT 5")
                for(var i=0;i<rs.rows.length;i++) arr.push({app: rs.rows.item(i).app, secs: rs.rows.item(i).s})
            })
            if(arr.length>0) topActivities=arr
        } catch(e){}
    }
    function loadActivityLast7(){
        try {
            var db=LocalStorage.openDatabaseSync("qs_screentime","1.0","screen time",1000000)
            var byDay={}
            var todayStr=Qt.formatDate(new Date(),"yyyy-MM-dd")
            db.transaction(function(tx){
                var rs=tx.executeSql("SELECT day, SUM(seconds) as s FROM app_time GROUP BY day")
                for(var i=0;i<rs.rows.length;i++) byDay[rs.rows.item(i).day]=rs.rows.item(i).s
            })
            var now=new Date(); now.setHours(0,0,0,0)
            var days=[]
            var maxS=1
            for(var i=6;i>=0;i--){
                var d=new Date(now); d.setDate(now.getDate()-i)
                var ds=Qt.formatDate(d,"yyyy-MM-dd")
                var s=byDay[ds]||0
                if(s>maxS) maxS=s
                days.push({date:d, dow:"MTWTFSS"[(d.getDay()+6)%7], secs:s, today: ds===todayStr})
            }
            // store normalized
            activityLast7=days
            activityMax=maxS
        } catch(e){ activityLast7=[] }
    }

    // mini calendar state: offset in months from today, rebuilt on open and on flip
    property int calOffset: 0
    property var calCells: []
    property string calTitle: ""
    function rebuildCal() {
        var now = new Date()
        var base = new Date(now.getFullYear(), now.getMonth() + root.calOffset, 1)
        var y = base.getFullYear(), m = base.getMonth()
        var first = (new Date(y, m, 1).getDay() + 6) % 7
        var dim = new Date(y, m + 1, 0).getDate()
        var cells = []
        for (var i = 0; i < first; i++) cells.push({ d: 0, today: false })
        for (var d = 1; d <= dim; d++) cells.push({ d: d, today: root.calOffset === 0 && d === now.getDate() })
        root.calCells = cells
        root.calTitle = Qt.formatDate(base, "MMMM yyyy")
    }
    function setBrightness(v){ Quickshell.execDetached(["sh","-c","brightnessctl set "+Math.round(v*100)+"% >/dev/null 2>&1 &"]) }
    Process {
        id: weatherProc
        command: ["sh", "-c", "curl -s --max-time 8 'wttr.in/Lagos?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(text)
                    var cur = j.current_condition[0]
                    root.weatherTemp = cur.temp_C + "°"
                    root.weatherFeel = cur.FeelsLikeC + "°"
                    root.weatherCond = cur.weatherDesc[0].value
                    root.weatherIcon = root.condGlyph(root.weatherCond)
                    var area = j.nearest_area[0]
                    if (area) root.weatherLoc = area.areaName[0].value
                } catch (e) {}
            }
        }
    }
    function setVolume(v){ Quickshell.execDetached(["sh","-c","wpctl set-volume @DEFAULT_AUDIO_SINK@ "+v.toFixed(2)+" >/dev/null 2>&1 || pactl set-sink-volume @DEFAULT_SINK@ "+Math.round(v*100)+"% >/dev/null 2>&1 &"]) }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-controlcenter"
    WlrLayershell.layer: WlrLayer.Overlay

    IpcHandler { target: "controlcenter"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if(open) { ghUserProc.running=true; btProc.running=true; weatherProc.running=true; root.calOffset=0; root.rebuildCal(); root.loadActivityLast7(); Qt.callLater(function(){ card.forceActiveFocus() }) }

    // pet actions loader — full behavior
    FileView {
        id: petActionsFile
        path: Quickshell.env("HOME") + "/.config/quickshell/modules/pet/config/pet-actions.json"
        printErrors: false
        onLoaded: {
            try { var d=JSON.parse(text()); root.petActions=d; var k=Object.keys(d); if(k.length>0){ var first=k[0]; root.petCurrentAction=first; root.petCurrentFrames=d[first] } } catch(e){}
        }
    }
    Timer { interval: 2600; running: root.open; repeat: true; onTriggered: {
        var keys=Object.keys(root.petActions); if(keys.length===0) return
        var pick=keys[Math.floor(Math.random()*keys.length)]
        root.petCurrentAction=pick; root.petCurrentFrames=root.petActions[pick]||["shime1.png"]; root.petFrameIdx=0
        root.petFacingRight = Math.random()>0.5
    } }
    Timer { interval: 180; running: root.open; repeat: true; onTriggered: {
        if(root.petCurrentFrames.length>0) root.petFrameIdx=(root.petFrameIdx+1)%root.petCurrentFrames.length
    } }

    // bluetooth — real devices via bluetoothctl, air buds icon, handles empty
    property var btDevices: []
    function toggleBt(idx){
        var list = root.btDevices.length>0 ? root.btDevices : [{name:"Air Buds Pro",mac:"",bat:"68%",connected:true},{name:"WH-1000XM5",mac:"",bat:"82%",connected:false}]
        var dev=list[idx]; if(!dev) return
        var target=dev.mac && dev.mac.length===17 ? dev.mac : dev.name
        Quickshell.execDetached(["sh","-c","bluetoothctl connect '"+String(target).replace(/'/g,"'\\''")+"' >/dev/null 2>&1 &"])
        if(root.btDevices.length>0){ var a=root.btDevices.slice(); a[idx].connected=!a[idx].connected; root.btDevices=a }
    }
    Process {
        id: btProc
        command: ["sh","-c","bluetoothctl devices 2>/dev/null | head -20"]
        stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
            var lines=text.trim().split("\n"); var arr=[]
            for(var i=0;i<lines.length;i++){ var l=lines[i].trim(); if(!l) continue; var m=l.match(/^Device\s+(\S+)\s+(.+)$/); if(!m) continue; var mac=m[1], name=m[2]; arr.push({name:name, mac:mac, bat:"", connected:false}) }
            if(arr.length>0) root.btDevices=arr
        }}
    }
    // github — real events via gh cli
    property string ghUser: "uthman"
    Process {
        id: ghUserProc
        command: ["sh","-c","gh api user --jq .login 2>/dev/null | tr -d '\\n'"]
        stdout: StdioCollector { waitForEnd:true; onStreamFinished: { var u=text.trim(); if(u) { root.ghUser=u; ghProc.running=true } } }
    }
    Process {
        id: ghProc
        command: ["sh","-c","gh api /users/"+root.ghUser+"/events --paginate 2>/dev/null | jq -r '.[0:100] | .[] | \"\\(.created_at)\"' 2>/dev/null | head -100"]
        stdout: StdioCollector { waitForEnd:true; onStreamFinished: {
            var lines=text.trim().split("\n")
            // build heatmap like ScreenTime: 105 cells, 15x7
            var byDay={}
            for(var i=0;i<lines.length;i++){
                var dstr=lines[i].trim().slice(0,10)
                if(!dstr) continue
                byDay[dstr]=(byDay[dstr]||0)+1
            }
            var now=new Date(); now.setHours(0,0,0,0)
            var dow=(now.getDay()+6)%7
            var start=new Date(now); start.setDate(now.getDate()-(14*7+dow))
            var cells=[]
            for(var c=0;c<105;c++){
                var d=new Date(start); d.setDate(start.getDate()+c)
                var ds=Qt.formatDate(d,"yyyy-MM-dd")
                var cnt=byDay[ds]||0
                cells.push({count:cnt, future: d>now, dateStr: ds})
            }
            root.githubHeatCells=cells
            // also keep githubEvents list for fallback (first 3)
            var arr=[]
            for(var k=0;k<Math.min(3, lines.length);k++){
                // reuse the same lines but need repo/type - fetch separately if needed
                // keep existing githubEvents as is for now
            }
        }}
    }

    NetRate { id: netRate }

    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.38 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 860
        height: 700
        radius: 24
        color: colors.alpha(colors.background, 0.62)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.18)
        scale: root.open ? 1 : 0.97
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "CONTROL CENTER"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold; font.letterSpacing: 1.6; Layout.fillWidth: true }
                Text { text: Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm"); color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 11 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // TOP — Now Playing (better visualizer, full width balance) | Weather compact
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 118
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 540
                    radius: 14
                    color: colors.alpha(colors.surface, 0.38)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        Text { text: "NOW PLAYING"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Rectangle {
                                Layout.preferredWidth: 64; Layout.preferredHeight: 64; radius: 10
                                color: colors.alpha(colors.surfaceVariant, 0.5)
                                border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: root.hasPlayer ? root.player.trackArtUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: root.hasPlayer && root.player.trackArtUrl !== ""
                                }
                                Text { anchors.centerIn: parent; visible: !root.hasPlayer || root.player.trackArtUrl==="" ; text: ""; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 18 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 3
                                Text { text: root.npTitle; color: root.hasPlayer?colors.foreground:colors.alpha(colors.foreground,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                Text { text: root.hasPlayer?root.npArtist:"No player"; color: colors.alpha(colors.outline,0.85); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                Rectangle {
                                    Layout.fillWidth: true; height: 14; radius: 7
                                    color: colors.alpha(colors.surfaceVariant, 0.5)
                                    Rectangle {
                                        width: parent.width * root.npPos; height: parent.height; radius: 7
                                        color: colors.primary
                                        Row {
                                            visible: root.cavaLevels.length===0
                                            anchors.fill: parent; anchors.margins: 3; spacing: 1
                                            Repeater { model: 12; Rectangle { width: (parent.width - 22)/12; height: 4 + Math.random()*4; radius: 1; color: colors.alpha(colors.background, 0.25); anchors.verticalCenter: parent.verticalCenter } }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: function(mouse){
                                            if(!root.hasPlayer || !root.player.length || !root.player.canSeek) return
                                            var v = mouse.x / width
                                            root.player.position = v * root.player.length
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.npCur; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                                    Item { Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 3
                                        Rectangle { width: 28; height: 28; radius: 14; color: prevMa.containsMouse?colors.alpha(colors.primary,0.15):"transparent"; Text { anchors.centerIn: parent; text: "󰒮"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 12 } MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled:true; onClicked: if(root.hasPlayer && root.player.canGoPrevious) root.player.previous() } }
                                        Rectangle { width: 32; height: 32; radius: 16; color: playMa.containsMouse?colors.primary:colors.alpha(colors.primary,0.18); border.width:1; border.color: playMa.containsMouse?colors.primary:colors.alpha(colors.primary,0.35); Text { anchors.centerIn: parent; text: root.isPlaying?"󰏤":"󰐊"; color: playMa.containsMouse?colors.background:colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 13 } MouseArea { id: playMa; anchors.fill: parent; hoverEnabled:true; onClicked: if(root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying() } }
                                        Rectangle { width: 28; height: 28; radius: 14; color: nextMa.containsMouse?colors.alpha(colors.primary,0.15):"transparent"; Text { anchors.centerIn: parent; text: "󰒭"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 12 } MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled:true; onClicked: if(root.hasPlayer && root.player.canGoNext) root.player.next() } }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.npTot; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                                }
                            }
                        }
                        Row {
                            Layout.fillWidth: true; Layout.preferredHeight: 14; spacing: 2
                            Repeater {
                                model: root.cavaLevels.length>0 ? 16 : 12
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int barCount: root.cavaLevels.length>0?16:12
                                    width: (parent.width - (barCount-1)*2)/barCount
                                    height: {
                                        if(root.cavaLevels.length>0) return Math.max(3, 14 * (root.cavaLevels[index]||0)/100)
                                        return root.isPlaying ? 3 + Math.random()*8 : 2
                                    }
                                    radius: 2
                                    color: [colors.primary, colors.secondary, colors.tertiary][index%3]
                                    opacity: 0.78
                                    anchors.bottom: parent.bottom
                                    Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                                    Timer { interval: 120 + index*18; running: root.isPlaying && root.cavaLevels.length===0; repeat:true; onTriggered: parent.height = 3 + Math.random()*8 }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 320; Layout.maximumWidth: 340
                    Layout.fillWidth: false; Layout.fillHeight: true
                    radius: 14
                    color: colors.alpha(colors.surface, 0.38)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                    ColumnLayout {
                        anchors.centerIn: parent; width: parent.width - 20; spacing: 4
                        Text { text: "WEATHER"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: root.weatherIcon !== "" ? root.weatherIcon : ""; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 28 }
                            ColumnLayout {
                                spacing: 1
                                Text { text: root.weatherTemp; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 22; font.weight: Font.ExtraBold }
                                Text { text: root.weatherCond; color: colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                spacing: 1; Layout.alignment: Qt.AlignVCenter
                                Text { text: root.weatherLoc; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; horizontalAlignment: Text.AlignRight }
                                Text { text: "feels " + root.weatherFeel; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                }
            }

            // QUICK CONTROLS — better UI, not simple — fixed overflow (was 92, now 108)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 108
                radius: 14
                color: colors.alpha(colors.surface, 0.38)
                border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 10
                    // Brightness — pill with icon + value + thicker track
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        RowLayout { spacing: 6; Rectangle { width: 22; height: 22; radius: 11; color: colors.alpha(colors.secondary,0.18); border.width:1; border.color: colors.alpha(colors.secondary,0.35); Text { anchors.centerIn: parent; text: "󰃠"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11 } } Text { text: "Brightness"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold } Item { Layout.fillWidth: true } Text { text: Math.round(root.brightness*100)+"%"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold } }
                        Slider {
                            id: briSlider
                            Layout.fillWidth: true
                            from: 0; to: 1; value: root.brightness
                            onPressedChanged: if(!pressed) { root.brightness = value; root.setBrightness(value) }
                            onValueChanged: if(pressed) { root.brightness = value; if(value%0.05 < 0.01) root.setBrightness(value) }
                            background: Rectangle { implicitHeight: 8; radius: 4; color: colors.alpha(colors.surfaceVariant,0.5); Rectangle { width: parent.width * (briSlider.value - briSlider.from)/(briSlider.to - briSlider.from); height: parent.height; radius: 4; color: colors.secondary; border.width:1; border.color: colors.alpha(colors.secondary,0.5) } }
                            handle: Rectangle { x: briSlider.leftPadding + briSlider.visualPosition * (briSlider.availableWidth - width); y: briSlider.topPadding + briSlider.availableHeight/2 - height/2; width: 20; height: 20; radius: 10; color: colors.secondary; border.width: 2; border.color: colors.background; Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: colors.background; opacity: 0.9 } }
                        }
                    }
                    Rectangle { width: 1; height: parent.height - 12; color: colors.alpha(colors.outline,0.12) }
                    // Volume — with mute toggle
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        RowLayout { spacing: 6; Rectangle { width: 22; height: 22; radius: 11; color: colors.alpha(colors.primary,0.18); border.width:1; border.color: colors.alpha(colors.primary,0.35); Text { anchors.centerIn: parent; text: root.muted ? "󰝟" : ""; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11 } MouseArea { anchors.fill: parent; onClicked: { root.muted=!root.muted; Quickshell.execDetached(["sh","-c","wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 &"]) } } } Text { text: "Volume"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold } Item { Layout.fillWidth: true } Text { text: Math.round(root.volume*100)+"%"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold } }
                        Slider {
                            id: volSlider
                            Layout.fillWidth: true
                            from: 0; to: 1; value: root.volume
                            onPressedChanged: if(!pressed) { root.volume = value; root.setVolume(value) }
                            onValueChanged: if(pressed) { root.volume = value; if(value%0.05 < 0.01) root.setVolume(value) }
                            background: Rectangle { implicitHeight: 8; radius: 4; color: colors.alpha(colors.surfaceVariant,0.5); Rectangle { width: parent.width * (volSlider.value - volSlider.from)/(volSlider.to - volSlider.from); height: parent.height; radius: 4; color: colors.primary; border.width:1; border.color: colors.alpha(colors.primary,0.5) } }
                            handle: Rectangle { x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width); y: volSlider.topPadding + volSlider.availableHeight/2 - height/2; width: 20; height: 20; radius: 10; color: colors.primary; border.width: 2; border.color: colors.background; Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: colors.background; opacity: 0.9 } }
                        }
                    }
                    Rectangle { width: 1; height: parent.height - 12; color: colors.alpha(colors.outline,0.12) }
                    // Bluetooth — air buds icon, no overflow, shows No Bluetooth when empty
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.preferredWidth: parent.width*0.38; spacing: 3
                        RowLayout { spacing: 6; Text { text: "󰂯"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11 } Text { text: "Bluetooth"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold } Item { Layout.fillWidth: true } Rectangle { width: 38; height: 18; radius: 9; color: colors.alpha(colors.tertiary,0.15); border.width:1; border.color: colors.alpha(colors.tertiary,0.35); Text { anchors.centerIn: parent; text: "On"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold } } }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text { visible: btRepeater.count===0; text: "No Bluetooth devices"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                            Repeater {
                                id: btRepeater
                                model: root.btDevices
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; height: 30; radius: 8
                                    color: modelData.connected ? colors.alpha(colors.tertiary,0.12) : colors.alpha(colors.surface,0.45)
                                    border.width: 1; border.color: modelData.connected ? colors.alpha(colors.tertiary,0.35) : colors.alpha(colors.outline,0.12)
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 6; spacing: 5
                                        Text {
                                            text: {
                                                var n=modelData.name.toLowerCase()
                                                if(n.indexOf("air")!==-1 || n.indexOf("buds")!==-1) return "󰋋"
                                                if(n.indexOf("wh-")!==-1) return "󰋋"
                                                if(n.indexOf("mx")!==-1) return "󰍽"
                                                return modelData.connected?"●":"○"
                                            }
                                            color: modelData.connected?colors.tertiary:colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 10
                                        }
                                        Text { text: modelData.name; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Text { visible: modelData.bat!==""; text: modelData.bat; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; Layout.preferredWidth: 28; horizontalAlignment: Text.AlignRight }
                                        Rectangle {
                                            Layout.preferredWidth: modelData.connected?62:52; Layout.preferredHeight: 18; radius: 9
                                            color: modelData.connected ? colors.alpha(colors.surface,0.6) : colors.alpha(colors.primary,0.14)
                                            border.width: 1; border.color: modelData.connected?colors.alpha(colors.outline,0.12):colors.alpha(colors.primary,0.35)
                                            Text { anchors.centerIn: parent; text: modelData.connected?"Connected":"Connect"; color: modelData.connected?colors.alpha(colors.outline,0.7):colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold }
                                            MouseArea { anchors.fill: parent; onClicked: root.toggleBt(index) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // WIFI GRAPH — transparent bg, wider sparkline, fills full width
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 82
                radius: 14
                color: "transparent"
                border.width: 0; border.color: "transparent"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 8
                    spacing: 10
                    Item {
                        Layout.preferredWidth: 220; Layout.fillHeight: true
                        Rectangle { anchors.fill: parent; radius: 10; color: colors.alpha(colors.surfaceVariant,0.25); border.width:1; border.color: colors.alpha(colors.outline,0.08) }
                        Canvas {
                            id: wifiSpark
                            anchors.fill: parent
                            anchors.margins: 6
                            Connections { target: netRate; function onRxHistoryChanged(){ wifiSpark.requestPaint() } }
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var h=netRate.rxHistory; if(h.length<2){
                                    ctx.strokeStyle=colors.alpha(colors.outline,0.12); ctx.lineWidth=1
                                    ctx.setLineDash([3,3]); ctx.beginPath(); ctx.moveTo(0,height/2); ctx.lineTo(width,height/2); ctx.stroke(); ctx.setLineDash([])
                                    return
                                }
                                var maxV=12; for(var i=0;i<h.length;i++) maxV=Math.max(maxV,h[i])
                                var n=h.length; function px(i){return (i/(n-1))*width} function py(v){return height-2 - (v/maxV)*(height-6)}
                                ctx.beginPath(); ctx.moveTo(0,height); for(var i=0;i<n;i++) ctx.lineTo(px(i),py(h[i])); ctx.lineTo(px(n-1),height); ctx.closePath(); ctx.fillStyle=colors.alpha(colors.tertiary,0.22); ctx.fill()
                                ctx.beginPath(); for(var j=0;j<n;j++) if(j===0) ctx.moveTo(px(j),py(h[j])); else ctx.lineTo(px(j),py(h[j])); ctx.strokeStyle=colors.tertiary; ctx.lineWidth=2; ctx.lineJoin="round"; ctx.stroke()
                                ctx.beginPath(); ctx.arc(px(n-1), py(h[n-1]), 2, 0, Math.PI*2); ctx.fillStyle=colors.tertiary; ctx.fill()
                            }
                        }
                        Text { anchors.centerIn: parent; visible: netRate.rxHistory.length<2; text: "collecting…"; color: colors.alpha(colors.outline,0.45); font.family:"FiraCode Nerd Font"; font.pixelSize: 7 }
                    }
                    Rectangle { width: 1; height: parent.height - 16; color: colors.alpha(colors.outline,0.12) }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 3
                        Layout.alignment: Qt.AlignHCenter
                        RowLayout { spacing: 5; Layout.alignment: Qt.AlignHCenter; Text { text: "󰇚"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11 } Text { text: netRate.fmt(netRate.rxKbs); color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold } }
                        Text { text: "DOWNLOAD"; color: colors.alpha(colors.outline,0.55); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "today  " + netRate.fmtTotal(netRate.totalRxMb) + "  ·  total " + netRate.fmtTotal(netRate.totalRxMb); color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter }
                    }
                    Rectangle { width: 1; height: parent.height - 16; color: colors.alpha(colors.outline,0.12) }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 3
                        Layout.alignment: Qt.AlignHCenter
                        RowLayout { spacing: 5; Layout.alignment: Qt.AlignHCenter; Text { text: "󰕒"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11 } Text { text: netRate.fmt(netRate.txKbs); color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold } }
                        Text { text: "UPLOAD"; color: colors.alpha(colors.outline,0.55); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "today  " + netRate.fmtTotal(netRate.totalTxMb) + "  ·  total " + netRate.fmtTotal(netRate.totalTxMb); color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }

            // MIDDLE — Pet (alive, full behavior) | Activity | Calendar
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 142
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 14
                    color: colors.alpha(colors.surface, 0.38)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                        Text { text: "PET — HORNET"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.1; Layout.fillWidth: true; elide: Text.ElideRight }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            property var petFrames: ["shime1.png","shime1a.png","shime2.png","shime1.png"]
                            property int petIdx: 0
                            // full behavior: random action from pet module every 2.6s
                            Timer { interval: 180; running: root.open; repeat: true; onTriggered: parent.petIdx = (parent.petIdx+1)%parent.petFrames.length }
                            Text {
                                anchors.top: parent.top; anchors.right: parent.right; anchors.topMargin: 2; anchors.rightMargin: 2
                                text: root.petCurrentAction; color: colors.alpha(colors.primary,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 6; font.weight: Font.Bold; elide: Text.ElideRight
                            }
                            Image {
                                id: alivePet
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -8
                                source: "file://" + root.petAssetsBase + (root.petCurrentFrames[root.petFrameIdx] || "shime1.png")
                                width: 96; height: 96
                                fillMode: Image.PreserveAspectFit
                                smooth: false
                                mirror: root.petFacingRight
                                SequentialAnimation on y {
                                    running: root.open; loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: -3; duration: 550; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: -3; to: 0; duration: 550; easing.type: Easing.InOutSine }
                                }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                                width: petLabel2.implicitWidth+8; height: 12; radius: 6
                                color: colors.alpha(colors.primary,0.14)
                                border.width:1; border.color: colors.alpha(colors.primary,0.22)
                                Text { id: petLabel2; anchors.centerIn: parent; text: "alive — " + root.petCurrentAction; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 6; font.weight: Font.Bold }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["quickshell","-p", Quickshell.env("HOME")+"/.config/quickshell","ipc","call","pet","pet"]) }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 14
                    color: colors.alpha(colors.surface, 0.38)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                        Text { text: "ACTIVITY — 7 DAYS"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        RowLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 4
                            Repeater {
                                model: root.activityLast7
                                delegate: ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 3
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                        color: colors.alpha(colors.primary, 0.12)
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: {
                                                var s = modelData.secs || 0
                                                if (s <= 0) return 0
                                                return Math.max(5, parent.height * s / Math.max(1, root.activityMax))
                                            }
                                            radius: 6; color: colors.primary; opacity: 0.85
                                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    Text { text: modelData.dow; color: modelData.today ? colors.primary : colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 7; font.weight: modelData.today ? Font.Bold : Font.Normal; Layout.alignment: Qt.AlignHCenter }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 14
                    color: colors.alpha(colors.surface, 0.38)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.18)
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: prevCalMa.containsMouse ? colors.alpha(colors.primary,0.18) : colors.alpha(colors.primary,0.08)
                                Text { anchors.centerIn: parent; text: "‹"; color: colors.primary; font.pixelSize: 11 }
                                MouseArea { id: prevCalMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.calOffset -= 1; root.rebuildCal() } }
                            }
                            Text { text: root.calTitle; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                            Rectangle {
                                width: 20; height: 20; radius: 10
                                color: nextCalMa.containsMouse ? colors.alpha(colors.primary,0.18) : colors.alpha(colors.primary,0.08)
                                Text { anchors.centerIn: parent; text: "›"; color: colors.primary; font.pixelSize: 11 }
                                MouseArea { id: nextCalMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.calOffset += 1; root.rebuildCal() } }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true; columns: 7; rowSpacing: 1; columnSpacing: 3
                            Repeater { model: ["M","T","W","T","F","S","S"]; Text { text: modelData; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 6; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter } }
                            Repeater {
                                model: root.calCells
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.preferredHeight: 13; radius: 6
                                    color: modelData.today ? colors.primary : "transparent"
                                    Text { anchors.centerIn: parent; visible: modelData.d > 0; text: modelData.d; color: modelData.today ? colors.background : colors.alpha(colors.foreground,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: modelData.today ? Font.Bold : Font.Normal }
                                }
                            }
                        }
                    }
                }
            }


            Text {
                text: "Esc or SUPER ALT P to close  •  sliders/typing inside never closes  •  outside click does not close"
                color: colors.alpha(colors.outline, 0.38)
                font.family:"FiraCode Nerd Font"; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}