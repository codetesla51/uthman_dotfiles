import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import "../components/Bloom.js" as Bloom
import "DripKind.js" as Drip

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

    // Only 3 toasts at a time. Anything beyond waits in a circle and is
    // released slowly after a card finishes retracting.
    property var pending: []
    property int waitingCount: 0
    // 340 = 320px capsule + 10px headroom each side for the entrance bounce.
    property int toastRailWidth: 340

    // Bar's PixelBot listens to this — the bot replaced the bell as the
    // ambient notification indicator.
    signal notificationArrived(var notification)

    function togglePanel() { panelOpen = !panelOpen }
    function toggleDnd() { dnd = !dnd }

    // drawer motion lives in openAnim/closeAnim below (bezier pair).
    // Close plays out before the window hides (visible binds running).
    onPanelOpenChanged: if (panelOpen) openAnim.restart(); else closeAnim.restart()

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
        return Drip.glyphForApp(name)
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
            if (!root.dnd) {
                root.popToast(notification)
                root.notificationArrived(notification)
            }
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
        // Start below the bar and position explicitly: implicitWidth alone
        // drifted when the rail resized, which shifted notifications off-centre.
        anchors { top: true; left: true }
        margins {
            top: 110
            left: Math.max(0, (Screen.width - root.toastRailWidth) / 2)
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "qs-toasts"
        WlrLayershell.layer: WlrLayer.Overlay
        // No resident window: idle means zero input interception.
        visible: openToasts().length > 0 || closingToasts().length > 0
                 || root.waitingCount > 0
        implicitWidth: root.toastRailWidth
        implicitHeight: Math.max(340, toastColumn.implicitHeight + 180)

        Column {
            id: toastColumn
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
            // Must match the toast item width, or Column left-aligns each
            // 320px toast inside a wider column and the window clips half.
            width: root.toastRailWidth
            // Each toast owns its own bottom gap (height = card + gap), so the
            // gap collapses with the card instead of jumping on destroy.
            spacing: 0
        }

        // Waiting count: a circle below the stack, same near-black as the
        // capsule, with the demo's slow ping ring.
        Rectangle {
            id: waitingCircle
            anchors.horizontalCenter: parent.horizontalCenter
            y: toastColumn.y + toastColumn.implicitHeight + 22
            width: 46
            height: 46
            radius: 23
            color: "#0a0a0a"
            visible: root.waitingCount > 0

            Text {
                anchors.centerIn: parent
                text: root.waitingCount
                color: "#f5f5f0"
                font.family: colors.fontSans
                font.pixelSize: 15
                font.weight: Font.Bold
            }
        }

        Rectangle {
            id: waitingPing
            anchors.centerIn: waitingCircle
            width: 46
            height: 46
            radius: 23
            color: "transparent"
            border.width: 2
            border.color: "#0a0a0a"
            visible: waitingCircle.visible

            ParallelAnimation {
                running: waitingCircle.visible
                loops: Animation.Infinite
                NumberAnimation {
                    target: waitingPing; property: "scale"
                    from: 0.7; to: 2.1; duration: 1800
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: waitingPing; property: "opacity"
                    from: 0.4; to: 0; duration: 1800
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Component {
        id: toastComp
        NotificationToast {}
    }

    // Recompute each card's return-to-notch offset after the stack changes.
    function syncToastOrigins() {
        let y = 0
        for (let i = 0; i < toastColumn.children.length; i++) {
            let c = toastColumn.children[i]
            // Never retarget a card that is already retracting into the notch.
            if (c.state_ === "closing") continue
            if (c.originY !== undefined) c.originY = -y
            y += c.height
        }
    }

    function openToasts() {
        return toastColumn.children.filter(function(c) {
            return c.toString().indexOf("NotificationToast") === 0 && c.state_ === "open"
        })
    }

    function closingToasts() {
        return toastColumn.children.filter(function(c) {
            return c.toString().indexOf("NotificationToast") === 0 && c.state_ === "closing"
        })
    }

    function updateRailWidth() {
        let w = 340
        let cards = openToasts()
        for (let i = 0; i < cards.length; i++)
            if (cards[i].targetW !== undefined) w = Math.max(w, cards[i].targetW)
        root.toastRailWidth = w
    }

    // Release ONE queued notification per tick, and only once every retract
    // has finished. No overlap with closing cards, no batch reflow jump.
    function drainQueue() {
        if (closingToasts().length > 0) return
        let open = openToasts()
        if (open.length >= 3 || root.pending.length === 0) {
            root.waitingCount = root.pending.length
            return
        }

        let y = 0
        for (let i = 0; i < open.length; i++) y += open[i].height

        let n = root.pending.shift()
        toastComp.createObject(toastColumn, {
            notification: n,
            colors: root.colors,
            stackIndex: open.length,
            railWidth: Qt.binding(function() { return root.toastRailWidth }),
            originY: -y
        }).expired.connect(function() { Qt.callLater(function() {
            syncToastOrigins()
            updateRailWidth()
        }) })
        updateRailWidth()
        root.waitingCount = root.pending.length
    }

    function popToast(n) {
        root.pending.push(n)
        root.waitingCount = root.pending.length
        queueTimer.restart()
        drainQueue()
    }

    // Slow release: one queued notification per closed slot, never rushed.
    Timer {
        id: queueTimer
        interval: 900
        running: root.pending.length > 0
        repeat: true
        onTriggered: drainQueue()
    }

    // ────────────────────────────────────────────────
    // Center drawer
    // ────────────────────────────────────────────────
    // Drawer: ONE fullscreen window (PowerMenu pattern) — dim backdrop catches
    // outside clicks, card anchored top-right. Two sibling layer windows stack
    // unpredictably (the catcher ended up ABOVE the drawer eating its clicks).
    PanelWindow {
        id: panelWindow
        visible: root.panelOpen || closeAnim.running
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
            transformOrigin: Item.TopRight
            focus: visible
            anchors { top: parent.top; right: parent.right }
            anchors.topMargin: 52
            anchors.rightMargin: 8
            width: 380
            height: 520
            radius: 16
            color: colors.alpha(colors.surface, 0.52)
            border.width: 1
            border.color: colors.alpha(colors.outline, 0.15)

            // ESC closes any open panel (convention for all future panels)
            Keys.onEscapePressed: root.panelOpen = false

            transform: [
                Translate { id: drawerSlide },
                Scale { id: drawerScale; origin.x: drawer.width; origin.y: 0 }
            ]
            Component.onCompleted: drawerSlide.x = 20

            // bezier pair — open pops in with overshoot bounce (fast), close
            // hurries out the same path with no overshoot. Same curve family
            // as the bar; Bloom.spring is the bounce.
            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: drawer; property: "rotation"; from: Bloom.anchorRotate; to: 0; duration: Bloom.anchor; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
                NumberAnimation { target: drawerSlide; property: "x"; from: 20; to: 0; duration: Bloom.anchor; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
                NumberAnimation { target: drawer; property: "opacity"; from: 0; to: 1; duration: Bloom.normal; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
                NumberAnimation { target: drawerScale; property: "xScale"; from: Bloom.anchorScale; to: 1; duration: Bloom.anchor; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
                NumberAnimation { target: drawerScale; property: "yScale"; from: Bloom.anchorScale; to: 1; duration: Bloom.anchor; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
            }
            ParallelAnimation {
                id: closeAnim
                NumberAnimation { target: drawer; property: "rotation"; to: Bloom.anchorRotate; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
                NumberAnimation { target: drawerSlide; property: "x"; to: 20; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
                NumberAnimation { target: drawer; property: "opacity"; to: 0; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
                NumberAnimation { target: drawerScale; property: "xScale"; to: Bloom.anchorScale; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
                NumberAnimation { target: drawerScale; property: "yScale"; to: Bloom.anchorScale; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
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
                                            // Same classifier as the toast: history rows
                                            // get the semantic icon and accent colour.
                                            readonly property var drip: Drip.classify({
                                                appName: modelData.appName,
                                                summary: modelData.summary,
                                                body: modelData.body
                                            }, modelData.urgent)
                                            text: drip.glyph
                                            color: Drip.color(drip.kind)
                                            font.family: "Phosphor"
                                            font.pixelSize: 17
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
