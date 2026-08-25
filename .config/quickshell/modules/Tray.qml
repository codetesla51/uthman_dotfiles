import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Controls

// Tray — glass pill container (surface .6, radius 14, padding like waybar #tray),
// 13px icons, L-click activate, R-click menu, scroll passthrough, hover tooltips.
Item {
    id: root

    property var colors

    // hide icons for apps already represented elsewhere (Spotify → NowPlaying pill)
    readonly property var hiddenApps: ["spotify"]
    readonly property var items: SystemTray.items.values.filter(function(it) {
        var s = ((it.id || "") + " " + (it.title || "")).toLowerCase()
        for (var i = 0; i < hiddenApps.length; i++)
            if (s.indexOf(hiddenApps[i]) !== -1) return false
        return true
    })

    implicitWidth: items.length > 0 ? frame.implicitWidth : 0
    implicitHeight: 30
    visible: items.length > 0

    Rectangle {
        id: frame
        anchors.centerIn: parent
        width: trayRow.implicitWidth + 20
        height: 22
        radius: 14
        color: colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)

        Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: root.items

                delegate: Item {
                    id: trayEntry

                    required property var modelData
                    readonly property var item: modelData

                    width: 13
                    height: 13

                    Image {
                        anchors.fill: parent
                        source: trayEntry.item.icon
                        sourceSize.width: 13
                        sourceSize.height: 13
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        opacity: trayMouse.containsMouse ? 1 : 0.75
                    }

                    MouseArea {
                        id: trayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: {
                            if (mouse.button === Qt.RightButton && trayEntry.item.hasMenu)
                                trayEntry.item.display()
                            else
                                trayEntry.item.activate()
                        }
                        onWheel: (wheel) => trayEntry.item.scroll(
                            wheel.angleDelta.y, wheel.angleDelta.x > 0)
                    }

                    ToolTip.visible: trayMouse.containsMouse && trayEntry.item.tooltipTitle !== ""
                    ToolTip.text: trayEntry.item.tooltipTitle
                    ToolTip.delay: 400
                }
            }
        }
    }
}
