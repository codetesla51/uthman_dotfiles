import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Pomodoro — standalone focus timer. Full cycle (focus / short / long break),
// adjustable durations, session dots, daily stats persisted to disk, critical
// notifications on every phase change. FloatingWindow, Amber Bento styling.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    // ── settings (persisted) ──
    property int workSecs: 25*60
    property int shortSecs: 5*60
    property int longSecs: 15*60
    property int longEvery: 4
    // ── runtime ──
    property string phase: "focus"      // focus | short | long
    property int seconds: workSecs
    property int total: workSecs
    property bool running: false
    property int setDone: 0             // focus sessions in the current set
    // ── daily stats (persisted) ──
    property string statDate: ""
    property int statSessions: 0
    property int statFocusSecs: 0
    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/quickshell/pomodoro.json"

    title: "Pomodoro"
    implicitWidth: 400
    implicitHeight: 540
    minimumSize: Qt.size(360, 480)
    maximumSize: Qt.size(460, 620)
    color: "transparent"
    visible: root.open

    IpcHandler {
        target: "pomodoro"
        function toggle(): void { root.open = !root.open }
        function close(): void { root.open = false }
    }

    onOpenChanged: if(open) Qt.callLater(function(){ bg.forceActiveFocus() })

    function todayStr(){ return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    function phaseSecs(p){ return p === "focus" ? root.workSecs : (p === "short" ? root.shortSecs : root.longSecs) }
    function phaseLabel(p){ return p === "focus" ? "FOCUS" : (p === "short" ? "SHORT BREAK" : "LONG BREAK") }
    function phaseAccent(p){ return p === "focus" ? colors.primary : (p === "short" ? colors.secondary : colors.tertiary) }

    function stateSave(){
        saveProc.command = ["sh","-c","mkdir -p '"+Quickshell.env("HOME")+"/.local/state/quickshell' && echo '"+Qt.btoa(JSON.stringify({work: root.workSecs, short: root.shortSecs, long: root.longSecs, every: root.longEvery, date: root.statDate, sessions: root.statSessions, focusSecs: root.statFocusSecs, phase: root.phase, seconds: root.seconds, running: root.running, savedAt: Date.now(), setDone: root.setDone}))+"' | base64 -d > '"+root.statePath+"'"]
        saveProc.running = true
    }
    function rollDay(){
        var t = root.todayStr()
        if(root.statDate !== t){ root.statDate = t; root.statSessions = 0; root.statFocusSecs = 0; root.stateSave() }
    }
    function fmtClock(s){
        var m = Math.floor(s / 60), r = s % 60
        return (m < 10 ? "0" + m : m) + ":" + (r < 10 ? "0" + r : r)
    }
    function fmtDur(s){
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        if(h > 0) return h + "h " + m + "m"
        return m + "m"
    }
    function setPhase(p){
        root.phase = p
        root.total = root.phaseSecs(p)
        root.seconds = root.total
        root.running = false
        root.stateSave()
    }
    function toggleRun(){
        if(root.seconds <= 0){ root.seconds = root.total }
        root.running = !root.running
        root.stateSave()
    }
    function bumpDur(k, d){
        if(k === "work") root.workSecs = Math.max(60, Math.min(120*60, root.workSecs + d))
        else if(k === "short") root.shortSecs = Math.max(60, Math.min(30*60, root.shortSecs + d))
        else root.longSecs = Math.max(60, Math.min(60*60, root.longSecs + d))
        var pk = k === "work" ? "focus" : k
        if(!root.running && root.phase === pk){ root.total = root.phaseSecs(pk); root.seconds = root.total }
        root.stateSave()
    }
    function skipPhase(){ root.finishPhase(true) }
    function finishPhase(skipped){
        var was = root.phase
        if(was === "focus" && !skipped){
            root.statSessions++
            root.statFocusSecs += root.total
            root.setDone++
            if(root.setDone >= root.longEvery) root.setDone = 0
            root.stateSave()
        }
        var next = "focus"
        if(was === "focus") next = (root.setDone === 0) ? "long" : "short"
        var msg = was === "focus"
            ? ("Focus done — " + (next === "long" ? "long break!" : "break time!"))
            : "Break over — back to focus!"
        if(!skipped) Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Pomodoro", "Pomodoro", msg])
        root.phase = next
        root.total = root.phaseSecs(next)
        root.seconds = root.total
        root.running = !skipped
        root.stateSave()
        if(!skipped) root.say(msg)
    }

    property int chomp: 0
    Timer { id: chompTimer; interval: 140; running: root.running; repeat: true; onTriggered: root.chomp++ }
    Timer { id: autoSave; interval: 10000; running: root.running; repeat: true; onTriggered: root.stateSave() }

    // transient status line
    property string statusMsg: ""
    function say(t){ root.statusMsg = t; statusLife.restart() }
    Timer { id: statusLife; interval: 4000; onTriggered: root.statusMsg = "" }

    Timer {
        id: tick
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            if(root.seconds > 0) root.seconds--
            if(root.seconds <= 0){ root.running = false; root.finishPhase(false) }
        }
    }

    Process { id: saveProc }
    FileView {
        id: stateView
        path: root.statePath
        printErrors: false
        onLoaded: {
            var d = null
            try { d = JSON.parse(text()) } catch(e) {}
            var runtimeOk = false
            if(d){
                if(d.work) root.workSecs = d.work
                if(d.short) root.shortSecs = d.short
                if(d.long) root.longSecs = d.long
                if(d.every) root.longEvery = d.every
                root.statDate = d.date || ""
                root.statSessions = d.sessions || 0
                root.statFocusSecs = d.focusSecs || 0
                root.rollDay()
                if(d.phase === "focus" || d.phase === "short" || d.phase === "long"){
                    root.phase = d.phase
                    if(typeof d.setDone === "number") root.setDone = Math.max(0, Math.min(root.longEvery - 1, d.setDone))
                    var rs = (typeof d.seconds === "number") ? Math.max(0, d.seconds) : -1
                    var wasRun = d.running === true
                    var elapsed = (typeof d.savedAt === "number") ? Math.max(0, Math.floor((Date.now() - d.savedAt) / 1000)) : 0
                    if(rs >= 0){
                        if(wasRun && root.phase === "focus") root.statFocusSecs += Math.min(elapsed, rs)
                        root.total = root.phaseSecs(root.phase)
                        root.seconds = Math.min(Math.max(0, rs - (wasRun ? elapsed : 0)), root.total)
                        root.running = wasRun && root.seconds > 0
                        if(wasRun && root.seconds <= 0) Qt.callLater(function(){ root.finishPhase(false) })
                        runtimeOk = true
                    }
                }
            } else {
                root.rollDay()
            }
            if(!runtimeOk){
                root.total = root.phaseSecs(root.phase)
                root.seconds = root.total
                root.running = false
            }
        }
        onLoadFailed: {
            root.rollDay()
            root.total = root.phaseSecs(root.phase)
            root.seconds = root.total
        }
    }

    // window glass
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        focus: true
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(e){
            if(e.key === Qt.Key_Space){ root.toggleRun(); e.accepted = true }
            else if(e.key === Qt.Key_R){ root.seconds = root.total; root.running = false; root.stateSave(); e.accepted = true }
            else if(e.key === Qt.Key_N){ root.skipPhase(); e.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // header — chip + label + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "POMODORO"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.open = false }
                }
            }

            // phase chips
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: [{k:"focus",t:"Focus"},{k:"short",t:"Short"},{k:"long",t:"Long"}]
                    Rectangle {
                        width: 96; height: 28; radius: 14
                        color: root.phase === modelData.k ? colors.alpha(root.phaseAccent(modelData.k), 0.2) : colors.alpha(colors.surface, 0.5)
                        border.width: 1; border.color: root.phase === modelData.k ? colors.alpha(root.phaseAccent(modelData.k), 0.45) : colors.alpha(colors.outline, 0.12)
                        Text { anchors.centerIn: parent; text: modelData.t; color: root.phase === modelData.k ? root.phaseAccent(modelData.k) : colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.setPhase(modelData.k) }
                    }
                }
            }

            // ring + clock
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 220
                Canvas {
                    id: ring
                    anchors.centerIn: parent
                    width: 200; height: 200
                    Connections { target: root; function onSecondsChanged(){ ring.requestPaint() } function onTotalChanged(){ ring.requestPaint() } function onChompChanged(){ ring.requestPaint() } function onPhaseChanged(){ ring.requestPaint() } }
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, 200, 200)
                        var frac = root.total > 0 ? 1 - root.seconds / root.total : 0
                        if(frac < 0) frac = 0
                        if(frac > 1) frac = 1
                        var N = 24, R = 84, i, a
                        ctx.fillStyle = colors.alpha(colors.tertiary, 0.55)
                        for(i = 0; i < N; i++){
                            if(i / N < frac) continue
                            a = -Math.PI / 2 + Math.PI * 2 * i / N
                            ctx.beginPath(); ctx.arc(100 + R * Math.cos(a), 100 + R * Math.sin(a), 2.5, 0, Math.PI * 2); ctx.fill()
                        }
                        var th = -Math.PI / 2 + Math.PI * 2 * frac
                        var px = 100 + R * Math.cos(th), py = 100 + R * Math.sin(th)
                        var dir = th + Math.PI / 2
                        var mouth = root.running ? (root.chomp % 2 === 0 ? 0.32 : 0.08) : 0.12
                        ctx.fillStyle = root.phaseAccent(root.phase)
                        ctx.beginPath(); ctx.moveTo(px, py); ctx.arc(px, py, 12, dir + mouth, dir - mouth + Math.PI * 2); ctx.closePath(); ctx.fill()
                        ctx.lineWidth = 2
                        ctx.strokeStyle = colors.alpha(colors.background, 0.6)
                        ctx.stroke()
                        ctx.fillStyle = colors.background
                        ctx.beginPath(); ctx.arc(px + Math.cos(dir - 0.5) * 5, py + Math.sin(dir - 0.5) * 5, 1.8, 0, Math.PI * 2); ctx.fill()
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Text { text: root.phaseLabel(root.phase); color: colors.alpha(root.phaseAccent(root.phase), 0.8); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignHCenter }
                    Text { text: root.fmtClock(root.seconds); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 42; font.weight: Font.ExtraBold; font.letterSpacing: 1; Layout.alignment: Qt.AlignHCenter }
                    Text { text: root.running ? "running" : (root.seconds < root.total ? "paused" : "ready"); color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8; Layout.alignment: Qt.AlignHCenter }
                }
            }

            // session dots
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: root.longEvery
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: index < root.setDone ? colors.primary : colors.alpha(colors.surfaceVariant, 0.5)
                        border.width: 1; border.color: index < root.setDone ? colors.primary : colors.alpha(colors.outline, 0.2)
                    }
                }
            }

            // controls
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Layout.alignment: Qt.AlignHCenter
                Rectangle {
                    width: 64; height: 36; radius: 18
                    color: ctlMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.5) : colors.alpha(colors.surface, 0.5)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "↺"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14 }
                    MouseArea { id: ctlMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.seconds = root.total; root.running = false; root.stateSave() } }
                }
                Rectangle {
                    width: 120; height: 44; radius: 22
                    color: goMa.containsMouse ? colors.primary : colors.alpha(colors.primary, 0.2)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.45)
                    Text { anchors.centerIn: parent; text: root.running ? "Pause" : "Start"; color: goMa.containsMouse ? colors.background : colors.primary; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold }
                    MouseArea { id: goMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.toggleRun() }
                }
                Rectangle {
                    width: 64; height: 36; radius: 18
                    color: skipMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.5) : colors.alpha(colors.surface, 0.5)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.15)
                    Text { anchors.centerIn: parent; text: "»"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14 }
                    MouseArea { id: skipMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.skipPhase() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // durations
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: [{k:"work", t:"Focus"},{k:"short", t:"Short break"},{k:"long", t:"Long break"}]
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text { text: modelData.t; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; Layout.fillWidth: true }
                        Rectangle {
                            width: 26; height: 24; radius: 12
                            color: decMa.containsMouse ? colors.alpha(colors.primary, 0.22) : colors.alpha(colors.surface, 0.5)
                            Text { anchors.centerIn: parent; text: "−"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.Bold }
                            MouseArea { id: decMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.bumpDur(modelData.k, -60) }
                        }
                        Text { text: Math.round((modelData.k === "work" ? root.workSecs : (modelData.k === "short" ? root.shortSecs : root.longSecs)) / 60) + "m"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.ExtraBold; Layout.preferredWidth: 34; horizontalAlignment: Text.AlignHCenter }
                        Rectangle {
                            width: 26; height: 24; radius: 12
                            color: incMa.containsMouse ? colors.alpha(colors.primary, 0.22) : colors.alpha(colors.surface, 0.5)
                            Text { anchors.centerIn: parent; text: "+"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.Bold }
                            MouseArea { id: incMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.bumpDur(modelData.k, 60) }
                        }
                    }
                }
            }

            // today stats + status
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: root.statSessions + " sessions · " + root.fmtDur(root.statFocusSecs) + " focus today"
                color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 8
            }
            Text {
                visible: root.statusMsg !== ""
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: root.statusMsg
                color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: "space start/pause · R reset · N skip · Esc close"
                color: colors.alpha(colors.outline, 0.45); font.family: colors.fontSans; font.pixelSize: 7; font.letterSpacing: 0.3
            }
        }
    }
}
