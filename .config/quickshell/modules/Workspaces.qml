import Quickshell.Hyprland
import QtQuick

// Workspaces — segmented control pill (waybar style.css parity).
// Container: surface .65, radius 14 · buttons radius 11, min-width 18.
// active: primary→secondary gradient + glow · empty: dim · urgent: error.
Item {
    id: root

    property var colors
    readonly property var wsList: Hyprland.workspaces.values
    readonly property var focusedWsId: Hyprland.focusedMonitor
        ? Hyprland.focusedMonitor.activeWorkspace.id : -1
    readonly property var shownIds: {
        var ids = {}
        for (var i = 1; i <= 5; i++) ids[i] = true
        for (var j = 0; j < wsList.length; j++)
            if (wsList[j].id > 0) ids[wsList[j].id] = true
        return Object.keys(ids).map(Number).sort(function(a, b) { return a - b })
    }

    implicitWidth: btnRow.implicitWidth + 10
    implicitHeight: 30

    // segmented-control container (width driven by the Row's implicit size — no childrenRect)
    Rectangle {
        id: container
        anchors.centerIn: parent
        width: btnRow.implicitWidth + 10
        height: 30
        radius: 14
        color: colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: root.shownIds

                delegate: Rectangle {
                    id: btn

                    required property var modelData
                    readonly property int wsId: modelData
                    readonly property var ws: root.wsList.find(w => w.id === wsId) ?? null
                    readonly property bool isActive: ws ? ws.active || wsId === root.focusedWsId : false
                    readonly property bool isEmpty: ws ? ws.toplevels.values.length === 0 : true
                    readonly property bool isUrgent: ws ? ws.urgent : false
                    readonly property bool hovered: btnMouse.containsMouse

                    width: Math.max(22, label.implicitWidth + 20)
                    height: 24
                    radius: 11
                    color: isActive ? "transparent"
                         : isUrgent ? colors.error
                         : hovered ? colors.alpha(colors.surfaceVariant, 0.4)
                         : "transparent"

                    Behavior on color { ColorAnimation { duration: 250 } }

                    // active glow (box-shadow stand-in)
                    Rectangle {
                        visible: btn.isActive
                        anchors.fill: parent
                        radius: 11
                        y: 1
                        color: colors.alpha(colors.primary, 0.35)
                    }

                    // active gradient fill
                    Rectangle {
                        visible: btn.isActive
                        anchors.fill: parent
                        radius: 11
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: colors.primary }
                            GradientStop { position: 1; color: colors.alpha(colors.secondary, 0.9) }
                        }
                    }

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: btn.isActive ? "󰮯"
                             : (!btn.isEmpty ? "󰊠" : "󰑊")
                        color: btn.isActive || btn.isUrgent ? colors.background
                             : btn.hovered ? colors.foreground
                             : btn.isEmpty ? colors.alpha(colors.outline, 0.35)
                             : colors.alpha(colors.outline, 0.7)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: btn.isEmpty && !btn.isActive ? 9 : 13
                        font.weight: Font.Bold
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Hyprland.dispatch("workspace " + btn.wsId)
                    }
                }
            }
        }
    }
}
