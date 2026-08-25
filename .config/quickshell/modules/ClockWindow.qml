import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ClockWindow — small draggable Hyprland floating window (FastFetch-style):
// big live time, date chip, week/unix trivia row. Toggle from the bar clock.
FloatingWindow {
    id: root

    property var colors
    property bool open: false

    title: "Clock"
    implicitWidth: 320
    implicitHeight: 190
    color: "transparent"
    visible: root.open

    IpcHandler { target: "clockwin"; function toggle(): void { root.open = !root.open } }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    readonly property string hhmm: clock.hours.toString().padStart(2, "0") + ":" + clock.minutes.toString().padStart(2, "0")
    readonly property string ss: clock.seconds.toString().padStart(2, "0")
    readonly property var now: new Date()

    Rectangle {
        id: card
        anchors.fill: parent
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
            anchors.margins: 18
            spacing: 8

            // -- header: label + date chip --
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "TIME"
                    color: colors.alpha(colors.outline, 0.65)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    radius: 9
                    height: 22
                    width: dateText.implicitWidth + 16
                    color: colors.alpha(colors.surfaceVariant, 0.30)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)
                    Text {
                        id: dateText
                        anchors.centerIn: parent
                        text: Qt.formatDateTime(root.now, "ddd dd MMM")
                        color: colors.alpha(colors.foreground, 0.85)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // -- big time --
            Item { Layout.fillHeight: true }
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Text {
                    text: root.hhmm
                    color: colors.primary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 52
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: root.ss
                        color: colors.tertiary
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                }
            }
            Item { Layout.fillHeight: true }

            // -- footer trivia --
            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDateTime(root.now, "dddd dd MMMM yyyy") + "  ·  W" + Qt.formatDateTime(root.now, "ww")
                color: colors.alpha(colors.foreground, 0.65)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
                font.weight: Font.Medium
            }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
