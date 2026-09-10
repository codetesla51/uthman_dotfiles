import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0
import QtQuick.Effects

// Control Center — bento-grid overlay popup (layershell).
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
        command: ["sh", "-c", "curl -s --max-time 8 'wttr.in/Lagos,Nigeria?format=j1' 2>/dev/null"]
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
            anchors.margins: 14
            spacing: 10

            // ── TOP — Now Playing | Weather ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 138
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 16
                    clip: true
                    color: colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                    Image {
                        id: npBg
                        anchors.fill: parent
                        source: root.hasPlayer ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: root.hasPlayer && root.player.trackArtUrl !== ""
                        layer.enabled: visible
                        layer.effect: MultiEffect {
                            blurEnabled: false
                            saturation: 0.85
                            brightness: -0.08
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: npBg.visible
                        gradient: Gradient {
                            GradientStop { position: 0; color: colors.alpha(colors.background, 0.5) }
                            GradientStop { position: 0.55; color: colors.alpha(colors.background, 0.4) }
                            GradientStop { position: 1; color: colors.alpha(colors.background, 0.85) }
                        }
                    }
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "NOW PLAYING"; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                            Item { Layout.fillWidth: true }
                            Text { text: root.isPlaying ? "▶ PLAYING" : "PAUSED"; color: root.isPlaying ? colors.primary : colors.alpha(colors.outline,0.45); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1 }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 5
                                Text {
                                    Layout.fillWidth: true
                                    text: root.npTitle
                                    color: root.hasPlayer?colors.foreground:colors.alpha(colors.foreground,0.5)
                                    font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; elide: Text.ElideRight
                                }
                                Text { text: root.hasPlayer?root.npArtist:"No player"; color: colors.alpha(colors.foreground,0.7); font.family: colors.fontSans; font.pixelSize: 9; elide: Text.ElideRight; Layout.fillWidth: true }
                                Rectangle {
                                    Layout.fillWidth: true; height: 18; radius: 9
                                    color: colors.alpha(colors.surfaceVariant, 0.55)
                                    Rectangle {
                                        width: Math.max(18, parent.width * root.npPos); height: parent.height; radius: 9
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: colors.primary }
                                            GradientStop { position: 0.55; color: colors.secondary }
                                            GradientStop { position: 1; color: colors.tertiary }
                                        }
                                        Rectangle {
                                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                            width: 10; height: 10; radius: 5
                                            color: colors.background
                                            border.width: 2; border.color: colors.primary
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
                                    Text { text: root.npCur; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 8 }
                                    Item { Layout.fillWidth: true }
                                    RowLayout {
                                        spacing: 5
                                        Rectangle { width: 28; height: 28; radius: 14; color: "transparent"; Text { anchors.centerIn: parent; text: "󰒮"; color: colors.alpha(colors.foreground,0.7); font.family: colors.fontSans; font.pixelSize: 11 } MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled:false; onClicked: if(root.hasPlayer && root.player.canGoPrevious) root.player.previous() } }
                                        Rectangle {
                                            width: 38; height: 38; radius: 19
                                            color: playMa.containsMouse ? colors.primary : colors.alpha(colors.primary,0.18)
                                            border.width: 1; border.color: root.isPlaying ? colors.alpha(colors.primary,0.6) : colors.alpha(colors.primary,0.35)
                                            Text { anchors.centerIn: parent; text: root.isPlaying?"󰏤":"󰐊"; color: playMa.containsMouse ? colors.background : colors.primary; font.family: colors.fontSans; font.pixelSize: 15 }
                                            MouseArea { id: playMa; anchors.fill: parent; hoverEnabled:true; onClicked: if(root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying() }
                                        }
                                        Rectangle { width: 28; height: 28; radius: 14; color: "transparent"; Text { anchors.centerIn: parent; text: "󰒭"; color: colors.alpha(colors.foreground,0.7); font.family: colors.fontSans; font.pixelSize: 11 } MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled:false; onClicked: if(root.hasPlayer && root.player.canGoNext) root.player.next() } }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.npTot; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 8 }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 300; Layout.maximumWidth: 300; Layout.minimumWidth: 300
                    Layout.fillWidth: false; Layout.fillHeight: true
                    radius: 16
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: colors.alpha(colors.tertiary, 0.14) }
                        GradientStop { position: 1; color: colors.alpha(colors.surface, 0.4) }
                    }
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 6
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "WEATHER"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        radius: 2
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.maximumWidth: 170
                                        width: Math.min(locText.implicitWidth + 16, 170); height: 20
                                        color: colors.alpha(colors.tertiary, 0.16)
                                        border.width: 1; border.color: colors.alpha(colors.tertiary, 0.35)
                                        Text { id: locText; anchors.centerIn: parent; width: parent.width - 12; elide: Text.ElideRight; text: root.weatherLoc; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                                    }
                                }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 12
                            Text { text: root.weatherIcon !== "" ? root.weatherIcon : ""; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 40 }
                            ColumnLayout {
                                spacing: 1
                                Text { text: root.weatherTemp; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 30; font.weight: Font.ExtraBold; maximumLineCount: 1 }
                                Text { text: root.weatherCond; Layout.maximumWidth: 130; maximumLineCount: 1; elide: Text.ElideRight; color: colors.alpha(colors.outline,0.8); font.family: colors.fontSans; font.pixelSize: 9 }
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: "feels " + root.weatherFeel; maximumLineCount: 1; elide: Text.ElideRight; Layout.maximumWidth: 70; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 9; Layout.alignment: Qt.AlignBottom }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ── QUICK CONTROLS ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 116
                radius: 16
                color: colors.alpha(colors.surface, 0.4)
                border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                clip: true
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12
                    spacing: 12
                    // Brightness
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        RowLayout { spacing: 8; Layout.alignment: Qt.AlignVCenter; Layout.bottomMargin: 7
                            Rectangle { width: 26; height: 26; radius: 13; color: colors.alpha(colors.secondary,0.15); border.width:1; border.color: colors.alpha(colors.secondary,0.3); Text { anchors.centerIn: parent; text: "󰃠"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 12 } }
                            Text { text: "BRIGHTNESS"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                            Item { Layout.fillWidth: true }
                            Text { text: Math.round(root.brightness*100)+"%"; Layout.alignment: Qt.AlignVCenter; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                        }
                        Slider {
                            id: briSlider
                            Layout.fillWidth: true
                            from: 0; to: 1; value: root.brightness
                            onPressedChanged: if(!pressed) { root.brightness = value; root.setBrightness(value) }
                            onValueChanged: if(pressed) { root.brightness = value; if(value%0.05 < 0.01) root.setBrightness(value) }
                            background: Rectangle { implicitHeight: 7; radius: 4; color: colors.alpha(colors.surfaceVariant,0.55); Rectangle { width: parent.width * (briSlider.value - briSlider.from)/(briSlider.to - briSlider.from); height: parent.height; radius: 4; color: colors.secondary; opacity: 0.9 } }
                            handle: Rectangle { x: briSlider.leftPadding + briSlider.visualPosition * (briSlider.availableWidth - width); y: briSlider.topPadding + briSlider.availableHeight/2 - height/2; width: 18; height: 18; radius: 9; color: briSlider.pressed ? colors.secondary : colors.background; border.width: 2; border.color: colors.secondary; Behavior on color { ColorAnimation { duration: 150 } } }
                        }
                    }
                    Rectangle { width: 1; height: parent.height - 14; color: colors.alpha(colors.outline,0.12) }
                    // Volume
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 6
                        RowLayout { spacing: 8; Layout.alignment: Qt.AlignVCenter; Layout.bottomMargin: 7
                            Rectangle { width: 26; height: 26; radius: 13; color: colors.alpha(colors.primary,0.15); border.width:1; border.color: colors.alpha(colors.primary,0.3); Text { anchors.centerIn: parent; text: root.muted ? "󰝟" : ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 } MouseArea { anchors.fill: parent; onClicked: { root.muted=!root.muted; Quickshell.execDetached(["sh","-c","wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 &"]) } } }
                            Text { text: "VOLUME"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                            Item { Layout.fillWidth: true }
                            Text { text: Math.round(root.volume*100)+"%"; Layout.alignment: Qt.AlignVCenter; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                        }
                        Slider {
                            id: volSlider
                            Layout.fillWidth: true
                            from: 0; to: 1; value: root.volume
                            onPressedChanged: if(!pressed) { root.volume = value; root.setVolume(value) }
                            onValueChanged: if(pressed) { root.volume = value; if(value%0.05 < 0.01) root.setVolume(value) }
                            background: Rectangle { implicitHeight: 7; radius: 4; color: colors.alpha(colors.surfaceVariant,0.55); Rectangle { width: parent.width * (volSlider.value - volSlider.from)/(volSlider.to - volSlider.from); height: parent.height; radius: 4; color: colors.primary; opacity: 0.9 } }
                            handle: Rectangle { x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - width); y: volSlider.topPadding + volSlider.availableHeight/2 - height/2; width: 18; height: 18; radius: 9; color: volSlider.pressed ? colors.primary : colors.background; border.width: 2; border.color: colors.primary; Behavior on color { ColorAnimation { duration: 150 } } }
                        }
                    }
                    Rectangle { width: 1; height: parent.height - 14; color: colors.alpha(colors.outline,0.12) }
                    // Bluetooth
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.preferredWidth: parent.width*0.32; spacing: 3
                        RowLayout { spacing: 8; Layout.alignment: Qt.AlignVCenter; Text { text: "󰂯"; Layout.alignment: Qt.AlignVCenter; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 12 } Text { text: "Bluetooth"; Layout.alignment: Qt.AlignVCenter; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold } Item { Layout.fillWidth: true } Rectangle { Layout.alignment: Qt.AlignVCenter; width: 36; height: 16; radius: 8; color: colors.alpha(colors.tertiary,0.15); border.width:1; border.color: colors.alpha(colors.tertiary,0.4); Text { anchors.centerIn: parent; text: "ON"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold } } }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text { visible: btRepeater.count===0; text: "No Bluetooth devices"; color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                            Repeater {
                                id: btRepeater
                                model: root.btDevices.slice(0, 2)
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; height: 24; radius: 7
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
                                            color: modelData.connected?colors.tertiary:colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 10
                                        }
                                        Text { text: modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 8; Layout.fillWidth: true; elide: Text.ElideRight }
                                        Text { visible: modelData.bat!==""; text: modelData.bat; color: colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 7; Layout.preferredWidth: 28; horizontalAlignment: Text.AlignRight }
                                        Rectangle {
                                            Layout.preferredWidth: modelData.connected?62:52; Layout.preferredHeight: 18; radius: 9
                                            color: modelData.connected ? colors.alpha(colors.surface,0.6) : colors.alpha(colors.primary,0.14)
                                            border.width: 1; border.color: modelData.connected?colors.alpha(colors.outline,0.12):colors.alpha(colors.primary,0.35)
                                            Text { anchors.centerIn: parent; text: modelData.connected?"Connected":"Connect"; color: modelData.connected?colors.alpha(colors.outline,0.7):colors.primary; font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold }
                                            MouseArea { anchors.fill: parent; onClicked: root.toggleBt(index) }
                                        }
                                    }
                                }
                            }
                            Text { visible: root.btDevices.length > 2; text: "＋" + (root.btDevices.length - 2) + " more"; color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 6; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }

            // ── NETWORK ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 88
                radius: 16
                color: colors.alpha(colors.surface, 0.4)
                border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                clip: true
                RowLayout {
                    anchors.fill: parent; anchors.margins: 10
                    spacing: 12
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        radius: 10
                        color: colors.alpha(colors.surfaceVariant,0.25)
                        border.width: 1; border.color: colors.alpha(colors.outline,0.08)
                        Canvas {
                            id: wifiSpark
                            anchors.fill: parent
                            anchors.margins: 6
                            Connections {
                                target: netRate
                                function onRxHistoryChanged(){ wifiSpark.requestPaint() }
                                function onTxHistoryChanged(){ wifiSpark.requestPaint() }
                            }
                            onPaint: {
                                var ctx=getContext("2d")
                                var W=width, H=height
                                ctx.clearRect(0,0,W,H)
                                var rx=netRate.rxHistory, tx=netRate.txHistory
                                if(rx.length<2){
                                    ctx.strokeStyle=colors.alpha(colors.outline,0.12); ctx.lineWidth=1
                                    ctx.setLineDash([3,3]); ctx.beginPath(); ctx.moveTo(0,H/2); ctx.lineTo(W,H/2); ctx.stroke(); ctx.setLineDash([])
                                    return
                                }
                                function curve(h, stroke){
                                    var maxV=12; for(var i=0;i<h.length;i++) maxV=Math.max(maxV,h[i])
                                    var n=h.length
                                    var pts=[]
                                    for(var i=0;i<n;i++) pts.push({x:(i/(n-1))*W, y:H-2-(h[i]/maxV)*(H-8)})
                                    ctx.beginPath(); ctx.moveTo(pts[0].x,pts[0].y)
                                    for(var k=1;k<pts.length;k++){
                                        var cpx=(pts[k-1].x+pts[k].x)/2
                                        ctx.bezierCurveTo(cpx,pts[k-1].y,cpx,pts[k].y,pts[k].x,pts[k].y)
                                    }
                                    ctx.strokeStyle=stroke; ctx.lineWidth=2; ctx.lineJoin="round"; ctx.stroke()
                                    return pts
                                }
                                if(tx.length>=2) curve(tx, colors.alpha(colors.secondary,0.65))
                                var pts=curve(rx, colors.tertiary)
                                ctx.beginPath(); ctx.moveTo(pts[0].x,H)
                                ctx.lineTo(pts[0].x,pts[0].y)
                                for(var l=1;l<pts.length;l++){
                                    var cpx2=(pts[l-1].x+pts[l].x)/2
                                    ctx.bezierCurveTo(cpx2,pts[l-1].y,cpx2,pts[l].y,pts[l].x,pts[l].y)
                                }
                                ctx.lineTo(pts[pts.length-1].x,H); ctx.closePath()
                                var grad=ctx.createLinearGradient(0,0,0,H)
                                grad.addColorStop(0,colors.alpha(colors.tertiary,0.25))
                                grad.addColorStop(1,"transparent")
                                ctx.fillStyle=grad; ctx.fill()
                                ctx.beginPath(); ctx.arc(pts[pts.length-1].x,pts[pts.length-1].y,2.5,0,Math.PI*2)
                                ctx.fillStyle=colors.tertiary; ctx.fill()
                            }
                        }
                        Text { anchors.centerIn: parent; visible: netRate.rxHistory.length<2; text: "collecting…"; color: colors.alpha(colors.outline,0.45); font.family: colors.fontSans; font.pixelSize: 7 }
                    }
                    Rectangle { width: 1; height: parent.height - 20; color: colors.alpha(colors.outline,0.12) }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 2
                        Layout.alignment: Qt.AlignHCenter
                        RowLayout { spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle { width: 22; height: 22; radius: 11; color: colors.alpha(colors.primary,0.15); border.width:1; border.color: colors.alpha(colors.primary,0.3); Text { anchors.centerIn: parent; text: "󰇚"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10 } }
                            Text { text: netRate.fmt(netRate.rxKbs); Layout.alignment: Qt.AlignVCenter; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold }
                        }
                        Text { text: "DOWNLOAD"; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "today " + netRate.fmtTotal(netRate.totalRxMb); color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter }
                    }
                    Rectangle { width: 1; height: parent.height - 20; color: colors.alpha(colors.outline,0.12) }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 2
                        Layout.alignment: Qt.AlignHCenter
                        RowLayout { spacing: 6; Layout.alignment: Qt.AlignHCenter
                            Rectangle { width: 22; height: 22; radius: 11; color: colors.alpha(colors.secondary,0.15); border.width:1; border.color: colors.alpha(colors.secondary,0.3); Text { anchors.centerIn: parent; text: "󰕒"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 10 } }
                            Text { text: netRate.fmt(netRate.txKbs); Layout.alignment: Qt.AlignVCenter; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold }
                        }
                        Text { text: "UPLOAD"; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "today " + netRate.fmtTotal(netRate.totalTxMb); color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }

            // ── MIDDLE — Pet | Activity | Calendar ──
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 150
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 16
                    color: colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 3
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "PET — HORNET"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                            Item { Layout.fillWidth: true }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Rectangle {
                                anchors.centerIn: parent
                                width: 96; height: 96; radius: 48
                                color: colors.alpha(colors.primary, 0.05)
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 70; height: 70; radius: 35
                                    color: colors.alpha(colors.primary, 0.07)
                                }
                            }
                            Image {
                                id: alivePet
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -4
                                source: "file://" + root.petAssetsBase + (root.petCurrentFrames[root.petFrameIdx] || "shime1.png")
                                width: 90; height: 90
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
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                                width: 58; height: 6; radius: 3
                                color: colors.alpha(colors.background, 0.35)
                                border.width: 1; border.color: colors.alpha(colors.primary, 0.12)
                            }
                            MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["quickshell","-p", Quickshell.env("HOME")+"/.config/quickshell","ipc","call","pet","pet"]) }
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter; spacing: 5
                            Rectangle { width: 6; height: 6; radius: 3; color: colors.primary }
                            Text { text: "ALIVE"; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 6; font.weight: Font.Bold; font.letterSpacing: 1 }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 16
                    color: colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 5
                        Text { text: "ACTIVITY — 7 DAYS"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.55); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                        Text { text: "PEAK " + root.fmtDurShort(root.activityMax); Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.primary,0.75); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold }
                        RowLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 5
                            Repeater {
                                model: root.activityLast7
                                delegate: ColumnLayout {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true; Layout.fillHeight: true; spacing: 4
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                                        color: colors.alpha(colors.primary, 0.1)
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: {
                                                var s = modelData.secs || 0
                                                if (s <= 0) return 0
                                                return Math.max(4, parent.height * s / Math.max(1, root.activityMax))
                                            }
                                            radius: 6
                                            gradient: Gradient {
                                                GradientStop { position: 0; color: colors.alpha(colors.primary, 0.25) }
                                                GradientStop { position: 1; color: colors.primary }
                                            }
                                            opacity: modelData.today ? 1 : 0.8
                                            Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    Item {
                                        Layout.preferredHeight: 24
                                        Layout.fillWidth: true
                                        Text {
                                            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.dow
                                            color: modelData.today ? colors.primary : colors.alpha(colors.outline,0.6)
                                            font.family: colors.fontSans; font.pixelSize: 7; font.weight: modelData.today ? Font.Bold : Font.Normal
                                        }
                                        Text {
                                            anchors.top: parent.top; anchors.topMargin: 10; anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.fmtDurShort(modelData.secs || 0)
                                            color: modelData.today ? colors.primary : colors.alpha(colors.outline,0.55)
                                            font.family: colors.fontSans; font.pixelSize: 7; font.weight: modelData.today ? Font.Bold : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    radius: 16
                    color: colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.14)
                    clip: true
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: prevCalMa.containsMouse ? colors.alpha(colors.primary,0.2) : colors.alpha(colors.primary,0.08)
                                Text { anchors.centerIn: parent; text: "‹"; color: colors.primary; font.pixelSize: 12 }
                                MouseArea { id: prevCalMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.calOffset -= 1; root.rebuildCal() } }
                            }
                            Text { text: root.calTitle; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.ExtraBold; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: nextCalMa.containsMouse ? colors.alpha(colors.primary,0.2) : colors.alpha(colors.primary,0.08)
                                Text { anchors.centerIn: parent; text: "›"; color: colors.primary; font.pixelSize: 12 }
                                MouseArea { id: nextCalMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.calOffset += 1; root.rebuildCal() } }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { id: calClock; text: "--:--"; Layout.alignment: Qt.AlignVCenter; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 18; font.weight: Font.ExtraBold }
                            Text { id: calSecs; text: "--"; Layout.alignment: Qt.AlignBottom; Layout.bottomMargin: 3; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                            Item { Layout.fillWidth: true }
                            Text { id: calDate; text: "—"; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline,0.65); font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                            Timer {
                                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                                onTriggered: {
                                    var now = new Date()
                                    calClock.text = Qt.formatTime(now, "HH:mm")
                                    calSecs.text = Qt.formatTime(now, "ss")
                                    calDate.text = Qt.formatDate(now, "ddd d MMM")
                                }
                            }
                        }
                        GridLayout {
                            Layout.fillWidth: true; Layout.fillHeight: true; columns: 7; rowSpacing: 3; columnSpacing: 4
                            Repeater { model: ["M","T","W","T","F","S","S"]; Text { text: modelData; color: colors.alpha(colors.outline,0.5); font.family: colors.fontSans; font.pixelSize: 5; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter } }
                            Repeater {
                                model: root.calCells
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 14; radius: 6
                                    color: modelData.today ? colors.primary : "transparent"
                                    border.width: modelData.today ? 2 : 0
                                    border.color: modelData.today ? colors.alpha(colors.primary,0.5) : "transparent"
                                    Text { anchors.centerIn: parent; visible: modelData.d > 0; text: modelData.d; color: modelData.today ? colors.background : colors.alpha(colors.foreground,0.8); font.family: colors.fontSans; font.pixelSize: 8; font.weight: modelData.today ? Font.Bold : Font.Normal }
                                }
                            }
                        }
                    }
                }
            }


            Text {
                text: "Esc or SUPER ALT P to close  •  sliders/typing inside never closes  •  outside click does not close"
                color: colors.alpha(colors.outline, 0.38)
                font.family: colors.fontSans; font.pixelSize: 7; Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}