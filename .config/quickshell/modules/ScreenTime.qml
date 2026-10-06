import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// uthmanHabit — graph + 7-day list, Hyprland FloatingWindow, no hover clutter
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    // system sans (fontconfig default) — FiraCode everywhere read like a
    // terminal, and the mock this ports was set in a grotesk
    property string fontUi: "JetBrainsMono Nerd Font Mono"
    title: "uthmanHabit"
    implicitWidth: 700
    implicitHeight: 660
    // pinned like Monitors: a min/max range lets the window land off-spec
    // and clip the content. Rule pins the same 700x660.
    minimumSize: Qt.size(700, 660)
    maximumSize: Qt.size(700, 660)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here — Bar.qml owns target "screentime" and lazy-loads this.

    // data comes from the `screentime` backend (Go daemon): `screentime --export all`
    // -> { cells[105]{secs,future}, last7[]{display,secs,today}, total_secs }
    function fmtDur(secs) {
        if (secs <= 0) return "No activity"
        var m = Math.floor(secs / 60)
        if (m < 60) return m + " min"
        var h = Math.floor(m / 60)
        var rm = m % 60
        if (rm === 0) return h + "h"
        return h + "h " + rm + "m"
    }

    property var heatCells: []
    property var last7: []
    property int totalSecs: 0
    property var todayApps: []   // [{name, secs}] sorted desc
    property int todaySecs: 0
    property real todayScore: 0
    readonly property int topSecs: todayApps.length ? todayApps[0].secs : 0
    property int stripHi: -1
    property int chartHi: -1
    readonly property int weekMax: {
        var m = 1
        for (var i = 0; i < last7.length; i++) if (last7[i].secs > m) m = last7[i].secs
        return m
    }
    function mixc(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }
    // six distinct hues derived from the theme (categorical data needs real
    // separation; fixed hex would freeze one wallpaper's palette forever)
    function appColor(i) {
        var c = [colors.primary, colors.secondary, colors.tertiary,
                 colors.error, root.mixc(colors.primary, colors.tertiary, 0.5),
                 root.mixc(colors.secondary, colors.error, 0.5)]
        return c[i % 6]
    }
    readonly property real avgDay: {
        if (!last7.length) return 0
        var t = 0
        for (var i = 0; i < last7.length; i++) t += last7[i].secs
        return t / last7.length
    }
    readonly property int todayH: Math.floor(root.todaySecs / 3600)
    readonly property int todayM: Math.floor(root.todaySecs % 3600 / 60)
    readonly property int yesterdaySecs: last7.length >= 7 ? last7[5].secs : 0

    Process {
        id: fetcher
        command: ["screentime", "--export", "all"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(text) } catch (e) { j = null }
                if (!j) { root.heatCells = []; root.last7 = []; root.totalSecs = 0; return }
                root.heatCells = j.cells || []
                root.totalSecs = j.total_secs || 0
                var days = []
                var src = j.last7 || []
                for (var i = 0; i < src.length; i++) {
                    days.push({ display: src[i].display, secs: src[i].secs || 0, isToday: !!src[i].today })
                }
                root.last7 = days
            }
        }
    }
    Process {
        id: appFetcher
        command: ["screentime", "--export", "today"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var j = null
                try { j = JSON.parse(text) } catch (e) { j = null }
                if (!j || !j.by_app) { root.todayApps = []; root.todaySecs = 0; root.todayScore = 0; return }
                var arr = []
                for (var k in j.by_app) arr.push({ name: k, secs: j.by_app[k] || 0 })
                arr.sort(function(a, b){ return b.secs - a.secs })
                root.todayApps = arr.slice(0, 6)
                root.todaySecs = j.total_secs || 0
                root.todayScore = j.weighted_score || 0
            }
        }
    }
    onOpenChanged: { if (open) { fetcher.running = true; appFetcher.running = true; openAnim.restart() } else closeAnim.restart() }


    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        // bezier pair — open pops with overshoot bounce, close hurries out
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "SCREEN TIME"
                    color: colors.primary
                    font.family: fontUi
                    font.pixelSize: 11
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.4
                    Layout.fillWidth: true
                }
                Text {
                    text: root.fmtDur(root.todaySecs) + " today"
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: fontUi
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
                            }

            // hero — giant today total + yesterday delta + focus score
            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { visible: root.todayH > 0; text: root.todayH; color: colors.foreground; font.family: "Iceland"; font.pixelSize: 118; lineHeight: 0.8 }
                Text { visible: root.todayH > 0; text: "h"; color: colors.alpha(colors.outline, 0.7); font.family: "Iceland"; font.pixelSize: 44; Layout.alignment: Qt.AlignBaseline; Layout.leftMargin: 4; Layout.rightMargin: 10 }
                Text { text: root.todayM; color: colors.foreground; font.family: "Iceland"; font.pixelSize: 118; lineHeight: 0.8 }
                Text { text: "m"; color: colors.alpha(colors.outline, 0.7); font.family: "Iceland"; font.pixelSize: 44; Layout.alignment: Qt.AlignBaseline; Layout.leftMargin: 4 }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: root.fmtDur(Math.abs(root.todaySecs - root.yesterdaySecs)); color: colors.foreground; font.family: fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text { text: (root.todaySecs - root.yesterdaySecs) <= 0 ? "less" : "more"; color: colors.alpha(colors.outline, 0.7); font.family: fontUi; font.pixelSize: 13 }
                Text { text: "than yesterday  ·  focus score"; color: colors.alpha(colors.outline, 0.7); font.family: fontUi; font.pixelSize: 13 }
                Text { visible: root.todayScore > 0; text: root.todayScore.toFixed(1); color: colors.foreground; font.family: fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
            }

            // proportional strip — explicit geometry from data only. No layout
            // interplay, no entrance animation: nothing here can drift or grow.
            Item {
                id: stripBox
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                function segW(i) {
                    if (root.todaySecs <= 0 || i >= root.todayApps.length) return 6
                    var avail = stripBox.width - 3 * (root.todayApps.length - 1)
                    return Math.max(6, avail * root.todayApps[i].secs / root.todaySecs)
                }
                function segX(i) {
                    var x = 0
                    for (var k = 0; k < i; k++) x += segW(k) + 3
                    return x
                }
                Repeater {
                    model: root.todayApps
                    Rectangle {
                        required property var modelData
                        required property int index
                        x: stripBox.segX(index)
                        y: 0
                        width: stripBox.segW(index)
                        height: 52
                        radius: 7
                        clip: true
                        color: root.appColor(index)
                        opacity: root.stripHi === -1 || root.stripHi === index ? 1 : 0.25
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        Text {
                            visible: root.todaySecs > 0 && modelData.secs / root.todaySecs > 0.14
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1)
                            color: colors.background
                            font.family: fontUi; font.pixelSize: 13; font.weight: Font.Bold
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.stripHi = index; onExited: root.stripHi = -1 }
                    }
                }
            }

            // legend — 2-col grid, hovering highlights the strip segment
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 22
                rowSpacing: 2
                Repeater {
                    model: root.todayApps
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 28
                        color: "transparent"
                        RowLayout {
                            anchors.fill: parent
                            spacing: 9
                            Rectangle { width: 9; height: 9; radius: 3; color: root.appColor(index); Layout.alignment: Qt.AlignVCenter }
                            Text {
                                text: modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1)
                                color: colors.foreground
                                font.family: fontUi; font.pixelSize: 14
                                font.weight: root.stripHi === index ? Font.Bold : Font.Normal
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.secs <= 0 ? "0m" : root.fmtDur(modelData.secs)
                                color: colors.alpha(colors.outline, 0.7)
                                font.family: fontUi; font.pixelSize: 13
                                Layout.rightMargin: 24
                            }
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: root.stripHi = index; onExited: root.stripHi = -1 }
                    }
                }
            }

            Text {
                text: "Past 7 days"
                color: colors.foreground
                font.family: fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Averaging " + (root.avgDay <= 0 ? "nothing" : root.fmtDur(root.avgDay)) + " a day"
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: fontUi
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: root.last7.length ? root.fmtDur(root.last7[root.last7.length - 1].secs) + " today" : ""
                    color: colors.foreground
                    font.family: fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
            // week chart — shapes only, exactly like the wifi sparkline:
            // reset(), direct QColor styles, no clip/gradient/dash/canvas-text.
            // Labels live in QML below so a paint failure can't take them too.
            Item {
                id: tipBox
                Layout.fillWidth: true
                Layout.preferredHeight: 110
                readonly property real tipX: 6 + root.chartHi * ((width - 12) / 6)
                readonly property real tipY: (110 - 8) - ((root.chartHi >= 0 && root.chartHi < root.last7.length ? root.last7[root.chartHi].secs : 0) / root.weekMax) * (110 - 16)
                Canvas {
                id: weekChart
                anchors.fill: parent
                Connections { target: root; function onLast7Changed() { weekChart.requestPaint() } function onChartHiChanged() { weekChart.requestPaint() } }
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var days = root.last7
                    if (!days.length) return
                    var mx = root.weekMax
                    var pad = 6
                    function X(i) { return pad + i * ((width - pad * 2) / 6) }
                    function Y(v) { return (height - 8) - (v / mx) * (height - 16) }
                    var acc = root.appColor(2)
                    // area fill under the smooth curve
                    ctx.beginPath()
                    ctx.moveTo(X(0), Y(days[0].secs))
                    for (var sgm = 1; sgm < days.length; sgm++) {
                        var cx = (X(sgm - 1) + X(sgm)) / 2
                        ctx.bezierCurveTo(cx, Y(days[sgm - 1].secs), cx, Y(days[sgm].secs), X(sgm), Y(days[sgm].secs))
                    }
                    ctx.lineTo(X(days.length - 1), height)
                    ctx.lineTo(X(0), height)
                    ctx.closePath()
                    ctx.fillStyle = colors.alpha(acc, 0.14)
                    ctx.fill()
                    // average hairline (solid — no dash games)
                    ctx.beginPath()
                    ctx.moveTo(0, Y(root.avgDay))
                    ctx.lineTo(width, Y(root.avgDay))
                    ctx.strokeStyle = colors.alpha(colors.outline, 0.5)
                    ctx.lineWidth = 1
                    ctx.stroke()
                    // the curve itself
                    ctx.beginPath()
                    ctx.moveTo(X(0), Y(days[0].secs))
                    for (var sgm2 = 1; sgm2 < days.length; sgm2++) {
                        var cx2 = (X(sgm2 - 1) + X(sgm2)) / 2
                        ctx.bezierCurveTo(cx2, Y(days[sgm2 - 1].secs), cx2, Y(days[sgm2].secs), X(sgm2), Y(days[sgm2].secs))
                    }
                    ctx.strokeStyle = acc
                    ctx.lineWidth = 2.5
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.stroke()
                    // hovered-day guide + dot (or today when nothing hovered)
                    var hi = root.chartHi >= 0 && root.chartHi < days.length ? root.chartHi : days.length - 1
                    ctx.beginPath()
                    ctx.moveTo(X(hi), 0)
                    ctx.lineTo(X(hi), height)
                    ctx.strokeStyle = colors.alpha(colors.outline, hi === days.length - 1 ? 0 : 0.35)
                    ctx.lineWidth = 1
                    ctx.stroke()
                    // today dot: halo + core
                    var tx = X(hi), ty = Y(days[hi].secs)
                    ctx.beginPath()
                    ctx.arc(tx, ty, 9, 0, 2 * Math.PI)
                    ctx.fillStyle = colors.alpha(acc, 0.2)
                    ctx.fill()
                    ctx.beginPath()
                    ctx.arc(tx, ty, 4.5, 0, 2 * Math.PI)
                    ctx.fillStyle = acc
                    ctx.fill()
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: function(m) {
                        var i = Math.round((m.x - 6) / ((width - 12) / 6))
                        root.chartHi = Math.max(0, Math.min(6, i))
                    }
                    onExited: root.chartHi = -1
                }
                Rectangle {
                    visible: root.chartHi >= 0 && root.chartHi < root.last7.length
                    width: 100; height: 46; radius: 10
                    x: Math.min(Math.max(tipBox.tipX - 50, 2), Math.max(2, tipBox.width - 102))
                    y: Math.min(Math.max(tipBox.tipY - 54, 2), 110 - 48)
                    color: colors.alpha(colors.surface, 0.94)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.25)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        Text {
                            text: { if (root.chartHi < 0 || root.chartHi >= root.last7.length) return ""; var p = String(root.last7[root.chartHi].display).split(" "); return (p[0] + " " + (p[2] || "")).trim() }
                            color: colors.foreground
                            font.family: fontUi; font.pixelSize: 11; font.weight: Font.Bold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: { if (root.chartHi < 0 || root.chartHi >= root.last7.length) return ""; var v = root.last7[root.chartHi].secs; return v <= 0 ? "0m" : root.fmtDur(v) }
                            color: colors.tertiary
                            font.family: fontUi; font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: root.last7
                    Text {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: { var p = String(modelData.display).split(" "); return (p[0] + " " + (p[2] || "")).trim() }
                        color: index === root.last7.length - 1 ? colors.foreground : colors.alpha(colors.outline, 0.7)
                        font.family: fontUi; font.pixelSize: 11
                        font.weight: index === root.last7.length - 1 ? Font.Bold : Font.Normal
                        elide: Text.ElideRight
                    }
                }
            }

        }
    }
}
