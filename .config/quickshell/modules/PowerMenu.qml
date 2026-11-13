import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components/Bloom.js" as Bloom

// Power menu — centered modal glass card.
// Open: SUPER+ESC (hypr bind -> IpcHandler) or Bar power button if wired.
// Closes on ESC (panel convention) or clicking the dimmed backdrop.
PanelWindow {
    id: root

    property var colors
    property bool open: false

    visible: root.open || closeAnim.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: true   // grab keyboard so ESC works

    // ── IPC: quickshell -p ~/.config/quickshell ipc call power toggle ──
    IpcHandler {
        target: "power"
        function toggle(): void { root.open = !root.open }
    }

    // bezier pair — open pops with overshoot bounce (fast), close hurries
    // out with none. Same curves as the launcher.
    onOpenChanged: if (open) openAnim.restart(); else closeAnim.restart()

    // click-outside catcher (invisible — no dim backdrop, card floats over desktop)
    Rectangle {
        anchors.fill: parent
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 520
        height: 200
        radius: 18
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        Keys.onEscapePressed: root.open = false
        focus: root.open
        transform: Translate { id: bloomOrigin }

        // bezier pair — open pops with overshoot bounce (fast), close hurries
        // out with none. Same curves as the launcher.
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: bloomOrigin; property: "y"; from: -(root.height / 2 - 34); to: 0; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
            NumberAnimation { target: card; property: "rotation"; from: Bloom.panelRotate; to: 0; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Bloom.normal; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "scale"; from: Bloom.panelScale; to: 1; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: bloomOrigin; property: "y"; to: -(root.height / 2 - 34); duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "rotation"; to: Bloom.panelRotate; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
            NumberAnimation { target: card; property: "scale"; to: Bloom.panelScale; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
        }

        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 8

            Text {
                text: "Power"
                color: colors.foreground
                font.family: colors.fontSans
                font.pixelSize: 15
                font.weight: Font.ExtraBold
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 6
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 8

                Repeater {
                    model: [
                        { label: "Lock",        icon: "",  cmd: "pidof hyprlock || hyprlock" },
                        { label: "Logout",      icon: "",  cmd: "hyprctl dispatch exit" },
                        { label: "Suspend",     icon: "",  cmd: "systemctl suspend" },
                        { label: "Reboot",      icon: "",  cmd: "systemctl reboot" },
                        { label: "Shutdown",    icon: "",  cmd: "systemctl poweroff" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        property bool hovered: itemArea.containsMouse

                        Layout.fillWidth: true
                        Layout.preferredHeight: 88
                        radius: 14
                        scale: hovered ? 1.06 : 1
                        y: hovered ? -3 : 0
                        color: hovered ? colors.alpha(colors.primary, 0.16)
                                       : colors.alpha(colors.surface, 0.5)
                        border.width: 1
                        border.color: hovered ? colors.alpha(colors.primary, 0.5)
                                              : colors.alpha(colors.outline, 0.12)
                        Behavior on scale { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } }
                        Behavior on y { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: modelData.icon
                                color: modelData.label === "Shutdown" && hovered ? colors.error : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 22
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: modelData.label
                                color: hovered ? colors.foreground : colors.alpha(colors.outline, 0.9)
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.open = false
                                Quickshell.execDetached(["sh", "-c", modelData.cmd])
                            }
                        }

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }
                }
            }
        }
    }
}
