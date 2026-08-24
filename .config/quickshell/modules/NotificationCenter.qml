import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Notification daemon + toast stack + center drawer.
// Owns org.freedesktop.Notifications (replaces swaync).
//
// History model: our own archive (plain objects, newest first, capped).
// The server's trackedNotifications only holds LIVE notifications — once a
// toast dismisses them they'd vanish, so we archive on arrival instead.
Item {
    id: root

    property var colors
    property bool dnd: false
    property bool panelOpen: false
    readonly property int historyCount: archive.length
    property var archive: []

    property int _idCounter: 0

    function togglePanel() { panelOpen = !panelOpen }
    function toggleDnd() { dnd = !dnd }

    function addToArchive(n) {
        let entry = {
            nid: ++root._idCounter,
            appName: n.appName,
            summary: n.summary,
            body: n.body.replace(/<[^>]*>/g, ""),
            icon: n.appIcon,
            urgent: n.urgency === NotificationUrgency.Critical,
            time: Qt.formatDateTime(new Date(), "HH:mm")
        }
        let list = archive.slice()
        list.unshift(entry)
        if (list.length > 100) list.length = 100
        archive = list
    }

    function clearHistory() { archive = [] }


    function removeAt(nid) {
        let list = archive.slice()
        for (let i = 0; i < list.length; i++)
            if (list[i].nid === nid) { list.splice(i, 1); break }
        archive = list
    }

    // ── daemon ──
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (notification) => {
            root.addToArchive(notification)
            if (!root.dnd) root.popToast(notification)
        }
    }

    // ── IPC: qs -p <config> ipc call notifications toggle ──
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.togglePanel() }
        function toggleDnd(): void { root.toggleDnd() }
    }

    // ── toast stack ──
    PanelWindow {
        id: toastWindow
        anchors { top: true; right: true }
        margins { top: 52; right: 8 }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        implicitWidth: 380
        implicitHeight: toastColumn.implicitHeight + 8

        Column {
            id: toastColumn
            anchors { top: parent.top; right: parent.right }
            width: 380
            spacing: 8
        }
    }

    Component {
        id: toastComp
        NotificationToast {}
    }

    function popToast(n) {
        let cards = toastColumn.children.filter(function(c) {
            return c.toString().indexOf("NotificationToast") === 0
        })
        while (cards.length >= 5) cards.shift().destroy()
        toastComp.createObject(toastColumn, { notification: n, colors: root.colors })
    }

    // ────────────────────────────────────────────────
    // Center drawer
    // ────────────────────────────────────────────────
    // Drawer: ONE fullscreen window (PowerMenu pattern) — dim backdrop catches
    // outside clicks, card anchored top-right. Two sibling layer windows stack
    // unpredictably (the catcher ended up ABOVE the drawer eating its clicks).
    PanelWindow {
        id: panelWindow
        visible: root.panelOpen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        focusable: true   // grabs keyboard while open -> ESC works

        // dimmed click-outside catcher (inside the SAME window, always below card)
        Rectangle {
            anchors.fill: parent
            color: colors.alpha(colors.background, root.panelOpen ? 0.3 : 0)
            Behavior on color { ColorAnimation { duration: 200 } }

            MouseArea {
                anchors.fill: parent
                onClicked: root.panelOpen = false
            }
        }

        Rectangle {
            id: drawer
            focus: visible
            anchors { top: parent.top; right: parent.right }
            anchors.topMargin: 52
            anchors.rightMargin: 8
            width: 380
            height: 520
            radius: 16
            color: colors.alpha(colors.background, 0.94)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.3)

            // ESC closes any open panel (convention for all future panels)
            Keys.onEscapePressed: root.panelOpen = false

            transform: Translate { id: drawerSlide }
            Component.onCompleted: drawerSlide.x = width + 8
            onVisibleChanged: {
                if (visible) {
                    drawerSlide.x = width + 8
                    slideIn.restart()
                }
            }

            ParallelAnimation {
                id: slideIn
                NumberAnimation { target: drawerSlide; property: "x"; from: drawer.width + 8; to: 0; duration: 250; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Notifications"
                        color: colors.foreground
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.ExtraBold
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        width: countLabel.implicitWidth + 14
                        height: 20
                        radius: 10
                        visible: root.historyCount > 0
                        color: colors.alpha(colors.primary, 0.15)

                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: root.historyCount
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    Rectangle {
                        width: dndLabel.implicitWidth + 22
                        height: 24
                        radius: 12
                        color: root.dnd ? colors.alpha(colors.error, 0.2)
                              : dndArea.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4)
                              : "transparent"
                        border.width: 1
                        border.color: root.dnd ? colors.alpha(colors.error, 0.5)
                                               : colors.alpha(colors.outline, 0.25)

                        Text {
                            id: dndLabel
                            anchors.centerIn: parent
                            text: (root.dnd ? "󰂛" : "󰂚") + " DND"
                            color: root.dnd ? colors.error : colors.alpha(colors.outline, 0.9)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                        }

                        MouseArea {
                            id: dndArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleDnd()
                        }
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: clearMouse.containsMouse ? colors.alpha(colors.error, 0.25) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "󰩹"
                            color: clearMouse.containsMouse ? colors.error : colors.alpha(colors.outline, 0.9)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.clearHistory()
                        }
                    }

                    Rectangle {
                        width: 24; height: 24; radius: 12
                        color: closePanelMouse.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "󰅖"
                            color: closePanelMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.9)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                        }

                        MouseArea {
                            id: closePanelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.panelOpen = false
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.15) }

                ScrollView {
                    id: historyScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    contentWidth: availableWidth
                    contentHeight: historyCol.implicitHeight

                    ColumnLayout {
                        id: historyCol
                        width: historyScroll.availableWidth
                        spacing: 4

                        Repeater {
                            model: root.archive   // newest first already

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                height: 56
                                radius: 10
                                color: itemMouse.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3)
                                                               : "transparent"

                                RowLayout {
                                    id: rowContent
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        radius: 8
                                        color: colors.alpha(colors.surfaceVariant, 0.35)

                                        Image {
                                            id: rowIcon
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            visible: status === Image.Ready
                                            source: modelData.icon === "" ? ""
                                                    : (modelData.icon.indexOf("/") === 0 || modelData.icon.indexOf("://") !== -1)
                                                      ? modelData.icon : Quickshell.iconPath(modelData.icon)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }

                                        Text {
                                            visible: !rowIcon.visible
                                            anchors.centerIn: parent
                                            text: modelData.appName ? modelData.appName.charAt(0).toUpperCase() : "?"
                                            color: colors.primary
                                            font.family: "FiraCode Nerd Font"
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                        }
                                    }

                                    ColumnLayout {
                                        spacing: 1
                                        Layout.fillWidth: true

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: modelData.summary
                                                color: colors.foreground
                                                font.family: "FiraCode Nerd Font"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: (modelData.appName ? modelData.appName : "") + (modelData.appName ? " · " : "") + modelData.time
                                                color: colors.alpha(colors.outline, 0.55)
                                                font.family: "FiraCode Nerd Font"
                                                font.pixelSize: 9
                                            }
                                        }

                                        Item { Layout.fillHeight: true; Layout.preferredWidth: 1 }

                                        Text {
                                            visible: modelData.body !== ""
                                            text: modelData.body
                                            color: colors.on_surface
                                            font.family: "FiraCode Nerd Font"
                                            font.pixelSize: 10
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: itemMouse.containsMouse
                                        width: 20; height: 20; radius: 10
                                        color: rowCloseMouse.containsMouse ? colors.alpha(colors.error, 0.3) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰅖"
                                            color: rowCloseMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7)
                                            font.family: "FiraCode Nerd Font"
                                            font.pixelSize: 11
                                        }

                                        MouseArea {
                                            id: rowCloseMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: root.removeAt(modelData.nid)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }
                            }
                        }

                        Item {
                            visible: root.historyCount === 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 220

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    text: "󰂛"
                                    color: colors.alpha(colors.outline, 0.35)
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 32
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: "No notifications"
                                    color: colors.alpha(colors.outline, 0.6)
                                    font.family: "FiraCode Nerd Font"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
