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

    // Hours keep the paper-white ink; the minutes take the live primary so
    // the headline itself carries one system colour instead of reading as
    // monochrome. Both lines share the same font and line height.
    readonly property color hoursColor: root.theme
        ? root.theme.foreground : "#fedad7"
    readonly property color minutesColor: root.theme
        ? root.theme.primary : "#ffffff"

    function update() {
        var d = new Date()
        root.hours = ("0" + d.getHours()).slice(-2)
        root.minutes = ("0" + d.getMinutes()).slice(-2)
    }

    Text {
        id: clockText
        anchors.left: parent.left
        text: "<font color=\"" + root.hoursColor + "\">" + root.hours
            + "</font><br><font color=\"" + root.minutesColor + "\">"
            + root.minutes + "</font>"
        textFormat: Text.StyledText
        color: root.hoursColor
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