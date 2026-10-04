import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// MonitorSettings — small live monitor controls for Hyprland.
// Applies via ~/.config/hypr/monitors-override.conf (sourced after monitors.conf)
// + hyprctl reload. No heavy UI, esc/click-outside to close.
FloatingWindow {
    id: root

    // Fallback palette so colors.* reads never throw during startup:
    // the external `colors` assignment lands after our bindings first
    // evaluate, and one throw aborts setup of the whole shell.
    QtObject {
        id: fallback
        property color background: "#17130f"
        property color foreground: "#ebe1da"
        property color primary: "#f3bc87"
        property color secondary: "#dfc1a8"
        property color tertiary: "#9bcee3"
        property color error: "#ffb4ab"
        property color surface: "#17130f"
        property color on_surface: "#efe5df"
        property color surfaceVariant: "#50453b"
        property color outline: "#a39487"
        function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    }
    property var colors: fallback
    property bool open: false
    property var monitors: []
    property int selected: 0
    readonly property var mon: (selected >= 0 && selected < monitors.length) ? monitors[selected] : null

    title: "Monitors"
    implicitWidth: 420
    implicitHeight: 240
    minimumSize: Qt.size(420, 240)
    maximumSize: Qt.size(420, 240)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here on purpose. shell.qml owns target "monitors"
    // and lazy-loads this module; a second handler for the same target wins
    // nothing and logs "registered but will not be used".
    onOpenChanged: { if (open) { load(); openAnim.restart() } else closeAnim.restart() }

    Process {
        id: loadProc
        command: ["sh", "-c", "hyprctl monitors -j 2>/dev/null"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.monitors = JSON.parse(text) } catch (e) { root.monitors = [] }
        } }
    }
    function load() { loadProc.running = true }

    function name(i) { return i >= 0 && i < monitors.length ? monitors[i].name : "" }
    function currentMode() {
        if (!mon) return "preferred"
        return mon.width + "x" + mon.height + "@" + Math.round(mon.refreshRate)
    }
    // Scale ladder — every value here divides the panel width into a whole
    // number of pixels. Hyprland snaps any other scale to the nearest ratio
    // that does (1.1 -> 1.2 on 1920, because 1920/1.1 = 1745.45), so offering
    // it would just be a box that silently does nothing.
    readonly property var scaleSteps: [1.0, 1.2, 1.25, 1.5, 1.6, 2.0]
    function scaleIdx() {
        if (!mon) return 1
        var best = 0, bd = 999
        for (var i = 0; i < scaleSteps.length; i++) {
            var d = Math.abs(scaleSteps[i] - mon.scale)
            if (d < bd) { bd = d; best = i }
        }
        return best
    }
    function apply(scale, transform) {
        if (!mon) return
        var name = mon.name
        var mode = currentMode()
        var cmd = "printf 'monitor = " + name + ", " + mode + ", auto, " + scale + ", transform, " + transform + "\\n' > $HOME/.config/hypr/monitors-override.conf && hyprctl reload >/dev/null 2>&1"
        Quickshell.execDetached(["sh", "-c", cmd])
        reloadTimer.restart()
    }
    function adjustScale(dir) {
        var i = Math.min(Math.max(0, scaleIdx() + dir), scaleSteps.length - 1)
        apply(scaleSteps[i], mon ? mon.transform : 0)
    }
    function rotate() { apply(mon ? mon.scale : 1.2, mon ? (mon.transform + 1) % 4 : 0) }

    Timer { id: reloadTimer; interval: 900; onTriggered: load() }
    Timer { id: refreshTimer; interval: 1500; running: root.open; repeat: true; onTriggered: load() }

    // glass card — anchors.fill so the hairline lands exactly on the window
    // edge (same as every other card). A fixed/inset card leaves a margin the
    // compositor then frames, which reads as a second border. Scale boxes use
    // preferredWidth, not fillWidth — fillWidth children inside a fill-parent
    // column form a circular implicit-size loop that pins the window to max.
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        // bezier pair — open pops with overshoot bounce, close hurries out
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // header — monitor identity + attached count
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: mon ? (mon.description || mon.name) : "No monitor"
                    color: colors.alpha(colors.foreground, 0.9)
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: root.monitors.length + " attached"
                    color: colors.alpha(colors.outline, 0.45)
                    font.family: colors.fontSans
                    font.pixelSize: 7
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }

            // monitor picker — only worth the row with 2+ displays
            RowLayout {
                Layout.fillWidth: true
                visible: root.monitors.length > 1
                spacing: 6
                Repeater {
                    model: root.monitors.length
                    delegate: Rectangle {
                        required property int index
                        readonly property bool on: root.selected === index
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: Math.max(60, mname.implicitWidth + 20)
                        radius: 11
                        color: on ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.surfaceVariant, 0.3)
                        border.width: 1
                        border.color: on ? colors.alpha(colors.primary, 0.3) : colors.alpha(colors.outline, 0.12)
                        Behavior on color { ColorAnimation { duration: 180 } }
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                        Text {
                            id: mname
                            anchors.centerIn: parent
                            text: root.monitors[index] ? root.monitors[index].name : ""
                            color: parent.on ? colors.primary : colors.alpha(colors.foreground, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.selected = index }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // scale — the one real control: a group of boxes, pick one.
            // Plain Row with explicit sizes: a RowLayout here let the boxes
            // grow past the card edge and cut the 2.00 box off.
            // 6*52 + 5*5 = 337 < 396 usable. No layout engine, no drift.
            Row {
                spacing: 5
                Repeater {
                    model: root.scaleSteps
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: index === root.scaleIdx()

                        width: 52
                        height: 44
                        radius: 9
                        color: on ? "transparent" : colors.alpha(colors.surfaceVariant, 0.3)
                        border.width: 1
                        border.color: on ? "transparent" : colors.alpha(colors.outline, 0.12)
                        y: boxMa.containsMouse ? -2 : 0
                        scale: boxMa.containsMouse ? 1.04 : 1.0
                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on border.color { ColorAnimation { duration: 200 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 9
                            visible: parent.on
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: colors.primary }
                                GradientStop { position: 1; color: colors.alpha(colors.secondary, 0.9) }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Number(modelData).toFixed(2)
                            color: parent.on ? colors.background : colors.alpha(colors.foreground, 0.75)
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            id: boxMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.apply(modelData, root.mon ? root.mon.transform : 0)
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // facts — three compact cells, dividers are siblings
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                spacing: 0

                // Plain Item cell, so inner content may use anchors — the rule
                // is only "no anchors.* on children OF a layout", and the
                // anchors.verticalCenter ColumnLayout that was here (child
                // of a RowLayout) blew the whole row's geometry out.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: "ROT"
                            color: colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans
                            font.pixelSize: 7
                            font.weight: Font.Bold
                            font.letterSpacing: 1.3
                        }
                        // Plain Row, explicit sizes — same reason as the
                        // scale boxes above: no layout engine, no drift.
                        Row {
                            spacing: 6
                            Text {
                                text: mon ? (mon.transform * 90) + "°" : "—"
                                color: colors.alpha(colors.foreground, 0.9)
                                font.family: colors.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                width: 52
                                height: 22
                                radius: 11
                                color: rotMa.containsMouse ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.surfaceVariant, 0.3)
                                border.width: 1
                                border.color: colors.alpha(colors.outline, 0.12)
                                y: rotMa.containsMouse ? -2 : 0
                                Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 140 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "turn"
                                    color: colors.alpha(colors.foreground, 0.8)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                                MouseArea {
                                    id: rotMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.rotate()
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline, 0.12) }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: "MODE"
                            color: colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans
                            font.pixelSize: 7
                            font.weight: Font.Bold
                            font.letterSpacing: 1.3
                        }
                        Text {
                            Layout.fillWidth: true
                            text: mon ? currentMode() : "—"
                            color: colors.alpha(colors.foreground, 0.9)
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline, 0.12) }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: "STATE"
                            color: colors.alpha(colors.outline, 0.55)
                            font.family: colors.fontSans
                            font.pixelSize: 7
                            font.weight: Font.Bold
                            font.letterSpacing: 1.3
                        }
                        Text {
                            Layout.fillWidth: true
                            text: mon ? (mon.disabled ? "off" : "on") : "—"
                            color: mon && mon.disabled ? colors.error : colors.alpha(colors.secondary, 0.95)
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
