import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ClockWindow — small glass CARD on bar-clock click.
// FloatingWindow centered popup, Amber Bento tokens only.
FloatingWindow {
    id: root

    property var colors
    property bool open: false

    title: "Clock"
    implicitWidth: 360
    implicitHeight: 408
    minimumSize: Qt.size(360, 408)
    maximumSize: Qt.size(360, 408)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here — Bar.qml owns target "clockwin" and lazy-loads this.

    onOpenChanged: { if (open) openAnim.restart(); else closeAnim.restart() }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property string hhmm: clock.hours.toString().padStart(2, "0") + ":" + clock.minutes.toString().padStart(2, "0")
    readonly property string ss: clock.seconds.toString().padStart(2, "0")
    readonly property var now: new Date()

    function dayFrac() {
        return (clock.hours * 3600 + clock.minutes * 60 + clock.seconds) / 86400
    }
    function hourFill(i) {
        if (i < clock.hours) return 1
        if (i > clock.hours) return 0
        return (clock.minutes * 60 + clock.seconds) / 3600
    }
    function dayPct() {
        return Math.floor(root.dayFrac() * 100)
    }
    function elapsedStr() {
        var h = clock.hours
        var m = clock.minutes
        return h + "h " + (m < 10 ? "0" + m : m) + "m elapsed"
    }
    function leftStr() {
        var total = 24 * 3600 - (clock.hours * 3600 + clock.minutes * 60 + clock.seconds)
        var h = Math.floor(total / 3600)
        var m = Math.floor((total % 3600) / 60)
        return h + "h " + (m < 10 ? "0" + m : m) + "m left"
    }
    function yearPct() {
        var n = new Date()
        var start = new Date(n.getFullYear(), 0, 1)
        var end = new Date(n.getFullYear() + 1, 0, 1)
        return Math.floor((n - start) / (end - start) * 100)
    }
    function monthFill(i) {
        var n = new Date()
        var m = n.getMonth()
        if (i < m) return 1
        if (i > m) return 0
        var dim = new Date(n.getFullYear(), m + 1, 0).getDate()
        return n.getDate() / dim
    }
    function weekNum() {
        var d = new Date()
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        var dn = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - dn)
        var y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil(((t - y) / 86400000 + 1) / 7).toString().padStart(2, "0")
    }
    function yearLeft() {
        var n = new Date()
        var end = new Date(n.getFullYear(), 11, 31, 23, 59, 59)
        return Math.ceil((end - n) / 86400000)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 6
        color: colors.alpha(colors.surface, 0.62)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.28)
        // mock pop: 280ms overshoot entrance
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
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
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "CLOCK"
                    color: colors.alpha(colors.outline, 0.85)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.3
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    radius: 10
                    height: 20
                    width: chipText.implicitWidth + 20
                    color: colors.alpha(colors.primary, 0.14)
                    border.width: 1
                    border.color: colors.alpha(colors.primary, 0.4)
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(root.now, "ddd dd MMM")
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.22) }

            // the dial — day-progress arc, 24 hour ticks, 60 stepping
            // second ticks, time in the middle. Canvas, wifi-sparkline way:
            // reset(), solid role colors + globalAlpha, butt caps, no text.
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 216; Layout.preferredHeight: 216
                Canvas {
                    id: dial
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var cx = 108, cy = 108
                        function pt(r, a) { return [cx + Math.sin(a) * r, cy - Math.cos(a) * r] }
                        // track groove + bevel: dark bed, faint ring, light inner lip
                        ctx.lineWidth = 11
                        ctx.strokeStyle = colors.background.toString()
                        ctx.globalAlpha = 0.85
                        ctx.beginPath(); ctx.arc(cx, cy, 87, 0, Math.PI * 2); ctx.stroke()
                        ctx.globalAlpha = 1
                        ctx.strokeStyle = colors.outline.toString()
                        ctx.globalAlpha = 0.22
                        ctx.beginPath(); ctx.arc(cx, cy, 87, 0, Math.PI * 2); ctx.stroke()
                        ctx.globalAlpha = 1
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = colors.foreground.toString()
                        ctx.globalAlpha = 0.18
                        ctx.beginPath(); ctx.arc(cx, cy, 81.5, 0, Math.PI * 2); ctx.stroke()
                        ctx.globalAlpha = 1
                        // day progress: soft shadow first, primary body,
                        // thin top highlight — raised-metal read
                        var f = root.dayFrac()
                        if (f > 0) {
                            var a0 = -Math.PI / 2, a1 = -Math.PI / 2 + f * Math.PI * 2
                            ctx.lineWidth = 11
                            ctx.strokeStyle = colors.background.toString()
                            ctx.globalAlpha = 0.6
                            ctx.beginPath(); ctx.arc(cx, cy + 2.5, 87, a0, a1); ctx.stroke()
                            ctx.globalAlpha = 1
                            ctx.strokeStyle = colors.primary.toString()
                            ctx.lineCap = "round"
                            ctx.beginPath(); ctx.arc(cx, cy, 87, a0, a1); ctx.stroke()
                            ctx.lineCap = "butt"
                            ctx.lineWidth = 2
                            ctx.strokeStyle = colors.foreground.toString()
                            ctx.globalAlpha = 0.35
                            ctx.beginPath(); ctx.arc(cx, cy - 3.5, 87, a0, a1); ctx.stroke()
                            ctx.globalAlpha = 1
                        }
                        // 24 hour ticks, quarters brighter, passed ones primary
                        for (var i = 0; i < 24; i++) {
                            var q = (i % 6 === 0), a = i / 24 * Math.PI * 2
                            var p1 = pt(q ? 94 : 96, a), p2 = pt(106, a)
                            ctx.lineWidth = q ? 3 : 2
                            if (i <= clock.hours) ctx.strokeStyle = colors.primary.toString()
                            else if (q) ctx.strokeStyle = colors.foreground.toString()
                            else { ctx.strokeStyle = colors.outline.toString(); ctx.globalAlpha = 0.45 }
                            ctx.beginPath(); ctx.moveTo(p1[0], p1[1]); ctx.lineTo(p2[0], p2[1]); ctx.stroke()
                            ctx.globalAlpha = 1
                        }
                        // 60 second ticks — step-lit tertiary, never sweeping
                        for (var j = 0; j < 60; j++) {
                            var five = (j % 5 === 0), aj = j / 60 * Math.PI * 2
                            var s1 = pt(five ? 63 : 67, aj), s2 = pt(74, aj)
                            ctx.lineWidth = 2
                            if (j <= clock.seconds) ctx.strokeStyle = colors.tertiary.toString()
                            else { ctx.strokeStyle = colors.outline.toString(); ctx.globalAlpha = five ? 0.6 : 0.3 }
                            ctx.beginPath(); ctx.moveTo(s1[0], s1[1]); ctx.lineTo(s2[0], s2[1]); ctx.stroke()
                            ctx.globalAlpha = 1
                        }
                    }
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: root.hhmm
                        color: colors.primary
                        font.family: "Iceberg"
                        font.pixelSize: 34
                        font.letterSpacing: 2
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: root.ss
                        color: colors.tertiary
                        font.family: "Iceberg"
                        font.pixelSize: 13
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: "DAY " + root.dayPct() + "%"
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.ExtraBold
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
                Connections { target: clock; function onSecondsChanged() { dial.requestPaint() } }
            }

            Text {
                text: Qt.formatDateTime(root.now, "dddd dd MMMM yyyy") + "  ·  W" + root.weekNum()
                color: colors.foreground
                font.family: colors.fontSans
                font.pixelSize: 11
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }

            // year strip — 12 month cells, letter row, days left
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "YEAR " + root.now.getFullYear()
                        color: colors.alpha(colors.outline, 0.85)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.yearPct() + "%"
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.ExtraBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 14
                    spacing: 2
                    Repeater {
                        model: 12
                        delegate: Item {
                            required property int index
                            readonly property real f: root.monthFill(index)
                            readonly property bool cur: index === root.now.getMonth()
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.fill: parent
                                radius: 1
                                color: colors.alpha(colors.outline, 0.2)
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * f
                                radius: 1
                                visible: f > 0
                                color: cur ? colors.tertiary : colors.primary
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: ["J","F","M","A","M","J","J","A","S","O","N","D"]
                        delegate: Text {
                            required property int index
                            required property string modelData
                            text: modelData
                            color: index === root.now.getMonth() ? colors.tertiary : colors.outline
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }
                    }
                }
                Text {
                    text: root.yearLeft() + " DAYS LEFT"
                    color: colors.tertiary
                    font.family: colors.fontSans
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
