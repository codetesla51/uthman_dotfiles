import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.LocalStorage 2.0

// uthmanHabit — graph + 7-day list, Hyprland FloatingWindow, no hover clutter
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    title: "uthmanHabit"
    implicitWidth: 440
    implicitHeight: 440
    minimumSize: Qt.size(400, 380)
    maximumSize: Qt.size(500, 480)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "screentime"; function toggle(): void { root.open = !root.open } }

    function db() { return LocalStorage.openDatabaseSync("qs_screentime", "1.0", "screen time", 1000000) }
    function fmtDay(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function fmtDisplay(d) { return Qt.formatDate(d, "ddd MMM dd") }
    function fmtDur(secs) {
        if (secs <= 0) return "No activity"
        var m = Math.floor(secs / 60)
        if (m < 60) return m + " min"
        var h = Math.floor(m / 60)
        var rm = m % 60
        if (rm === 0) return h + "h"
        return h + "h " + rm + "m"
    }
    readonly property string today: fmtDay(new Date())

    function initDb() {
        db().transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS app_time(day TEXT, app TEXT, seconds INTEGER, PRIMARY KEY(day, app))")
            tx.executeSql("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        })
    }
    property var mem: ({})
    function sample() {
        var t = Hyprland.activeToplevel
        var cls = (t && t.class) ? t.class : "unknown"
        mem[cls] = (mem[cls] || 0) + 10
    }
    function flush() {
        var entries = []
        for (var k in mem) entries.push([today, k, mem[k]])
        mem = {}
        if (entries.length === 0) return
        db().transaction(function (tx) {
            for (var i = 0; i < entries.length; i++) {
                tx.executeSql("UPDATE app_time SET seconds = seconds + ? WHERE day=? AND app=?", [entries[i][2], entries[i][0], entries[i][1]])
                tx.executeSql("INSERT INTO app_time(day, app, seconds) SELECT ?, ?, ? WHERE (SELECT changes()) = 0", [entries[i][0], entries[i][1], entries[i][2]])
            }
        })
        if (root.open) loadAll()
    }

    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.sample() }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.flush() }
    Component.onCompleted: initDb()
    Component.onDestruction: flush()

    property var heatCells: []
    property var last7: []
    property int totalSecs: 0
    function unflushedToday() {
        var t = 0
        for (var k in mem) t += mem[k]
        return t
    }
    function loadAll() {
        var byDay = {}
        db().transaction(function (tx) {
            var rs = tx.executeSql("SELECT day, SUM(seconds) AS s FROM app_time GROUP BY day")
            for (var i = 0; i < rs.rows.length; i++) byDay[rs.rows.item(i).day] = rs.rows.item(i).s
        })
        byDay[today] = (byDay[today] || 0) + unflushedToday()
        var now = new Date()
        now.setHours(0,0,0,0)
        // 105-day heatmap
        var dow = (now.getDay() + 6) % 7
        var start = new Date(now); start.setDate(now.getDate() - (14 * 7 + dow))
        var cells = []
        for (var c = 0; c < 105; c++) {
            var d = new Date(start); d.setDate(start.getDate() + c)
            var ds = fmtDay(d)
            cells.push({ secs: (byDay[ds] || 0), future: d > now, dateStr: ds })
        }
        heatCells = cells
        // last 7 days list
        var days = []
        var total = 0
        for (var i = 6; i >= 0; i--) {
            var dd = new Date(now); dd.setDate(now.getDate() - i)
            var dds = fmtDay(dd)
            var secs = byDay[dds] || 0
            var fut = dd > now
            if (fut) continue
            days.push({ date: dd, dateStr: dds, display: fmtDisplay(dd), secs: secs, isToday: i === 0 })
            total += secs
        }
        last7 = days
        totalSecs = total
    }
    onOpenChanged: if (open) { flush(); loadAll() }

    function heatColor(secs, future) {
        if (future) return colors.alpha(colors.outline, 0.04)
        if (secs <= 0) return colors.alpha(colors.outline, 0.08)
        var m = secs / 60
        if (m < 15) return colors.alpha(colors.primary, 0.18)
        if (m < 60) return colors.alpha(colors.primary, 0.35)
        if (m < 120) return colors.alpha(colors.primary, 0.55)
        if (m < 240) return colors.alpha(colors.primary, 0.78)
        return colors.primary
    }
    function dotColor(secs) {
        if (secs <= 0) return colors.alpha(colors.outline, 0.25)
        var m = secs / 60
        if (m < 15) return colors.alpha(colors.primary, 0.45)
        if (m < 60) return colors.alpha(colors.primary, 0.65)
        if (m < 120) return colors.alpha(colors.primary, 0.85)
        return colors.primary
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.background, 0.96)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "UTHMAN HABIT"
                    color: colors.primary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.4
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            // graph — 105 cells, static, no hover
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 15*11 + 14*3
                Layout.preferredHeight: 7*11 + 6*3
                Grid {
                    anchors.fill: parent
                    columns: 15
                    rows: 7
                    columnSpacing: 3
                    rowSpacing: 3
                    Repeater {
                        model: 105
                        Rectangle {
                            required property int index
                            width: 11; height: 11
                            radius: 2
                            color: root.heatCells.length === 105 ? root.heatColor(root.heatCells[index].secs, root.heatCells[index].future) : colors.alpha(colors.outline, 0.06)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "Less"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                Row {
                    spacing: 3
                    Repeater {
                        model: [0, 10*60, 45*60, 90*60, 200*60]
                        Rectangle { width: 11; height: 11; radius: 2; color: root.heatColor(modelData, false) }
                    }
                }
                Text { text: "More"; color: colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                Item { Layout.fillWidth: true }
                Text { text: "Total " + root.fmtDur(root.totalSecs); color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Medium }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.10) }

            Text {
                text: "LAST 7 DAYS"
                color: colors.alpha(colors.outline, 0.55)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 8
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: root.last7
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 28
                        radius: 8
                        color: modelData.isToday ? colors.alpha(colors.primary, 0.10) : "transparent"
                        border.width: modelData.isToday ? 1 : 0
                        border.color: modelData.isToday ? colors.alpha(colors.primary, 0.18) : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            spacing: 10
                            Rectangle { width: 8; height: 8; radius: 4; color: root.dotColor(modelData.secs); Layout.alignment: Qt.AlignVCenter }
                            Text {
                                text: modelData.display
                                color: modelData.isToday ? colors.primary : colors.foreground
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
                                font.weight: modelData.isToday ? Font.Bold : Font.Medium
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.isToday ? "today" : ""
                                color: colors.alpha(colors.primary, 0.7)
                                font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold
                                visible: modelData.isToday
                            }
                            Text {
                                text: root.fmtDur(modelData.secs)
                                color: modelData.secs > 0 ? colors.foreground : colors.alpha(colors.outline, 0.55)
                                font.family:"FiraCode Nerd Font"; font.pixelSize: 10
                                font.weight: modelData.secs > 0 ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
            }
        }
    }
}
