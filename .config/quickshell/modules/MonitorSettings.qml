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

    property var colors
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
    visible: root.open

    IpcHandler { target: "monitors"; function toggle(): void { root.open = !root.open; if (root.open) load() } }

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
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
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

            // scale — the one real control: a group of boxes, pick one
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: root.scaleSteps
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: index === root.scaleIdx()

                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 44
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

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    RowLayout {
                        anchors.fill: parent
                        spacing: 6
                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: "ROT"
                                color: colors.alpha(colors.outline, 0.55)
                                font.family: colors.fontSans
                                font.pixelSize: 7
                                font.weight: Font.Bold
                                font.letterSpacing: 1.3
                            }
                            Text {
                                text: mon ? (mon.transform * 90) + "°" : "—"
                                color: colors.alpha(colors.foreground, 0.9)
                                font.family: colors.fontSans
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 52
                            Layout.preferredHeight: 22
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

                Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter; color: colors.alpha(colors.outline, 0.12) }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 2
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
                        anchors.fill: parent
                        spacing: 2
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
