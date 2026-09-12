import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// Workspace Viewer — fullscreen overview of every workspace with live
// mini-screen previews (windows laid out by their real geometry).
// Open: SUPER ALT O (hypr bind -> IpcHandler wsview). Click a card to jump
// & close; Esc/backdrop closes; Left/Right cycles workspaces and stays open;
// number keys 1-9 jump straight.
//
// State model: delegates must NEVER bind Quickshell.Hyprland objects
// directly — chained QS bindings (wsList.find().active etc.) freeze at
// creation-time values when change signals don't propagate. Instead we
// snapshot plain JS objects into wsDataMap on a 1s timer while open
// (same polling convention as NetRate/Colors) + on Hyprland raw events.
// Delegates read only the snapshot, so they can never go stale.
PanelWindow {
    id: root

    property var colors
    property bool open: false

    visible: root.open                    // fully gone when closed
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Exclusive grab: arrows/Esc/digits work the instant the viewer opens —
    // focusable alone leaves compositor focus on the app behind (keys lost)
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive


    IpcHandler {
        target: "wsview"
        function toggle(): void { root.open = !root.open }
    }


    // same id set as the bar's Workspaces pill: 1..5 always shown, extras appended
    readonly property var wsList: Hyprland.workspaces.values
    readonly property var shownIds: {
        var ids = {}
        for (var i = 1; i <= 5; i++) ids[i] = true
        for (var j = 0; j < wsList.length; j++)
            if (wsList[j].id > 0) ids[wsList[j].id] = true
        return Object.keys(ids).map(Number).sort(function(a, b) { return a - b })
    }
    readonly property int perRow: 3
    readonly property int rows: Math.max(1, Math.ceil(root.shownIds.length / root.perRow))
    readonly property int cellH: 216

    // plain-JS snapshot: {id: {active, urgent, monName, monX, monY, monW, monH, wins[]}}
    // wins[] entries: {cls, title, activated, urgent, gx, gy, gw, gh} (logical px, -1 = unknown)
    property var wsDataMap: ({})

    function refresh(): void {
        var fId = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.activeWorkspace.id : -1
        var tls = Hyprland.toplevels ? Hyprland.toplevels.values : []
        var map = {}
        for (var k = 0; k < root.shownIds.length; k++) {
            var id = root.shownIds[k]
            var w = null
            for (var j = 0; j < root.wsList.length; j++)
                if (root.wsList[j].id === id) { w = root.wsList[j]; break }
            var mon = w ? w.monitor : null
            var scale = (mon && mon.scale > 0) ? mon.scale : 1
            var wins = []
            for (var i = 0; i < tls.length; i++) {
                var t = tls[i]
                if (!t || !t.workspace || t.workspace.id !== id) continue
                var raw = t.lastIpcObject
                if (!raw || raw.hidden === true) continue
                // hypr IPC uses at:[x,y] + size:[w,h] (logical px), not `geometry`
                var at = raw.at, sz = raw.size
                var hasGeom = at && at.length >= 2 && sz && sz.length >= 2
                wins.push({
                    addr: raw.address || "",
                    cls: raw.class || raw.initialClass || "",
                    title: t.title || raw.title || "",
                    activated: !!t.activated,
                    urgent: !!t.urgent,
                    gx: hasGeom ? at[0] : -1, gy: hasGeom ? at[1] : -1,
                    gw: hasGeom ? sz[0] : 0, gh: hasGeom ? sz[1] : 0
                })
            }
            map[String(id)] = {
                active: ((w && w.active) ? true : false) || id === fId,
                urgent: !!((w && w.urgent) ? true : false),
                monName: mon ? mon.name : "",
                monX: mon ? mon.x / scale : 0,
                monY: mon ? mon.y / scale : 0,
                monW: mon ? mon.width / scale : 1920,
                monH: mon ? mon.height / scale : 1080,
                wins: wins
            }
        }
        root.wsDataMap = map
    }

    Timer {
        interval: 1000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (root.open) root.refresh() }
    }
    onOpenChanged: if (root.open) { root.refresh(); card.forceActiveFocus() }

    function jumpTo(id: int): void {
        Hyprland.dispatch("workspace " + id)
        root.open = false
    }
    function cycle(dir: int): void {
        var ids = root.shownIds
        var mon = Hyprland.focusedMonitor
        var fId = (mon && mon.activeWorkspace) ? mon.activeWorkspace.id : -1
        var cur = ids.indexOf(fId)
        if (cur < 0) cur = 0
        Hyprland.dispatch("workspace " + ids[(cur + dir + ids.length) % ids.length])
    }

    // dimmed backdrop — click to dismiss
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.55 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    // centered card; height follows the grid row count
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 960
        height: 84 + root.rows * root.cellH + (root.rows - 1) * 14
        radius: 20
        color: colors.alpha(colors.background, 0.97)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.3)
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.92
        focus: root.open
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: root.open = false
        Keys.onLeftPressed: root.cycle(-1)
        Keys.onRightPressed: root.cycle(1)
        Keys.onPressed: (event) => {
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                var id = event.key - Qt.Key_1 + 1
                if (root.shownIds.indexOf(id) !== -1) {
                    if ((event.modifiers & Qt.ShiftModifier) !== 0)
                        Hyprland.dispatch("movetoworkspace " + id)  // throw focused window there, stay open
                    else
                        root.jumpTo(id)
                    event.accepted = true
                }
            }
        }

        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
            spacing: 14

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "󰮯 Workspaces"
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.2
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "← → cycle · 1-9 jump · SHIFT+1-9 move window · click focuses · ESC"
                    color: colors.alpha(colors.outline, 0.55)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }

            // workspace grid
            Flow {
                id: grid
                Layout.fillWidth: true
                Layout.preferredHeight: root.rows * root.cellH + (root.rows - 1) * 14
                spacing: 14

                Repeater {
                    model: root.shownIds

                    delegate: Rectangle {
                        id: cell

                        required property var modelData
                        readonly property int wsId: modelData
                        // snapshot lookup — plain JS, refreshed by timer/events
                        readonly property var d: root.wsDataMap[String(wsId)] ?? null
                        readonly property bool isActive: d ? d.active : false
                        readonly property bool isUrgent: d ? d.urgent : false
                        readonly property var wins: d ? d.wins : []
                        readonly property bool hovered: cellMouse.containsMouse
                        readonly property real stageW: cell.width - 24
                        readonly property real stageH: 96
                        readonly property var tiles: {
                            var out = []
                            if (!d) return out
                            for (var i = 0; i < wins.length; i++) {
                                var win = wins[i]
                                if (win.gx < 0 || win.gw <= 0 || win.gh <= 0) continue
                                out.push({
                                    x: (win.gx - d.monX) / d.monW,
                                    y: (win.gy - d.monY) / d.monH,
                                    w: win.gw / d.monW,
                                    h: win.gh / d.monH,
                                    activated: win.activated,
                                    urgent: win.urgent
                                })
                            }
                            return out
                        }

                        width: (grid.width - 2 * 14) / root.perRow
                        height: root.cellH
                        radius: 16
                        color: cell.isActive ? "transparent"
                             : cell.hovered ? colors.alpha(colors.primary, 0.14)
                             : colors.alpha(colors.surfaceVariant, 0.35)
                        border.width: 1
                        border.color: cell.isUrgent ? colors.error
                             : cell.isActive ? "transparent"
                             : cell.hovered ? colors.alpha(colors.primary, 0.45)
                             : colors.alpha(colors.outline, 0.2)
                        // hover lift via transform — NEVER y: on a Flow child,
                        // the positioner owns x/y and relayouts (rows collapse)
                        transform: Translate {
                            y: cell.hovered ? -3 : 0
                            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        scale: cell.hovered ? 1.03 : 1
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        // active glow (box-shadow stand-in)
                        Rectangle {
                            visible: cell.isActive
                            anchors.fill: parent
                            radius: 16
                            y: 3
                            z: -1
                            color: colors.alpha(colors.primary, 0.4)
                        }

                        // active gradient fill
                        Rectangle {
                            visible: cell.isActive
                            anchors.fill: parent
                            radius: 16
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: colors.primary }
                                GradientStop { position: 1; color: colors.alpha(colors.secondary, 0.9) }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            // header: WS id · count+monitor chip (no glyphs)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: "WS " + cell.wsId
                                    color: cell.isActive ? colors.background
                                         : cell.hovered ? colors.foreground
                                         : colors.alpha(colors.foreground, 0.85)
                                    font.family: colors.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.ExtraBold
                                    font.letterSpacing: 0.5
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    Layout.preferredHeight: 18
                                    Layout.preferredWidth: Math.min(tagText.implicitWidth + 14, 140)
                                    Layout.alignment: Qt.AlignVCenter
                                    radius: 9
                                    clip: true
                                    color: cell.isActive ? colors.alpha(colors.background, 0.2)
                                         : cell.hovered ? colors.alpha(colors.primary, 0.12)
                                         : colors.alpha(colors.surfaceVariant, 0.4)
                                    border.width: 1
                                    border.color: cell.isActive ? colors.alpha(colors.background, 0.25)
                                         : colors.alpha(colors.outline, 0.15)

                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        width: Math.min(implicitWidth, 126)
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        text: cell.wins.length + (cell.wins.length === 1 ? " win" : " wins")
                                              + ((d && d.monName !== "") ? " · " + d.monName.toUpperCase() : "")
                                        color: cell.isActive ? colors.alpha(colors.background, 0.75)
                                             : colors.alpha(colors.outline, 0.7)
                                        font.family: colors.fontSans
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            // mini-screen preview
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: cell.stageH
                                radius: 10
                                color: cell.isActive ? colors.alpha(colors.background, 0.18)
                                     : cell.hovered ? colors.alpha(colors.background, 0.55)
                                     : colors.alpha(colors.background, 0.5)
                                border.width: 1
                                border.color: cell.isActive ? colors.alpha(colors.background, 0.2)
                                     : colors.alpha(colors.outline, 0.15)
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    clip: true

                                    Repeater {
                                        model: cell.tiles

                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property real scaleX: parent.width
                                            readonly property real scaleY: parent.height
                                            x: Math.max(0, Math.min(scaleX - 2, modelData.x * scaleX))
                                            y: Math.max(0, Math.min(scaleY - 2, modelData.y * scaleY))
                                            width: Math.max(6, Math.min(scaleX, modelData.w * scaleX))
                                            height: Math.max(6, Math.min(scaleY, modelData.h * scaleY))
                                            radius: 4
                                            color: modelData.urgent ? colors.alpha(colors.error, 0.75)
                                                 : modelData.activated ? colors.alpha(colors.primary, 0.85)
                                                 : cell.isActive ? colors.alpha(colors.background, 0.55)
                                                 : colors.alpha(colors.foreground, 0.45)
                                            border.width: modelData.activated ? 2 : 0
                                            border.color: modelData.activated
                                                 ? (cell.isActive ? colors.background : colors.primary)
                                                 : "transparent"
                                        }
                                    }

                                    // empty state
                                    ColumnLayout {
                                        visible: cell.tiles.length === 0
                                        anchors.centerIn: parent
                                        spacing: 4


                                        Text {
                                            text: "EMPTY"
                                            Layout.alignment: Qt.AlignHCenter
                                            color: cell.isActive ? colors.alpha(colors.background, 0.5)
                                                 : colors.alpha(colors.outline, 0.35)
                                            font.family: colors.fontSans
                                            font.pixelSize: 7
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.5
                                        }
                                    }
                                }
                            }

                            // window list — every window on the workspace, up to 3 + more
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 57
                                spacing: 2

                                Repeater {
                                    model: cell.wins.slice(0, 3)

                                    delegate: Item {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 15

                                        Text {
                                            anchors.fill: parent
                                            verticalAlignment: Text.AlignVCenter
                                            text: (modelData.cls || "?")
                                                  + (modelData.title ? "  ·  " + modelData.title : "")
                                            elide: Text.ElideRight
                                            color: modelData.activated ? colors.primary
                                                 : modelData.urgent ? colors.error
                                                 : cell.isActive ? colors.alpha(colors.background, 0.8)
                                                 : cell.hovered ? colors.alpha(colors.foreground, 0.9)
                                                 : colors.alpha(colors.foreground, 0.65)
                                            font.family: colors.fontSans
                                            font.pixelSize: 9
                                            font.weight: modelData.activated ? Font.DemiBold : Font.Medium
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                            onClicked: (mouse) => {
                                                if (!modelData.addr) return
                                                if (mouse.button === Qt.MiddleButton)
                                                    Hyprland.dispatch("closewindow address:" + modelData.addr)
                                                else {
                                                    Hyprland.dispatch("focuswindow address:" + modelData.addr)
                                                    root.open = false
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: cell.wins.length > 3
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 12
                                    text: "+" + (cell.wins.length - 3) + " more"
                                    color: cell.isActive ? colors.alpha(colors.background, 0.55)
                                         : colors.alpha(colors.outline, 0.5)
                                    font.family: colors.fontSans
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                }

                                Text {
                                    visible: cell.wins.length === 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 15
                                    text: cell.isActive ? "CURRENT" : "CLICK TO OPEN"
                                    color: cell.isActive ? colors.alpha(colors.background, 0.6)
                                         : colors.alpha(colors.outline, 0.4)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    font.weight: Font.Medium
                                }
                            }
                        }

                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.jumpTo(cell.wsId)
                        }
                    }
                }
            }
        }
    }
}