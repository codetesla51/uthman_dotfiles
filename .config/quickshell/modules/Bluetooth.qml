import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Bluetooth — adapter power, scan, pair/connect/disconnect/forget.
// Talks to BlueZ through bluetoothctl only (no daemons, no blueman dep).
// Pairing uses JustWorks-friendly `pair` + auto-`trust`; devices that demand
// a PIN/passkey report the failure in the status line instead of hanging —
// answer it in blueman-manager, which is installed as the fallback.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string fontUi: "JetBrainsMono Nerd Font Mono"
    // Phosphor icon face (codepoints verified against the installed build)
    property string fontIcon: "Phosphor"

    title: "Bluetooth"
    implicitWidth: 440
    implicitHeight: 560
    minimumSize: Qt.size(440, 560)
    maximumSize: Qt.size(440, 560)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here on purpose. shell.qml owns target "bluetooth"
    // and lazy-loads this module; a second handler for the same target wins
    // nothing and logs "registered but will not be used".

    property bool powered: false
    property bool scanning: false
    property var devices: []   // {mac, name, paired, connected, trusted, rssi, battery}
    property string statusMsg: ""
    property string busyMac: ""  // device with an in-flight action (spinner state)
    // pods-only smart connect: nothing else gets auto-touch, hangs get killed
    property string podsMac: "41:42:18:25:3A:8E"
    property string podsName: "Max AirPro"
    property bool podsPending: false   // power-on chained connect

    onOpenChanged: { if (open) { refresh(); openAnim.restart() } else { scanStop(); closeAnim.restart() } }
    Timer { id: pollTimer; interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }

    function sh(cmd) { return ["sh", "-c", "timeout 10 " + cmd + " 2>/dev/null"] }

    function refresh() {
        if (!root.open) return
        powProc.running = true
        devProc.running = true
    }

    // adapter power state
    Process {
        id: powProc
        command: ["sh", "-c", "timeout 8 bluetoothctl show 2>/dev/null | grep -i 'Powered:'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.powered = text.toLowerCase().indexOf("yes") !== -1
                if (root.powered && root.podsPending) { root.podsPending = false; root.connectPods() }
            }
        }
    }
    function setPower(on) {
        root.statusMsg = on ? "Powering on…" : "Powering off…"
        powSetProc.command = ["sh", "-c", "timeout 8 bluetoothctl power " + (on ? "on" : "off") + " >/dev/null 2>&1"]
        powSetProc.running = true
    }
    Process {
        id: powSetProc
        onExited: { root.refresh(); root.statusMsg = "" }
    }

    // paired + nearby devices (a scan populates the BlueZ cache; `devices`
    // then lists everything found, no scan-output parsing needed)
    Process {
        id: devProc
        command: ["sh", "-c", "timeout 8 bluetoothctl devices 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var macs = []
                var names = {}
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$/)
                    if (m && macs.indexOf(m[1]) === -1) { macs.push(m[1]); names[m[1]] = m[2].trim() }
                }
                if (!macs.length) { root.devices = []; return }
                infoAccum = []
                infoQueue = macs.slice()
                infoNames = names
                infoNext()
            }
        }
    }
    property var infoQueue: []
    property var infoNames: ({})
    property var infoAccum: []
    function infoNext() {
        if (!infoQueue.length) { root.devices = infoAccum; return }
        var mac = infoQueue[0]
        infoProc.command = ["sh", "-c", "timeout 8 bluetoothctl info '" + mac.replace(/'/g, "'\\''") + "' 2>/dev/null"]
        infoProc.running = true
    }
    Process {
        id: infoProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var mac = infoQueue.length ? infoQueue.shift() : ""
                var t = text
                function yn(re) { var m = t.match(re); return !!m && m[1].toLowerCase() === "yes" }
                var bm = t.match(/Battery Percentage:\s*(?:0x[0-9a-fA-F]+\s*)?\(?\s*([0-9]+)/)
                var rm = t.match(/RSSI:\s*(-?[0-9]+)/)
                infoAccum.push({
                    mac: mac,
                    name: infoNames[mac] || mac,
                    paired: yn(/Paired:\s*(yes|no)/i),
                    connected: yn(/Connected:\s*(yes|no)/i),
                    trusted: yn(/Trusted:\s*(yes|no)/i),
                    rssi: rm ? parseInt(rm[1]) : 0,
                    battery: bm ? parseInt(bm[1]) : -1
                })
                infoNext()
            }
        }
    }

    // scan: 12s discovery in the background, re-list at 4/8/12s as the cache fills
    function scanStart() {
        if (root.scanning || !root.powered) return
        root.scanning = true
        root.statusMsg = "Scanning…"
        scanProc.running = true
        scanTick1.restart()
        scanTick2.restart()
        scanTick3.restart()
    }
    function scanStop() {
        scanProc.running = false
        scanTick1.stop(); scanTick2.stop(); scanTick3.stop()
        if (root.scanning) { root.scanning = false; root.statusMsg = "" }
    }
    Process { id: scanProc; command: ["sh", "-c", "timeout 13 bluetoothctl scan on >/dev/null 2>&1"] ; onExited: { root.scanning = false; root.statusMsg = ""; root.refresh() } }
    Timer { id: scanTick1; interval: 4000; onTriggered: devProc.running = true }
    Timer { id: scanTick2; interval: 8000; onTriggered: devProc.running = true }
    Timer { id: scanTick3; interval: 12000; onTriggered: devProc.running = true }

    // per-device actions; result lands in the status line, list refreshes after
    function act(mac, what) {
        root.busyMac = mac
        root.statusMsg = {pair: "Pairing…", connect: "Connecting…", disconnect: "Disconnecting…", remove: "Forgetting…", trust: "Trusting…"}[what] || "Working…"
        var cmd = "timeout 20 bluetoothctl " + what + " '" + mac.replace(/'/g, "'\\''") + "' 2>&1 | tail -n 3"
        if (what === "pair") cmd += "; timeout 8 bluetoothctl trust '" + mac.replace(/'/g, "'\\''") + "' >/dev/null 2>&1"
        actProc.command = ["sh", "-c", cmd]
        actProc.running = true
    }
    Process {
        id: actProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                var last = t.split("\n").filter(function(l){ return l.trim() !== "" }).pop() || ""
                root.statusMsg = last.slice(0, 90)
                root.busyMac = ""
                refreshTimer.restart()
            }
        }
    }
    Timer { id: refreshTimer; interval: 1200; onTriggered: root.refresh() }

    // ---- pods-only smart connect ----
    function podsEntry() {
        for (var i = 0; i < root.devices.length; i++)
            if (root.devices[i].mac === root.podsMac) return root.devices[i]
        return null
    }
    function connectPods() {
        var e = root.podsEntry()
        if (e && e.connected) { root.statusMsg = "Pods already connected"; return }
        if (!root.powered) {
            root.podsPending = true
            root.statusMsg = "Powering on…"
            setPower(true)
            return
        }
        // fresh list first so the presence check isn't stale
        root.statusMsg = "Looking for pods…"
        devProc.running = true
        podsRecheck.restart()
    }
    Timer {
        id: podsRecheck
        interval: 2000; repeat: false
        onTriggered: {
            var e = root.podsEntry()
            if (!e) { root.statusMsg = "Pods not around — out of the case?"; return }
            if (!e.paired) { root.statusMsg = "Pods aren't paired — pair them first"; return }
            if (e.connected) { root.statusMsg = "Pods already connected"; return }
            root.busyMac = root.podsMac
            root.statusMsg = e.rssi === 0 ? "Pods quiet — trying anyway…" : "Connecting to pods…"
            actProc.command = ["sh", "-c", "timeout 20 bluetoothctl connect '" + root.podsMac + "' 2>&1 | tail -n 3"]
            actProc.running = true
            podsWatch.restart()
        }
    }
    // watchdog: 12s, then verify and kill the hang — never stuck connecting
    Timer {
        id: podsWatch
        interval: 12000; repeat: false
        onTriggered: podsVerifyProc.running = true
    }
    Process {
        id: podsVerifyProc
        command: ["sh", "-c", "timeout 8 bluetoothctl info '" + root.podsMac + "' 2>/dev/null | grep -i 'Connected:'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // actProc may have already finished on its own; stopping an idle process is harmless
                actProc.running = false
                if (text.toLowerCase().indexOf("yes") !== -1) {
                    root.busyMac = ""
                    root.statusMsg = "Pods connected"
                    root.refresh()
                } else {
                    root.busyMac = ""
                    root.statusMsg = "Pods didn't answer — still in the case?"
                }
            }
        }
    }

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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14

            // header: phosphor mark + title + power
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: ""; color: root.powered ? colors.primary : colors.alpha(colors.outline, 0.5); font.family: root.fontIcon; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter }
                Text { text: "Bluetooth"; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 15; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    width: 64; height: 30; radius: 15
                    color: root.powered ? colors.alpha(colors.primary, 0.2) : colors.alpha(colors.surfaceVariant, 0.4)
                    border.width: 1; border.color: root.powered ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.2)
                    Text { anchors.centerIn: parent; text: root.powered ? "On" : "Off"; color: root.powered ? colors.primary : colors.alpha(colors.outline, 0.7); font.family: root.fontUi; font.pixelSize: 11; font.weight: Font.Bold }
                    MouseArea { anchors.fill: parent; onClicked: root.setPower(!root.powered) }
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // scan row
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true; height: 38; radius: 12
                    color: scanMa.containsMouse && root.powered ? colors.alpha(colors.primary, 0.18) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: root.scanning ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.15)
                    opacity: root.powered ? 1 : 0.45
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text { text: ""; color: colors.primary; font.family: root.fontIcon; font.pixelSize: 14
                            RotationAnimation on rotation { running: root.scanning; loops: Animation.Infinite; from: 0; to: 360; duration: 900 } }
                        Text { text: root.scanning ? "Scanning…" : "Scan for devices"; color: colors.primary; font.family: root.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true; enabled: root.powered; onClicked: root.scanning ? root.scanStop() : root.scanStart() }
                }
            }

            // pods hero: one tap powers + connects, watchdog kills hangs
            Rectangle {
                Layout.fillWidth: true
                height: 52
                radius: 14
                color: podsDot.containsMouse ? colors.alpha(colors.primary, 0.18) : colors.alpha(colors.primary, 0.08)
                border.width: 1
                border.color: colors.alpha(colors.primary, 0.35)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14; anchors.rightMargin: 14
                    spacing: 10
                    Rectangle {
                        width: 9; height: 9; radius: 4.5
                        Layout.alignment: Qt.AlignVCenter
                        color: root.podsEntry() && root.podsEntry().connected ? colors.primary
                             : root.busyMac === root.podsMac ? colors.secondary
                             : root.podsEntry() ? colors.tertiary : colors.alpha(colors.outline, 0.4)
                    }
                    Text {
                        text: root.podsName
                        color: colors.foreground
                        font.family: root.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: root.podsEntry() && root.podsEntry().connected ? "Connected"
                            : root.busyMac === root.podsMac ? "Connecting…" : "Connect"
                        color: colors.primary
                        font.family: root.fontUi; font.pixelSize: 11; font.weight: Font.Bold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
                MouseArea {
                    id: podsDot
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var e = root.podsEntry()
                        if (e && e.connected) root.act(root.podsMac, "disconnect")
                        else root.connectPods()
                    }
                }
            }

            // device list
            ListView {
                id: devList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: root.devices
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: devList.width
                    height: 64
                    radius: 14
                    color: modelData.connected ? colors.alpha(colors.primary, 0.10) : colors.alpha(colors.surface, 0.5)
                    border.width: 1
                    border.color: modelData.connected ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.12)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 12
                        anchors.topMargin: 8; anchors.bottomMargin: 8
                        spacing: 2
                        RowLayout { spacing: 8; Layout.fillWidth: true
                            Rectangle { width: 8; height: 8; radius: 4; Layout.alignment: Qt.AlignVCenter
                                color: root.busyMac === modelData.mac ? colors.secondary : (modelData.connected ? colors.primary : (modelData.paired ? colors.tertiary : colors.alpha(colors.outline, 0.4))) }
                            Text { text: modelData.name; color: colors.foreground; font.family: root.fontUi; font.pixelSize: 13; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { visible: modelData.battery >= 0; text: modelData.battery + "%"; color: colors.primary; font.family: root.fontUi; font.pixelSize: 11; font.weight: Font.Bold }
                        }
                        RowLayout { spacing: 8; Layout.fillWidth: true
                            Text { text: modelData.mac; color: colors.alpha(colors.outline, 0.55); font.family: root.fontUi; font.pixelSize: 10; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { visible: modelData.rssi !== 0; text: modelData.rssi + " dBm"; color: colors.alpha(colors.outline, 0.55); font.family: root.fontUi; font.pixelSize: 10 }
                            Rectangle { width: 78; height: 24; radius: 8
                                color: rowActMa.containsMouse ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.primary, 0.12)
                                border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                                Text { anchors.centerIn: parent
                                    text: !modelData.paired ? "Pair" : (modelData.connected ? "Leave" : "Join")
                                    color: colors.primary; font.family: root.fontUi; font.pixelSize: 10; font.weight: Font.Bold }
                                MouseArea { id: rowActMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        if (!modelData.paired) root.act(modelData.mac, "pair")
                                        else if (modelData.connected) root.act(modelData.mac, "disconnect")
                                        else root.act(modelData.mac, "connect")
                                    } }
                            }
                            Text { visible: modelData.paired; text: "✕"; color: rowDelMa.containsMouse ? colors.error : colors.alpha(colors.outline, 0.5); font.family: root.fontUi; font.pixelSize: 12
                                MouseArea { id: rowDelMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.act(modelData.mac, "remove") } }
                        }
                    }
                }
            }
            Text {
                visible: root.devices.length === 0
                text: root.powered ? "Nothing found yet — hit Scan." : "Adapter is off — flip it on first."
                color: colors.alpha(colors.outline, 0.6); font.family: root.fontUi; font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }

            // status line
            Text {
                visible: root.statusMsg !== ""
                text: root.statusMsg
                color: colors.secondary; font.family: root.fontUi; font.pixelSize: 10
                Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
    }
}
