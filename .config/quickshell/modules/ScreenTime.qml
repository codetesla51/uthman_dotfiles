import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.LocalStorage 2.0

// uthmanHabit — GitHub-style activity graph. Layer overlay, NOT a Hyprland window.
// Samples focused Hydrland-free: focused window every 10s → SQLite. ipc call screentime.
PanelWindow {
    id: root

    property var colors
    property bool open: false

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true

    IpcHandler { target: "screentime"; function toggle(): void { root.open = !root.open } }

    // ---------- storage + sampling ----------
    function db() { return LocalStorage.openDatabaseSync("qs_screentime", "1.0", "screen time", 1000000) }
    function fmtDay(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
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

    // ---------- graph data ----------
    property var heatCells: []
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
        var dow = (now.getDay() + 6) % 7                       // Mon=0
        var start = new Date(now); start.setDate(now.getDate() - (14 * 7 + dow))
        var cells = []
        for (var c = 0; c < 105; c++) {
            var d = new Date(start); d.setDate(start.getDate() + c)
            cells.push({ secs: (byDay[fmtDay(d)] || 0), future: d > now })
        }
        heatCells = cells
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

    // ---------- UI ----------
    // dim backdrop — click outside to close (single-window pattern)
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.30 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 290
        height: 240
        radius: 18
        color: colors.alpha(colors.background, 0.92)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "UTHMAN HABIT"
                color: colors.primary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                font.weight: Font.ExtraBold
                font.letterSpacing: 1.5
                Layout.alignment: Qt.AlignHCenter
            }

            Grid {
                Layout.alignment: Qt.AlignHCenter
                columns: 15
                rows: 7
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: 105
                    Rectangle {
                        required property int index
                        width: 13; height: 13
                        radius: 3
                        color: root.heatCells.length === 105
                               ? root.heatColor(root.heatCells[index].secs, root.heatCells[index].future)
                               : colors.alpha(colors.outline, 0.06)
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
