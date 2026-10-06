import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Earbuds — bluetooth headset battery panel. Data comes from the stack itself:
// bluetoothctl for pairing/connection, UPower for battery levels. No vendor
// apps, no daemons. Up to three battery devices map to Left/Right/Case in the
// order found; missing ones read "–". ANC/mode buttons are intentionally
// absent — no generic BlueZ API drives them, and dead buttons are worse.
// Bud hardware stays fixed white/gray (object colors, not theme); all UI
// chrome follows `colors`.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string fontUi: "JetBrainsMono Nerd Font Mono"
    // Phosphor icon face (verified codepoints against the installed build:
    // bluetooth E0DA, bluetooth-connected E0DC, x E4F6)
    property string fontIcon: "Phosphor"

    title: "Earbuds"
    implicitWidth: 380
    implicitHeight: 460
    minimumSize: Qt.size(380, 460)
    maximumSize: Qt.size(380, 460)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here on purpose. shell.qml owns target "earbuds"
    // and lazy-loads this module; a second handler for the same target wins
    // nothing and logs "registered but will not be used".

    // ── state ──
    property string mac: ""
    property string devName: "No earbuds"
    property bool connected: false
    property bool busy: false
    // batteries in L/R/C order: {pct: -1|0..100, charging: bool}
    property var bats: [{pct: -1, charging: false}, {pct: -1, charging: false}, {pct: -1, charging: false}]
    function level(i) { return (i >= 0 && i < bats.length) ? bats[i].pct : -1 }
    function charging(i) { return (i >= 0 && i < bats.length) ? bats[i].charging : false }
    function levelColor(p) {
        if (p < 0) return colors.alpha(colors.outline, 0.4)
        if (p <= 20) return colors.error
        if (p <= 40) return colors.secondary
        return colors.primary
    }

    onOpenChanged: { if (open) { probe(); openAnim.restart() } else closeAnim.restart() }
    Timer { id: pollTimer; interval: 10000; running: root.open && !root.busy; repeat: true; onTriggered: root.probe() }

    function probe() {
        if (root.busy) return
        devProc.running = true
    }

    // 1. paired devices -> pick target (connected one, else first paired)
    Process {
        id: devProc
        command: ["sh", "-c", "timeout 8 bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var first = "", fname = ""
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$/)
                    if (m) {
                        if (!first) { first = m[1]; fname = m[2].trim() }
                    }
                }
                if (!first) {
                    root.mac = ""; root.devName = "No earbuds"; root.connected = false
                    root.bats = [{pct: -1, charging: false}, {pct: -1, charging: false}, {pct: -1, charging: false}]
                    return
                }
                root.mac = first
                root.devName = fname || first
                infoProc.running = true
                upProc.running = true
            }
        }
    }
    // 2a. connection state for the target
    Process {
        id: infoProc
        command: ["sh", "-c", "timeout 8 bluetoothctl info '" + root.mac.replace(/'/g, "'\\''") + "' 2>/dev/null | grep -i 'Connected:'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { root.connected = text.toLowerCase().indexOf("yes") !== -1 }
        }
    }
    // 2b. batteries via one upower dump, blocks matched by MAC
    Process {
        id: upProc
        command: ["sh", "-c", "timeout 8 upower -d 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var flat = root.mac.replace(/:/g, "_").toLowerCase()
                var blocks = text.split("\n\n")
                var found = []
                for (var i = 0; i < blocks.length; i++) {
                    var b = blocks[i]
                    if (b.toLowerCase().indexOf(flat) === -1) continue
                    var pm = b.match(/percentage:\s*([0-9]+)%/)
                    var sm = b.match(/state:\s*([a-z-]+)/)
                    if (pm) found.push({
                        pct: parseInt(pm[1]),
                        charging: !!sm && (sm[1] === "charging" || sm[1] === "fully-charged")
                    })
                }
                while (found.length < 3) found.push({pct: -1, charging: false})
                root.bats = found.slice(0, 3)
            }
        }
    }

    function setBusy(b, label) {
        root.busy = b
        if (label !== undefined) statusText = label
    }
    property string statusText: ""
    function actClicked() {
        if (root.busy || !root.mac) return
        var cmd = root.connected ? "disconnect" : "connect"
        root.setBusy(true, root.connected ? "Disconnecting…" : "Connecting…")
        linkProc.command = ["sh", "-c", "timeout 15 bluetoothctl " + cmd + " '" + root.mac.replace(/'/g, "'\\''") + "' >/dev/null 2>&1"]
        linkProc.running = true
    }
    Process {
        id: linkProc
        onExited: {
            root.setBusy(false)
            root.statusText = ""
            probeTimer.restart()
        }
    }
    Timer { id: probeTimer; interval: 1200; onTriggered: root.probe() }

    // glass card
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 22
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
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

        // one bud: progress ring + earbud shapes + pct + bolt
        component Bud: Item {
            id: bud
            property int slot: 0          // 0 L, 1 R
            property bool mirror: false
            width: 130; height: 196
            property real pct: root.level(slot)
            property bool chg: root.charging(slot)
            property bool dim: !root.connected || root.busy
            // sonar ring (behind, only while connected and idle)
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -32
                    width: 120; height: 120; radius: 60
                    color: "transparent"
                    border.width: 1.5
                    border.color: colors.primary
                    opacity: 0
                    SequentialAnimation {
                        running: root.connected && !root.busy && root.open
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 1400 }
                        ParallelAnimation {
                            NumberAnimation { target: parent; property: "scale"; from: 0.3; to: 1.6; duration: 2800; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.6, 0.3, 1] }
                            SequentialAnimation {
                                NumberAnimation { target: parent; property: "opacity"; to: 0.45; duration: 200 }
                                NumberAnimation { target: parent; property: "opacity"; to: 0; duration: 2600 }
                            }
                        }
                    }
                }
            }
            // progress ring
            Canvas {
                id: ring
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                width: 124; height: 124
                Connections { target: root; function onBatsChanged() { ring.requestPaint() } }
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var cx = width / 2, cy = height / 2, r = 57
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                    ctx.strokeStyle = colors.alpha(colors.surfaceVariant, 0.6)
                    ctx.lineWidth = 5
                    ctx.stroke()
                    if (bud.pct >= 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * bud.pct / 100)
                        ctx.strokeStyle = root.levelColor(bud.pct)
                        ctx.lineWidth = 5
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }
            }
            // earbud body: stem + head + mesh (fixed hardware whites)
            Item {
                id: budBody
                anchors.horizontalCenter: parent.horizontalCenter
                y: 34
                width: 60; height: 72
                rotation: bud.mirror ? 9 : -9
                opacity: bud.dim ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: 400 } }
                SequentialAnimation {
                    running: root.busy
                    loops: Animation.Infinite
                    NumberAnimation { target: budBody; property: "opacity"; to: 0.45; duration: 450; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: budBody; property: "opacity"; to: 1; duration: 450; easing.type: Easing.InOutQuad }
                }
                // float bob
                SequentialAnimation {
                    running: root.connected && !root.busy
                    loops: Animation.Infinite
                    PauseAnimation { duration: bud.mirror ? 2500 : 0 }
                    NumberAnimation { target: budBody; property: "y"; to: 29; duration: 2500; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: budBody; property: "y"; to: 34; duration: 2500; easing.type: Easing.InOutQuad }
                }
                Rectangle { // stem
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6; width: 16; height: 60; radius: 8
                    color: "#d7dedb"
                    border.width: 1; border.color: "#a9b8b3"
                }
                Rectangle { // head
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: bud.mirror ? 7 : -7
                    y: -4; width: 56; height: 56; radius: 28
                    color: "#f4f7f5"
                    border.width: 1; border.color: "#a9b8b3"
                }
                Rectangle { // mesh
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: bud.mirror ? 16 : -16
                    y: 8; width: 12; height: 12; radius: 6
                    color: "#26353a"
                }
            }
            // bolt while charging
            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: bud.mirror ? 14 : -14
                y: 44
                width: 16; height: 22
                visible: root.connected && bud.chg
                opacity: 1
                SequentialAnimation {
                    running: visible
                    loops: Animation.Infinite
                    NumberAnimation { target: parent; property: "opacity"; to: 0.35; duration: 800 }
                    NumberAnimation { target: parent; property: "opacity"; to: 1; duration: 800 }
                }
                onVisibleChanged: if (visible) requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.beginPath()
                    ctx.moveTo(11, 0); ctx.lineTo(4, 0); ctx.lineTo(0, 11)
                    ctx.lineTo(5, 11); ctx.lineTo(2, 20); ctx.lineTo(11, 8)
                    ctx.lineTo(6, 8); ctx.closePath()
                    ctx.fillStyle = colors.secondary
                    ctx.fill()
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 142
                text: bud.pct < 0 ? "–" : Math.round(bud.pct) + "%"
                color: colors.foreground
                font.family: root.fontUi; font.pixelSize: 30
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 172
                text: bud.slot === 0 ? "Left" : "Right"
                color: colors.alpha(colors.outline, 0.7)
                font.family: root.fontUi; font.pixelSize: 12
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 16

            // top: rune + name/status + close
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: root.connected ? "" : ""; color: root.connected ? colors.primary : colors.alpha(colors.outline, 0.5); font.family: root.fontIcon; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Text { text: root.devName; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                    RowLayout { spacing: 6
                        Rectangle { width: 7; height: 7; radius: 3.5; color: root.busy ? colors.secondary : (root.connected ? colors.primary : colors.alpha(colors.outline, 0.5)); Layout.alignment: Qt.AlignVCenter
                            SequentialAnimation {
                                running: root.connected && !root.busy
                                loops: Animation.Infinite
                                NumberAnimation { target: parent; property: "opacity"; to: 0.35; duration: 1000 }
                                NumberAnimation { target: parent; property: "opacity"; to: 1; duration: 1000 }
                            }
                        }
                        Text { text: root.busy ? root.statusText : (root.connected ? "Connected" : (root.mac === "" ? "No earbuds paired" : "Disconnected")); color: colors.alpha(colors.outline, 0.75); font.family: root.fontUi; font.pixelSize: 12 }
                    }
                }
                            }

            // buds side by side
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Bud { slot: 0; mirror: false }
                Bud { slot: 1; mirror: true }
            }

            // case row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle { width: 30; height: 22; radius: 6; color: "transparent"; border.width: 2; border.color: colors.alpha(colors.outline, 0.6); Layout.alignment: Qt.AlignVCenter
                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 2; color: colors.alpha(colors.outline, 0.6) } }
                Text { text: "Case"; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 14; Layout.alignment: Qt.AlignVCenter }
                Rectangle {
                    Layout.fillWidth: true; height: 8; radius: 4
                    color: colors.alpha(colors.surfaceVariant, 0.55)
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: root.level(2) < 0 ? 0 : parent.width * root.level(2) / 100
                        radius: 4
                        color: root.levelColor(root.level(2))
                    }
                }
                Text { text: root.level(2) < 0 ? "–" : Math.round(root.level(2)) + "%"; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 20; Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }
            }

            // foot: address + connect/disconnect
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: root.mac === "" ? "bluetooth off or nothing paired" : root.mac; color: colors.alpha(colors.outline, 0.6); font.family: root.fontUi; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    width: 124; height: 36; radius: 10
                    color: actMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.7) : colors.alpha(colors.surfaceVariant, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.2)
                    opacity: root.mac === "" ? 0.45 : 1
                    Text { anchors.centerIn: parent; text: root.connected ? "Disconnect" : "Connect"; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { id: actMa; anchors.fill: parent; hoverEnabled: true; enabled: root.mac !== ""; onClicked: root.actClicked() }
                }
            }
        }
    }
}
