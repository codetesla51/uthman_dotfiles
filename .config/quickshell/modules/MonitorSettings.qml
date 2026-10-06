import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// MonitorSettings — display controls (scale / orientation / mode line) in the
// segmented-pill design, themed off `colors`. Applies persistently via
// ~/.config/hypr/monitors-override.conf (sourced after monitors.conf) —
// a reload-repoll picks up the applied values, so no transient keywords.
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
    implicitHeight: col.implicitHeight + 48
    // pinned like the old module: without a fixed size the fillWidth segs
    // inside the fill-parent column form an implicit-size loop and the
    // window blows up to a tile. Hyprland rules pin the same 460x620.
    minimumSize: Qt.size(460, 620)
    maximumSize: Qt.size(460, 620)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here on purpose. shell.qml owns target "monitors"
    // and lazy-loads this module; a second handler for the same target wins
    // nothing and logs "registered but will not be used".
    onOpenChanged: {
        if (open) { syncing = true; load(); openAnim.restart() }
        else closeAnim.restart()
    }

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
    readonly property var dims: mon ? [mon.width, mon.height] : [1600, 900]
    readonly property bool portrait: orientVal === 1 || orientVal === 3
    readonly property int pw: portrait ? dims[1] : dims[0]
    readonly property int ph: portrait ? dims[0] : dims[1]

    // scale ladder + whole-pixel math from the sketch: offer the common rungs,
    // warn when the picked one doesn't divide the panel into whole pixels
    readonly property var scaleLadder: [1, 1.2, 1.25, 1.5, 1.75, 2]
    property real scaleVal: 1
    property int orientVal: 0
    // take values from the monitor until the user picks; the 1.5s re-poll
    // must not clobber a pick that hasn't applied yet
    property bool syncing: true
    function syncFromMon() {
        if (!mon || !syncing) return
        orientVal = mon.transform
        var best = 0, bd = 999
        for (var i = 0; i < scaleLadder.length; i++) {
            var d = Math.abs(scaleLadder[i] - mon.scale)
            if (d < bd) { bd = d; best = i }
        }
        scaleVal = scaleLadder[best]
    }
    onMonitorsChanged: syncFromMon()

    function whole(s) {
        var n = Math.round(s * 100)
        return (pw * 100) % n === 0 && (ph * 100) % n === 0
    }
    function nearest() {
        var best = -1, bd = 9
        for (var x = 100; x <= 200; x += 5) {
            var s = x / 100
            if (whole(s)) {
                var d = Math.abs(s - scaleVal)
                if (d < bd) { bd = d; best = s }
            }
        }
        return best
    }

    readonly property string value: (mon ? mon.name : "DP-1") + "," + currentMode() + ",0x0," + scaleVal + (orientVal ? ",transform," + orientVal : "")
    function apply() {
        if (!mon) return
        var cmd = "printf 'monitor = " + value + "\\n' > $HOME/.config/hypr/monitors-override.conf && hyprctl reload >/dev/null 2>&1"
        Quickshell.execDetached(["sh", "-c", cmd])
        reloadTimer.restart()
    }


    Timer { id: reloadTimer; interval: 900; onTriggered: load() }
    Timer { id: refreshTimer; interval: 1500; running: root.open; repeat: true; onTriggered: load() }

    component Seg: Rectangle {
        id: seg
        property var labels: []
        property int current: 0
        // orientation labels ("Portrait flip") outgrow a 13px segment, so
        // that row opts into 11px while the short rows stay at 13
        property int labelSize: 13
        signal picked(int index)
        implicitHeight: 44
        radius: height / 2
        color: colors.alpha(colors.background, 0.85)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.3)
        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 4
            Repeater {
                model: seg.labels
                Rectangle {
                    required property int index
                    required property var modelData
                    width: Math.max(1, (parent.width - (seg.labels.length - 1) * 4) / seg.labels.length)
                    height: parent.height
                    radius: height / 2
                    color: seg.current === index ? colors.primary : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: colors.fontSans
                        font.pixelSize: seg.labelSize
                        font.weight: Font.Medium
                        color: seg.current === index ? colors.background : colors.foreground
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: seg.picked(index)
                    }
                }
            }
        }
    }

    // glass card — anchors.fill so the hairline lands exactly on the window
    // edge. A fixed/inset card leaves a margin the compositor then frames,
    // which reads as a second border.
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 28
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
            id: col
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            // monitor switcher — only when there's more than one
            Seg {
                Layout.fillWidth: true
                visible: root.monitors.length > 1
                labels: { var a = []; for (var i = 0; i < root.monitors.length; i++) a.push(root.monitors[i].name); return a }
                current: root.selected
                onPicked: i => { root.selected = i; root.syncing = true; root.syncFromMon() }
            }

            RowLayout {
                spacing: 14
                Row {
                    spacing: 2
                    Text { text: String(root.scaleVal).replace(/\.0+$/, ""); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 76; font.weight: Font.Bold }
                    Text { text: "×"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 34; anchors.baseline: parent.children[0].baseline }
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: Math.round(root.pw / root.scaleVal) + " × " + Math.round(root.ph / root.scaleVal); color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 19; font.weight: Font.Medium }
                    Text { text: "usable desktop"; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 14 }
                }
            }

            Text { text: "Orientation"; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 14 }
            Seg {
                Layout.fillWidth: true
                labelSize: 11
                labels: ["Landscape", "Portrait", "Upside down", "Portrait flip"]
                current: root.orientVal
                onPicked: i => { root.orientVal = i; root.syncing = false }
            }

            Text { text: "Scale"; color: colors.alpha(colors.outline, 0.8); font.family: colors.fontSans; font.pixelSize: 14 }
            Seg {
                Layout.fillWidth: true
                labels: ["1", "1.2", "1.25", "1.5", "1.75", "2"]
                current: root.scaleLadder.indexOf(root.scaleVal)
                onPicked: i => { root.scaleVal = root.scaleLadder[i]; root.syncing = false }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.family: colors.fontSans
                font.pixelSize: 14
                color: root.whole(root.scaleVal) ? colors.alpha(colors.outline, 0.8) : colors.secondary
                text: root.whole(root.scaleVal)
                      ? "Whole pixels. Text stays sharp in every app."
                      : "Not a whole number of pixels, so some apps may look soft." + (root.nearest() > 0 ? " Try " + root.nearest() + " instead." : "")
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 26
                color: colors.alpha(colors.background, 0.85)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.3)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 6
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "monitor=" + root.value
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 12
                    }
                    Rectangle {
                        implicitWidth: 66
                        implicitHeight: 40
                        radius: 20
                        color: colors.primary
                        Text {
                            anchors.centerIn: parent
                            text: "Apply"
                            font.family: colors.fontSans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: colors.background
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.apply()
                        }
                    }
                }
            }
        }
    }
}
