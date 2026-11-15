import QtQuick

// Clock — Iceberg stacked hours over minutes, left aligned so it reads as
// the page's headline rather than a centred widget. One timer wake per real
// minute boundary; no per-second ticking.
Item {
    id: root

    property var theme
    property string hours: "00"
    property string minutes: "00"

    implicitWidth: clockText.implicitWidth
    implicitHeight: clockText.implicitHeight

    function update() {
        var d = new Date()
        root.hours = ("0" + d.getHours()).slice(-2)
        root.minutes = ("0" + d.getMinutes()).slice(-2)
    }

    Text {
        id: clockText
        anchors.left: parent.left
        text: root.hours + "\n" + root.minutes
        color: root.theme ? root.theme.foreground : "#fedad7"
        font.family: root.theme ? root.theme.clockFamily : "Iceberg"
        font.pixelSize: root.theme ? root.theme.clockSize : 158
        font.weight: Font.Light
        font.letterSpacing: root.theme ? root.theme.clockTracking : -3
        horizontalAlignment: Text.AlignLeft
        lineHeight: root.theme ? root.theme.clockLineHeight : 0.74
        lineHeightMode: Text.ProportionalHeight
    }

    Timer {
        id: minuteTimer
        repeat: false
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.update()
            // 80ms of slack so the minute flips just after the boundary
            interval = Math.max(250, 60000 - (Date.now() % 60000) + 80)
            restart()
        }
    }
}