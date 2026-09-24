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
    implicitHeight: 320
    minimumSize: Qt.size(340, 300)
    maximumSize: Qt.size(390, 350)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "clockwin"; function toggle(): void { root.open = !root.open } }

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
    function yearLeft() {
        var n = new Date()
        var end = new Date(n.getFullYear(), 11, 31, 23, 59, 59)
        return Math.ceil((end - n) / 86400000)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "CLOCK"
                    color: colors.alpha(colors.outline, 0.55)
                    font.family: colors.fontSans
                    font.pixelSize: 7
                    font.weight: Font.Bold
                    font.letterSpacing: 1.3
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    radius: 11
                    height: 22
                    width: dateText.implicitWidth + 16
                    color: colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)
                    Text {
                        id: dateText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(root.now, "ddd dd MMM")
                        color: colors.alpha(colors.foreground, 0.85)
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Text {
                    text: root.hhmm
                    color: colors.primary
                    font.family: "Iceberg"
                    font.pixelSize: 44
                    font.weight: Font.Normal
                    font.letterSpacing: 2
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    Text {
                        text: root.ss
                        color: colors.tertiary
                        font.family: "Iceberg"
                        font.pixelSize: 14
                        font.weight: Font.Normal
                        Layout.alignment: Qt.AlignLeft
                    }
                    Text {
                        text: "SEC"
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        font.letterSpacing: 1.3
                        Layout.alignment: Qt.AlignLeft
                    }
                }
            }

            Text {
                text: Qt.formatDateTime(root.now, "dddd dd MMMM yyyy") + "  ·  W" + Qt.formatDateTime(root.now, "ww")
                color: colors.foreground
                font.family: colors.fontSans
                font.pixelSize: 11
                font.weight: Font.Medium
                Layout.alignment: Qt.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "DAY — 24H"
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        font.letterSpacing: 1.3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "DAY " + root.dayPct() + "%"
                        color: colors.alpha(colors.primary, 0.75)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    spacing: 2
                    Repeater {
                        model: 24
                        delegate: Item {
                            required property int index
                            readonly property real f: root.hourFill(index)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: colors.alpha(colors.outline, 0.12)
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * f
                                radius: 3
                                visible: f > 0
                                color: index < clock.hours ? colors.primary : colors.tertiary
                                opacity: index < clock.hours ? 0.85 : 1.0
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                radius: 1
                                visible: index === clock.hours
                                color: colors.tertiary
                            }
                        }
                    }
                }
                Text {
                    text: root.leftStr()
                    color: colors.tertiary
                    font.family: colors.fontSans
                    font.pixelSize: 10
                    font.weight: Font.ExtraBold
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "YEAR — " + root.now.getFullYear()
                        color: colors.alpha(colors.outline, 0.55)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        font.letterSpacing: 1.3
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "YEAR " + root.yearPct() + "%"
                        color: colors.alpha(colors.primary, 0.75)
                        font.family: colors.fontSans
                        font.pixelSize: 7
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 12
                    spacing: 2
                    Repeater {
                        model: 12
                        delegate: Item {
                            required property int index
                            readonly property real f: root.monthFill(index)
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: colors.alpha(colors.outline, 0.12)
                            }
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * f
                                radius: 3
                                visible: f > 0
                                color: index < root.now.getMonth() ? colors.primary : colors.tertiary
                                opacity: index < root.now.getMonth() ? 0.85 : 1.0
                            }
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
