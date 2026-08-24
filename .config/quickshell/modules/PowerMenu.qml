import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Power menu — centered modal glass card.
// Open: SUPER+ESC (hypr bind -> IpcHandler) or Bar power button if wired.
// Closes on ESC (panel convention) or clicking the dimmed backdrop.
PanelWindow {
    id: root

    property var colors
    property bool open: false

    visible: root.open          // fully gone when closed — no invisible click-blocker
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: true   // grab keyboard so ESC works

    // ── IPC: quickshell -p ~/.config/quickshell ipc call power toggle ──
    IpcHandler {
        target: "power"
        function toggle(): void { root.open = !root.open }
    }

    // dimmed backdrop — click to dismiss
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, open ? 0.55 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.open = false
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 340
        height: cardColumn.implicitHeight + 40
        radius: 18
        color: colors.alpha(colors.background, 0.96)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.3)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: root.open = false
        focus: root.open

        ColumnLayout {
            id: cardColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 8

            Text {
                text: "Power"
                color: colors.foreground
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 15
                font.weight: Font.ExtraBold
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 6
            }

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
                    height: 44
                    radius: 12
                    color: hovered ? colors.alpha(colors.primary, 0.14)
                                   : colors.alpha(colors.surface, 0.5)
                    border.width: 1
                    border.color: hovered ? colors.alpha(colors.primary, 0.4)
                                          : colors.alpha(colors.outline, 0.12)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        Text {
                            text: modelData.icon
                            color: modelData.label === "Shutdown" && itemArea.containsMouse
                                   ? colors.error : colors.foreground
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 14
                        }

                        Text {
                            text: modelData.label
                            color: colors.foreground
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }

                        Text {
                            text: ""
                            color: colors.alpha(colors.outline, itemArea.containsMouse ? 0.9 : 0.35)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
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
