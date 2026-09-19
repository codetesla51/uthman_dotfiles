import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
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
    property var _live: ({})   // nid -> live Notification object (for invoking actions)

    function togglePanel() { panelOpen = !panelOpen }
    function toggleDnd() { dnd = !dnd }

    // see WifiPanel: drawer.onVisibleChanged never fires on window toggle.
    onPanelOpenChanged: if (panelOpen) { drawerSlide.x = drawer.width + 8; slideIn.restart() }

    function addToArchive(n) {
        let acts = []
        let alist = n.actions || []
        for (let ai = 0; ai < alist.length; ai++) {
            if (alist[ai].identifier && alist[ai].identifier !== "default" && alist[ai].text)
                acts.push({ id: alist[ai].identifier, label: alist[ai].text })
        }
        let entry = {
            nid: ++root._idCounter,
            appName: n.appName,
            summary: n.summary,
            body: n.body.replace(/<[^>]*>/g, ""),
            icon: n.appIcon,
            urgent: n.urgency === NotificationUrgency.Critical,
            time: Qt.formatDateTime(new Date(), "HH:mm"),
            actions: acts
        }
        root._live[entry.nid] = n
        let list = archive.slice()
        list.unshift(entry)
        if (list.length > 100) list.length = 100
        archive = list
    }

    function clearHistory() {
        archive = []
        _live = ({})
    }



    // per-app Phosphor fallback icon (avatar when the app ships no icon)
    function appGlyph(name) {
        var n = String(name || "").toLowerCase()
        if (n.indexOf("whatsapp") !== -1) return ""
        if (n.indexOf("firefox") !== -1) return ""
        if (n.indexOf("mozilla") !== -1) return ""
        if (n.indexOf("chrome") !== -1) return ""
        if (n.indexOf("chromium") !== -1) return ""
        if (n.indexOf("spotify") !== -1) return ""
        if (n.indexOf("telegram") !== -1) return ""
        if (n.indexOf("discord") !== -1) return ""
        if (n.indexOf("ghostty") !== -1) return ""
        if (n.indexOf("kitty") !== -1) return ""
        if (n.indexOf("terminal") !== -1) return ""
        if (n.indexOf("console") !== -1) return ""
        if (n.indexOf("volume") !== -1) return ""
        if (n.indexOf("audio") !== -1) return ""
        if (n.indexOf("wpctl") !== -1) return ""
        if (n.indexOf("pactl") !== -1) return ""
        if (n.indexOf("speaker") !== -1) return ""
        if (n.indexOf("mic") !== -1) return ""
        if (n.indexOf("battery") !== -1) return ""
        if (n.indexOf("power") !== -1) return ""
        if (n.indexOf("tlp") !== -1) return ""
        if (n.indexOf("wifi") !== -1) return ""
        if (n.indexOf("network") !== -1) return ""
        if (n.indexOf("nmcli") !== -1) return ""
        if (n.indexOf("iwctl") !== -1) return ""
        if (n.indexOf("bluetooth") !== -1) return ""
        if (n.indexOf("screenshot") !== -1) return ""
        if (n.indexOf("shot") !== -1) return ""
        if (n.indexOf("camera") !== -1) return ""
        if (n.indexOf("clipboard") !== -1) return ""
        if (n.indexOf("cliphist") !== -1) return ""
        if (n.indexOf("music") !== -1) return ""
        if (n.indexOf("mpv") !== -1) return ""
        if (n.indexOf("video") !== -1) return ""
        if (n.indexOf("mail") !== -1) return ""
        if (n.indexOf("thunderbird") !== -1) return ""
        if (n.indexOf("envelope") !== -1) return ""
        if (n.indexOf("calendar") !== -1) return ""
        if (n.indexOf("download") !== -1) return ""
        if (n.indexOf("brightness") !== -1) return ""
        if (n.indexOf("sunset") !== -1) return ""
        if (n.indexOf("night") !== -1) return ""
        if (n.indexOf("image") !== -1) return ""
        if (n.indexOf("chat") !== -1) return ""
        if (n.indexOf("note") !== -1) return ""
        if (n.indexOf("github") !== -1) return ""
        if (n.indexOf("git") !== -1) return ""
        if (n.indexOf("brave") !== -1) return ""
        if (n.indexOf("vivaldi") !== -1) return ""
        if (n.indexOf("edge") !== -1) return ""
        if (n.indexOf("opera") !== -1) return ""
        if (n.indexOf("zen") !== -1) return ""
        if (n.indexOf("grim") !== -1) return ""
        if (n.indexOf("slurp") !== -1) return ""
        if (n.indexOf("flameshot") !== -1) return ""
        if (n.indexOf("swappy") !== -1) return ""
        if (n.indexOf("obs") !== -1) return ""
        if (n.indexOf("recorder") !== -1) return ""
        if (n.indexOf("swayosd") !== -1) return ""
        if (n.indexOf("upower") !== -1) return ""
        if (n.indexOf("mpd") !== -1) return ""
        if (n.indexOf("ncmpcpp") !== -1) return ""
        if (n.indexOf("pacman") !== -1) return ""
        if (n.indexOf("yay") !== -1) return ""
        if (n.indexOf("paru") !== -1) return ""
        if (n.indexOf("update") !== -1) return ""
        if (n.indexOf("keepassxc") !== -1) return ""
        if (n.indexOf("password") !== -1) return ""
        if (n.indexOf("nautilus") !== -1) return ""
        if (n.indexOf("thunar") !== -1) return ""
        if (n.indexOf("dolphin") !== -1) return ""
        if (n.indexOf("filemanager") !== -1) return ""
        if (n.indexOf("code") !== -1) return ""
        if (n.indexOf("zed") !== -1) return ""
        if (n.indexOf("nvim") !== -1) return ""
        if (n.indexOf("neovim") !== -1) return ""
        if (n.indexOf("phone") !== -1) return ""
        if (n.indexOf("hyprlock") !== -1) return ""
        if (n.indexOf("lock") !== -1) return ""
        if (n.indexOf("weather") !== -1) return ""
        if (n.indexOf("usb") !== -1) return ""
        if (n.indexOf("udisk") !== -1) return ""
        if (n.indexOf("timer") !== -1) return ""
        if (n.indexOf("pomodoro") !== -1) return ""
        if (n.indexOf("alarm") !== -1) return ""
        if (n.indexOf("watchcat") !== -1) return ""
        return ""
    }

    function removeAt(nid) {
        delete _live[nid]
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
        WlrLayershell.namespace: "qs-toasts"
        WlrLayershell.layer: WlrLayer.Overlay
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
        WlrLayershell.namespace: "qs-notify"
        WlrLayershell.layer: WlrLayer.Overlay

        // click-outside catcher (invisible — no dim backdrop, card floats over desktop)
        Rectangle {
            anchors.fill: parent
            color: "transparent"

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
            color: colors.alpha(colors.background, 0.78)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)

            // ESC closes any open panel (convention for all future panels)
            Keys.onEscapePressed: root.panelOpen = false

            transform: Translate { id: drawerSlide }
            Component.onCompleted: drawerSlide.x = width + 8

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

                    Rectangle {
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                        color: colors.alpha(colors.primary, 0.15)
                        border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                        Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: "Phosphor"; font.pixelSize: 12 }
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "NOTIFICATIONS"
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 12
                        font.weight: Font.ExtraBold
                        font.letterSpacing: 1.3
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
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
                            font.family: colors.fontSans
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    Rectangle {
                        width: dndIcon.implicitWidth + dndLabel.implicitWidth + 26
                        height: 24
                        radius: 12
                        color: root.dnd ? colors.alpha(colors.error, 0.2)
                              : dndArea.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4)
                              : "transparent"
                        border.width: 1
                        border.color: root.dnd ? colors.alpha(colors.error, 0.5)
                                               : colors.alpha(colors.outline, 0.25)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                id: dndIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.dnd ? "" : ""
                                color: root.dnd ? colors.error : colors.alpha(colors.outline, 0.9)
                                font.family: "Phosphor"
                                font.pixelSize: 10
                            }
                            Text {
                                id: dndLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: "DND"
                                color: root.dnd ? colors.error : colors.alpha(colors.outline, 0.9)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
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
                            text: ""
                            color: clearMouse.containsMouse ? colors.error : colors.alpha(colors.outline, 0.9)
                            font.family: "Phosphor"
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
                            text: ""
                            color: closePanelMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.9)
                            font.family: "Phosphor"
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
                                id: notifRow
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                height: Math.max(56, rowContent.implicitHeight + 18)
                                radius: 10
                                color: itemMouse.containsMouse ? colors.alpha(colors.surfaceVariant, 0.3)
                                                               : "transparent"
                                border.width: modelData.urgent ? 1 : 0
                                border.color: colors.alpha(colors.error, 0.45)

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
                                            readonly property string ag: root.appGlyph(modelData.appName)
                                            text: ag !== "" ? ag : (modelData.appName ? modelData.appName.charAt(0).toUpperCase() : "?")
                                            color: colors.primary
                                            font.family: ag !== "" ? "Phosphor" : colors.fontSans
                                            font.pixelSize: ag !== "" ? 17 : 13
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
                                                font.family: colors.fontSans
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: (modelData.appName ? modelData.appName : "") + (modelData.appName ? " · " : "") + modelData.time
                                                color: colors.alpha(colors.outline, 0.55)
                                                font.family: colors.fontSans
                                                font.pixelSize: 9
                                            }
                                        }

                                        Item { Layout.fillHeight: true; Layout.preferredWidth: 1 }

                                        Text {
                                            visible: modelData.body !== ""
                                            text: modelData.body
                                            color: colors.on_surface
                                            font.family: colors.fontSans
                                            font.pixelSize: 10
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }

                                        // action chips — invoke the live notification's action
                                        Row {
                                            visible: notifRow.modelData.actions && notifRow.modelData.actions.length > 0
                                            spacing: 5

                                            Repeater {
                                                model: notifRow.modelData.actions || []

                                                delegate: Rectangle {
                                                    id: actChip
                                                    required property var modelData
                                                    width: actLbl.implicitWidth + 18
                                                    height: 20
                                                    radius: 10
                                                    color: actMa.containsMouse ? colors.alpha(colors.primary, 0.25)
                                                                              : colors.alpha(colors.primary, 0.12)
                                                    border.width: 1
                                                    border.color: colors.alpha(colors.primary, 0.35)

                                                    Text {
                                                        id: actLbl
                                                        anchors.centerIn: parent
                                                        text: actChip.modelData.label
                                                        color: colors.primary
                                                        font.family: colors.fontSans
                                                        font.pixelSize: 9
                                                        font.weight: Font.Bold
                                                    }

                                                    MouseArea {
                                                        id: actMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        onClicked: {
                                                            let live = root._live[notifRow.modelData.nid]
                                                            if (!live) return
                                                            let list = live.actions || []
                                                            for (let i = 0; i < list.length; i++)
                                                                if (list[i].identifier === actChip.modelData.id) { list[i].invoke(); break }
                                                            root.removeAt(notifRow.modelData.nid)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: itemMouse.containsMouse
                                        width: 20; height: 20; radius: 10
                                        color: rowCloseMouse.containsMouse ? colors.alpha(colors.error, 0.3) : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: ""
                                            color: rowCloseMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7)
                                            font.family: "Phosphor"
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
                                    text: ""
                                    color: colors.alpha(colors.outline, 0.35)
                                    font.family: "Phosphor"
                                    font.pixelSize: 32
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                Text {
                                    text: "No notifications"
                                    color: colors.alpha(colors.outline, 0.6)
                                    font.family: colors.fontSans
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
