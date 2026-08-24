import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// Calendar — shows below the clock on hover. Beautiful month grid + reminders + timer/pomodoro.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property date selectedDate: new Date()
    property date currentMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)

    // timer/pomodoro state — pacman style
    property int timerSeconds: 0
    property int timerTotal: 0
    property int pomodoroWork: 25*60
    property int pomodoroBreak: 5*60
    property bool pomodoroMode: false
    property bool pomodoroIsBreak: false
    property int pomodoroCycles: 0
    property bool timerRunning: false
    property real pacmanMouth: 0.25
    Timer { id: pacmanAnim; interval: 120; running: root.timerRunning; repeat: true; onTriggered: root.pacmanMouth = root.pacmanMouth===0.25?0.05:0.25 }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true

    function fmtDate(d){ return Qt.formatDate(d, "yyyy-MM-dd") }

    // LocalStorage for reminders
    function db(){ return LocalStorage.openDatabaseSync("qs_calendar","1.0","reminders",100000) }
    property var reminders: [] // {id, date, text}
    function loadReminders(){
        var d=db(); d.transaction(function(tx){
            tx.executeSql('CREATE TABLE IF NOT EXISTS reminders(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, text TEXT)')
            var rs=tx.executeSql('SELECT * FROM reminders ORDER BY id DESC'); var arr=[]
            for(var i=0;i<rs.rows.length;i++) arr.push(rs.rows.item(i))
            reminders=arr
        })
    }
    function addReminder(dateStr, txt){
        if(!txt.trim()) return
        var d=db(); d.transaction(function(tx){ tx.executeSql('INSERT INTO reminders(date,text) VALUES(?,?)',[dateStr,txt]) })
        loadReminders()
    }
    function delReminder(id){
        var d=db(); d.transaction(function(tx){ tx.executeSql('DELETE FROM reminders WHERE id=?',[id]) })
        loadReminders()
    }
    Component.onCompleted: loadReminders()

    Timer {
        id: tick
        interval: 1000; running: root.timerRunning; repeat: true
        onTriggered: {
            if (root.timerSeconds>0) root.timerSeconds--
            else {
                root.timerRunning=false
                // alert — system notification + sound
                if (root.pomodoroMode) {
                    var msg = root.pomodoroIsBreak ? "Break over — back to focus!" : "Focus done — break time!"
                    Quickshell.execDetached(["notify-send", "-u", "critical", "-i", "alarm", "Pomodoro", msg])
                    Quickshell.execDetached(["sh","-c","paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga 2>/dev/null || true"])
                    if (!root.pomodoroIsBreak) { root.pomodoroIsBreak=true; root.timerSeconds=root.pomodoroBreak; root.timerTotal=root.pomodoroBreak; root.timerRunning=true }
                    else { root.pomodoroIsBreak=false; root.pomodoroCycles++; root.timerSeconds=root.pomodoroWork; root.timerTotal=root.pomodoroWork; }
                } else {
                    Quickshell.execDetached(["notify-send", "-u", "critical", "-i", "alarm", "Timer", "Time's up!"])
                    Quickshell.execDetached(["sh","-c","paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null || true"])
                }
            }
        }
    }
    function fmtTime(s){ var m=Math.floor(s/60), sec=s%60; return (m<10?"0"+m:m)+":"+(sec<10?"0"+sec:sec) }

    signal closeRequested()
    property bool hovered: hoverBridge.containsMouse || calHover.containsMouse

    // backdrop — click outside to close pinned
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.12 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
    }

    IpcHandler { target: "calendar"; function toggle(): void { root.open = !root.open } }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 520
        height: Math.min(640, col.implicitHeight + 28)
        radius: 20
        color: colors.alpha(colors.background, 0.96)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.25)
        implicitHeight: col.implicitHeight + 28

        MouseArea {
            id: calHover
            anchors.fill: parent
            hoverEnabled: true
        }
        // top-most hover bridge — catches hover even over child MouseAreas
        MouseArea {
            id: hoverBridge
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true
        }

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            spacing: 10

            // header: month / nav
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: prevMa.containsMouse ? colors.alpha(colors.primary,0.15) : "transparent"
                    Text { anchors.centerIn: parent; text: "‹"; color: colors.primary; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.currentMonth = new Date(root.currentMonth.getFullYear(), root.currentMonth.getMonth()-1, 1) }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(root.currentMonth, "MMMM yyyy")
                    color: colors.secondary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.ExtraBold
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: nextMa.containsMouse ? colors.alpha(colors.primary,0.15) : "transparent"
                    Text { anchors.centerIn: parent; text: "›"; color: colors.primary; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.currentMonth = new Date(root.currentMonth.getFullYear(), root.currentMonth.getMonth()+1, 1) }
                }
                Rectangle {
                    width: 52; height: 24; radius: 12
                    color: todayMa.containsMouse ? colors.alpha(colors.primary,0.15) : colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: colors.alpha(colors.primary,0.3)
                    Text { anchors.centerIn: parent; text: "Today"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.DemiBold }
                    MouseArea { id: todayMa; anchors.fill: parent; hoverEnabled:true; onClicked: { root.currentMonth=new Date(new Date().getFullYear(), new Date().getMonth(),1); root.selectedDate=new Date() } }
                }
            }

            // weekdays
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                    delegate: Text {
                        required property var modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: colors.tertiary
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                    }
                }
            }

            // days grid — 6x7
            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 4
                columnSpacing: 4
                Repeater {
                    model: 42
                    delegate: Rectangle {
                        required property int index
                        property date d: {
                            var first = new Date(root.currentMonth.getFullYear(), root.currentMonth.getMonth(), 1)
                            var startDay = (first.getDay()+6)%7 // Monday=0
                            var day = new Date(first); day.setDate(1 - startDay + index)
                            return day
                        }
                        property bool isCurrentMonth: d.getMonth() === root.currentMonth.getMonth()
                        property bool isToday: fmtDate(d) === fmtDate(new Date())
                        property bool isSelected: fmtDate(d) === fmtDate(root.selectedDate)
                        property bool hasReminder: {
                            for(var i=0;i<root.reminders.length;i++) if(root.reminders[i].date===fmtDate(d)) return true
                            return false
                        }
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: 8
                        color: isSelected ? colors.primary : isToday ? colors.alpha(colors.primary,0.18) : maCal.containsMouse ? colors.alpha(colors.surfaceVariant,0.3) : "transparent"
                        border.width: isToday && !isSelected ? 1 : 0
                        border.color: colors.alpha(colors.primary,0.5)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                text: d.getDate()
                                color: isSelected ? colors.background : isCurrentMonth ? colors.foreground : colors.alpha(colors.outline,0.4)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
                                font.weight: isSelected||isToday ? Font.DemiBold : Font.Medium
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Rectangle {
                                visible: hasReminder
                                width: 4; height: 4; radius: 2
                                color: isSelected ? colors.background : colors.primary
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                        MouseArea {
                            id: maCal
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.selectedDate = d
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline,0.15) }

            // reminders for selected date
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "Reminders — " + Qt.formatDate(root.selectedDate, "dd MMM")
                    color: colors.secondary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                }
                Text {
                    visible: root.reminders.filter(function(r){return r.date===fmtDate(root.selectedDate)}).length>0
                    text: root.reminders.filter(function(r){return r.date===fmtDate(root.selectedDate)}).length + ""
                    color: colors.tertiary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: root.reminders.filter(function(r){return r.date===fmtDate(root.selectedDate)})
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 32
                        radius: 8
                        color: colors.alpha(colors.surface,0.5)
                        border.width: 1; border.color: colors.alpha(colors.outline,0.12)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                text: modelData.text
                                color: colors.foreground
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "󰅖"
                                color: delMa.containsMouse ? colors.error : colors.alpha(colors.outline,0.6)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
                                MouseArea { id: delMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.delReminder(modelData.id) }
                            }
                        }
                    }
                }
                Text {
                    visible: root.reminders.filter(function(r){return r.date===fmtDate(root.selectedDate)}).length===0
                    text: "No reminders"
                    color: colors.alpha(colors.outline,0.5)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                TextField {
                    id: remInput
                    Layout.fillWidth: true
                    implicitHeight: 36
                    topPadding: 8
                    bottomPadding: 8
                    leftPadding: 12
                    rightPadding: 12
                    placeholderText: "●  Add reminder…"
                    placeholderTextColor: colors.alpha(colors.primary,0.6)
                    color: colors.foreground
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    background: Rectangle {
                        radius: 10
                        color: colors.alpha(colors.surface, 0.75)
                        border.width: 1
                        border.color: remInput.activeFocus ? colors.alpha(colors.primary,0.45) : colors.alpha(colors.outline,0.18)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                    onAccepted: { root.addReminder(fmtDate(root.selectedDate), text); text="" }
                }
                Rectangle {
                    width: 56; height: 28; radius: 8
                    color: remInput.text.trim().length>0 ? colors.alpha(colors.primary,0.2) : colors.alpha(colors.surfaceVariant,0.3)
                    Text { anchors.centerIn: parent; text: "Add"; color: remInput.text.trim().length>0?colors.primary:colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize:10; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: { root.addReminder(fmtDate(root.selectedDate), remInput.text); remInput.text="" } }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline,0.15) }

            // ── PACMAN TIMER ──
            Rectangle {
                Layout.fillWidth: true
                height: 132
                radius: 14
                color: colors.alpha(colors.surface, 0.55)
                border.width: 1; border.color: colors.alpha(colors.primary,0.25)

                // subtle dot grid background
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // pacman canvas — circular track with eating dots
                    Item {
                        width: 64; height: 64
                        Canvas {
                            id: pacCanvas
                            anchors.fill: parent
                            property real progress: root.timerTotal>0 ? 1 - root.timerSeconds/root.timerTotal : 0
                            onProgressChanged: requestPaint()
                            Connections { target: root; function onTimerSecondsChanged() { pacCanvas.requestPaint() } }
                            Connections { target: root; function onPacmanMouthChanged() { pacCanvas.requestPaint() } }
                            onPaint: {
                                var ctx=getContext("2d"); ctx.reset()
                                var cx=width/2, cy=height/2, r=26
                                // track
                                ctx.beginPath(); ctx.arc(cx,cy,r,0,Math.PI*2); ctx.strokeStyle=colors.alpha(colors.outline,0.15); ctx.lineWidth=3; ctx.stroke()
                                // progress dots — 24 dots around circle, eaten as pacman moves
                                var dots=24; var prog=pacCanvas.progress
                                for(var i=0;i<dots;i++){
                                    var a=(i/dots)*Math.PI*2 - Math.PI/2
                                    var eaten = (i/dots) < prog
                                    if(eaten) continue
                                    var x=cx+Math.cos(a)*r, y=cy+Math.sin(a)*r
                                    ctx.beginPath(); ctx.arc(x,y,2.2,0,Math.PI*2)
                                    ctx.fillStyle=colors.primary
                                    ctx.fill()
                                }
                                // pacman
                                var pa = prog*Math.PI*2 - Math.PI/2
                                var dir = pa + Math.PI/2
                                var px=cx+Math.cos(pa)*r, py=cy+Math.sin(pa)*r
                                var mouth=root.pacmanMouth
                                ctx.beginPath()
                                ctx.moveTo(px,py)
                                ctx.arc(px,py,7, dir+mouth*Math.PI, dir+(2-mouth)*Math.PI)
                                ctx.closePath()
                                ctx.fillStyle=colors.primary
                                ctx.fill()
                                // eye
                                var ex=px+Math.cos(pa)*2, ey=py+Math.sin(pa)*2
                                ctx.beginPath(); ctx.arc(ex,ey,1.2,0,Math.PI*2); ctx.fillStyle=colors.background; ctx.fill()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: root.pomodoroMode ? (root.pomodoroIsBreak ? "BREAK" : "FOCUS") + " · " + (root.pomodoroCycles+1) : "TIMER"
                                color: root.pomodoroMode ? colors.primary : colors.alpha(colors.outline,0.7)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                                font.letterSpacing: 1.4
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                width: 6; height: 6; radius: 3
                                color: root.timerRunning ? colors.primary : colors.alpha(colors.outline,0.2)
                                SequentialAnimation on opacity { running: root.timerRunning; loops: Animation.Infinite; NumberAnimation { from:1; to:0.3; duration:600 } NumberAnimation { from:0.3; to:1; duration:600 } }
                            }
                        }
                        Text {
                            text: fmtTime(root.timerSeconds)
                            color: colors.foreground
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 28
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1
                        }
                        RowLayout {
                            spacing: 6
                            Rectangle {
                                width: 68; height: 28; radius: 8
                                color: root.timerRunning ? colors.alpha(colors.error,0.9) : colors.primary
                                Text { anchors.centerIn: parent; text: root.timerRunning?"PAUSE":"START"; color: root.timerRunning?colors.background:colors.background; font.family:"FiraCode Nerd Font"; font.pixelSize:10; font.weight:Font.ExtraBold }
                                MouseArea { anchors.fill: parent; onClicked: root.timerRunning=!root.timerRunning }
                            }
                            Rectangle {
                                width: 48; height: 28; radius: 8
                                color: colors.alpha(colors.surface,0.5)
                                Text { anchors.centerIn: parent; text: "RESET"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize:9; font.weight:Font.Bold }
                                MouseArea { anchors.fill: parent; onClicked: { root.timerRunning=false; root.timerSeconds=root.timerTotal>0?root.timerTotal: (root.pomodoroMode?root.pomodoroWork:0) } }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.timerTotal>0 ? Math.round((1-root.timerSeconds/root.timerTotal)*100)+"%" : "0%"
                                color: colors.alpha(colors.outline,0.6)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                        RowLayout {
                            spacing: 5
                            Repeater {
                                model: [5*60,10*60,25*60]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 42; height: 22; radius: 8
                                    color: root.timerTotal===modelData && !root.pomodoroMode ? colors.primary : colors.alpha(colors.surface,0.6)
                                    Text { anchors.centerIn: parent; text: (modelData/60)+"m"; color: root.timerTotal===modelData && !root.pomodoroMode ? colors.background : colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize:9; font.weight:Font.DemiBold }
                                    MouseArea { anchors.fill: parent; onClicked: { root.pomodoroMode=false; root.timerSeconds=modelData; root.timerTotal=modelData } }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 22; radius: 8
                                color: root.pomodoroMode ? colors.primary : colors.alpha(colors.surface,0.6)
                                Text { anchors.centerIn: parent; text: "POMO 25/5"; color: root.pomodoroMode ? colors.background : colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize:8; font.weight:Font.Bold }
                                MouseArea { anchors.fill: parent; onClicked: { root.pomodoroMode=!root.pomodoroMode; if(root.pomodoroMode){ root.timerSeconds=root.pomodoroWork; root.timerTotal=root.pomodoroWork; root.pomodoroIsBreak=false } } }
                            }
                        }
                    }
                }
            }
        }
    }
}
