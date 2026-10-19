import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Wi-Fi panel — network selector + PassPrompt join + live throughput + speed test.
// Opens from the Network pill (or `quickshell -p ~/.config/quickshell ipc call wifi toggle`).
// Single fullscreen window w/ dim backdrop; Esc / click-outside closes.
PanelWindow {
    id: root

    property var colors
    property bool open: false
    property string connectingSsid: ""
    property string errorText: ""
    property real _lastBytes: 0
    property real _lastStamp: 0

    // speed test state
    property bool speedTesting: false
    property real speedMbps: 0        // raw measured (download)
    property real shownMbps: 0        // eased display counter
    property var stSamples: []        // instantaneous samples for the live chart
    property real stProgress: 0       // 0..1 through the download
    property real ropePhase: 0        // UI-only twist phase for the rope chart (visual layer)
    property int stPhase: 0           // 0 idle, 1 downloading, 2 uploading, 3 done
    property real ulMbps: 0           // measured upload Mbps
    property real shownUl: 0
    property string stUpOutText: ""

    readonly property var wifiDev: {
        var devs = Networking.devices.values
        return devs.find(d => d.type === DeviceType.Wifi) ?? null
    }
    property bool scanSpinning: false   // true while a manual rescan is in flight
    property string searchQuery: ""
    readonly property var nets: {
        if (!wifiDev || !wifiDev.networks) return []
        var l = wifiDev.networks.values.slice()
        l.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return b.signalStrength - a.signalStrength
        })
        return l
    }
    readonly property var filteredNets: {
        if (searchQuery.trim() === "") return nets
        var q = searchQuery.trim().toLowerCase()
        return nets.filter(function(n){ return n.name.toLowerCase().includes(q) })
    }
    readonly property var connectedNet: root.nets.find(n => n.connected) ?? null
    readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired) ?? null

    NetRate { id: rate }

    function strengthGlyph(sig) {
        return sig >= 0.8 ? "󰤨" : sig >= 0.6 ? "󰤥" : sig >= 0.4 ? "󰤢" : "󰤟"
    }

    // True for networks that take no secret. The enum has no `None` -- the
    // open value is `Open`, and `Owe` is enhanced-open. Everything else
    // (WPA/WPA2/WPA3, WEP, EAP) prompts.
    function isPasswordless(sec) {
        return sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe
    }

    function connectTo(net) {
        root.errorText = ""
        root.connectingSsid = net.name.trim()
        connectWatch.restart()
        net.connect()
    }

    Timer {
        id: connectWatch
        interval: 25000
        onTriggered: {
            if (root.connectingSsid !== "") {
                root.errorText = "\"" + root.connectingSsid + "\" is taking too long — wrong password?"
                root.connectingSsid = ""
                failClear.restart()
            }
        }
    }

    Timer {
        id: failClear
        interval: 6000
        onTriggered: root.errorText = ""
    }
    function failText(r) {
        var m = ["unknown error", "no password saved", "client disconnected", "client failed", "auth timed out", "network lost"]
        return m[r] !== undefined ? m[r] : "failed"
    }

    // ── keyboard selection / actions ──
    property int selectedIndex: 0
    property var pendingPskNet: null   // network waiting on PassPrompt

    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    // Secured, unknown networks ask through the shared PassPrompt overlay. The
    // old inline field lived on this layer-shell surface and never reliably got
    // keyboard focus; PassPrompt force-focuses its own field in an overlay.
    function askPsk(net) {
        if (!net) return
        root.pendingPskNet = net
        root.errorText = ""
        var prompt = "Wi-Fi " + net.name.trim() + " — password needed to join"
        passAskProc.command = ["sh", "-c",
            "quickshell -p $HOME/.config/quickshell ipc call passprompt ask " +
            root.shellQuote(prompt) + " >/dev/null 2>&1"]
        passAskProc.running = true
    }

    function connectSelected() {
        var n = root.filteredNets[root.selectedIndex]
        if (!n || n.connected) return
        if (root.isPasswordless(n.security) || n.known) root.connectTo(n)
        else root.askPsk(n)
    }

    // PassPrompt bridge: ask -> poll st() -> read result() -> connectWithPsk.
    Process {
        id: passAskProc
        running: false
        onExited: function(code) {
            if (code !== 0) {
                root.errorText = "Could not open the password prompt"
                root.pendingPskNet = null
                failClear.restart()
                return
            }
            passPoll.restart()
        }
    }
    Timer { id: passPoll; interval: 250; repeat: true; onTriggered: passStProc.running = true }
    Process {
        id: passStProc
        running: false
        command: ["sh","-c","quickshell -p $HOME/.config/quickshell ipc call passprompt st 2>/dev/null | tr -d '\" '"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var st = text.trim()
                if (st === "done") {
                    passPoll.stop()
                    passResProc.running = true
                } else if (st === "cancelled" || st === "idle") {
                    passPoll.stop()
                    root.pendingPskNet = null
                }
            }
        }
    }
    Process {
        id: passResProc
        running: false
        command: ["sh","-c","quickshell -p $HOME/.config/quickshell ipc call passprompt result 2>/dev/null | sed 's/^\"//; s/\"$//'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var net = root.pendingPskNet
                root.pendingPskNet = null
                var pw = text.trim()
                if (net && pw !== "") {
                    root.connectingSsid = net.name.trim()
                    connectWatch.restart()
                    net.connectWithPsk(pw)
                }
            }
        }
    }
    function forgetSelected() {
        var n = root.filteredNets[root.selectedIndex]
        if (n && n.known && !n.connected) n.forget()
    }
    function moveSel(d) {
        if (root.filteredNets.length === 0) return
        root.selectedIndex = Math.max(0, Math.min(root.filteredNets.length - 1, root.selectedIndex + d))
        netList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
    onFilteredNetsChanged: root.selectedIndex = Math.max(0, Math.min(root.filteredNets.length - 1, root.selectedIndex))

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    focusable: true
    visible: root.open || closeAnim.running
    WlrLayershell.namespace: "qs-wifi"
    WlrLayershell.layer: WlrLayer.Overlay

    // NOTE: no IpcHandler here — Bar.qml owns target "wifi" and lazy-loads this.

    // entrance animation lives here, not on the card: the card's own `visible`
    // never changes when this window toggles, so card.onVisibleChanged never fires
    // and the first open after a reload left the card parked off-screen.
    // drawer motion lives in openAnim/closeAnim below (bezier pair).
    // Close plays out before the window hides (visible binds running).
    onOpenChanged: {
        if (root.open) openAnim.restart()
        else {
            root.connectingSsid = ""
            root.errorText = ""
            wifiSearch.text = ""      // fresh search every open
            root.searchQuery = ""
            closeAnim.restart()
        }
    }

    Timer {
        id: scanTimeout
        interval: 4000
        onTriggered: root.scanSpinning = false
    }

    onNetsChanged: {
        if (root.scanSpinning) {
            scanSpinStop.restart()
        }
    }

    Timer {
        id: scanSpinStop
        interval: 600
        onTriggered: root.scanSpinning = false
    }

    // ── click-outside catcher (invisible — no dim backdrop, card floats over desktop) ──
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    // ── the card ──
    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right }
        anchors.topMargin: 52
        anchors.rightMargin: 8
        width: 410
        height: 640
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(event){
            // Arrows keep steering the list even while the search field is typing
            if (event.key === Qt.Key_Down) { root.moveSel(1); event.accepted = true; return }
            if (event.key === Qt.Key_Up) { root.moveSel(-1); event.accepted = true; return }
            if (wifiSearch.activeFocus) return
            var txt = event.text ? event.text.toLowerCase() : ""
            if (txt === "s" || event.key === Qt.Key_S) {
                if (root.wifiDev) { root.wifiDev.scannerEnabled = false; root.wifiDev.scannerEnabled = true; root.scanSpinning = true }
                event.accepted = true
            } else if (txt === "t" || event.key === Qt.Key_T) { root.runSpeedTest(); event.accepted = true }
            else if (event.key === Qt.Key_C || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.connectSelected(); event.accepted = true }
            else if (event.key === Qt.Key_D) { if (root.connectedNet) root.connectedNet.disconnect(); event.accepted = true }
            else if (event.key === Qt.Key_F) { root.forgetSelected(); event.accepted = true }
        }

        transform: [
            Translate { id: slide },
            Scale { id: cardScale; origin.x: card.width; origin.y: 0 }
        ]
        Component.onCompleted: slide.x = width + 8
        // bezier pair — open pops in with overshoot bounce (fast), close
        // hurries out the same path with no overshoot. Same curve family
        // as the notification drawer.
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: slide; property: "x"; from: card.width + 8; to: 0; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: cardScale; property: "xScale"; from: 0.96; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
            NumberAnimation { target: cardScale; property: "yScale"; from: 0.96; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: slide; property: "x"; to: card.width + 8; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: cardScale; property: "xScale"; to: 0.96; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: cardScale; property: "yScale"; to: 0.96; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }

        ColumnLayout {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 14
            anchors.bottom: stDock.top
            anchors.bottomMargin: 10
            spacing: 10

            // ══════════ header ══════════
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                    Text { anchors.centerIn: parent; text: "󰤯"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 12 }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "WI-FI"
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 12
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1.3
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                // wifi radio on/off
                Rectangle {
                    visible: root.wifiDev !== null
                    width: 26; height: 26; radius: 13
                    color: wfMouse.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4)
                         : root.wifiDev && root.wifiDev.wifiEnabled ? colors.alpha(colors.primary, 0.15) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: root.wifiDev && root.wifiDev.wifiEnabled ? "󰤯" : "󰖪"
                        color: root.wifiDev && root.wifiDev.wifiEnabled ? colors.primary : colors.alpha(colors.outline, 0.7)
                        font.family: colors.fontSans
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: wfMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (root.wifiDev) root.wifiDev.wifiEnabled = !root.wifiDev.wifiEnabled
                    }
                }

                Item {
                    width: 26; height: 26
                    Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: colors.fontSans
                        font.pixelSize: 13
                        color: scanMouse.containsMouse || scanAnim.running ? colors.primary : colors.alpha(colors.outline, 0.9)

                        RotationAnimation on rotation {
                            id: scanAnim
                            running: root.scanSpinning
                            loops: Animation.Infinite
                            from: 0; to: 360
                            duration: 900
                        }
                    }
                    MouseArea {
                        id: scanMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!root.wifiDev) return
                            root.wifiDev.scannerEnabled = false
                            root.wifiDev.scannerEnabled = true
                            root.scanSpinning = true   // spin until results land or timeout
                        }
                    }
                }

                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeBtn.containsMouse ? colors.alpha(colors.surfaceVariant, 0.4) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "󰅖"
                        color: closeBtn.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.9)
                        font.family: colors.fontSans
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: closeBtn
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.open = false
                    }
                }
            }

            // ══════════ current connection card ══════════
            Rectangle {
                visible: root.connectedNet !== null
                Layout.fillWidth: true
                height: connCol.implicitHeight + 20
                radius: 12
                color: colors.alpha(colors.primary, 0.08)
                border.width: 1
                border.color: colors.alpha(colors.primary, 0.35)

                ColumnLayout {
                    id: connCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 4

                    // row 1: glyph + name + signal% share one rail
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            id: connGlyph
                            text: root.strengthGlyph(root.connectedNet ? root.connectedNet.signalStrength : 0)
                            color: colors.primary
                            font.family: colors.fontSans
                            font.pixelSize: 15
                        }

                        Text {
                            text: ((root.connectedNet || {}).name ?? "").trim()
                            color: colors.foreground
                            font.family: colors.fontSans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "signal " + Math.round(((root.connectedNet || {}).signalStrength ?? 0) * 100) + "%"
                            color: colors.alpha(colors.outline, 0.7)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                        }
                    }

                    // row 1.5: actions — disconnect from this network
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: connGlyph.width + 8
                        spacing: 6

                        Rectangle {
                            width: discRow.implicitWidth + 18
                            height: 22
                            radius: 11
                            color: dcMouse.containsMouse ? colors.alpha(colors.error, 0.2) : colors.alpha(colors.surfaceVariant, 0.3)
                            border.width: 1
                            border.color: dcMouse.containsMouse ? colors.alpha(colors.error, 0.45) : colors.alpha(colors.outline, 0.15)

                            Row {
                                id: discRow
                                anchors.centerIn: parent
                                spacing: 5

                                Text {
                                    text: "󰰡"
                                    color: dcMouse.containsMouse ? colors.error : colors.alpha(colors.foreground, 0.75)
                                    font.family: colors.fontSans
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "Disconnect"
                                    color: dcMouse.containsMouse ? colors.error : colors.alpha(colors.foreground, 0.75)
                                    font.family: colors.fontSans
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: dcMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: if (root.connectedNet) root.connectedNet.disconnect()
                            }
                        }
                    }

                    // row 2: IP indented to line up exactly under the SSID
                    Text {
                        Layout.leftMargin: connGlyph.width + 8
                        text: root.wifiDev && root.wifiDev.address !== "" ? root.wifiDev.address : "no address"
                        color: colors.alpha(colors.outline, 0.7)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // ══════════ live throughput strip ══════════
            Rectangle {
                Layout.fillWidth: true
                height: 64
                radius: 12
                color: colors.alpha(colors.surface, 0.45)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    // sparkline
                    Item {
                        width: 110
                        Layout.fillHeight: true

                        // stock-style zig-zag line chart of recent download rate
                        Canvas {
                            anchors.fill: parent

                            Connections {
                                target: rate
                                function onRxHistoryChanged() { sparkCanvas.requestPaint() }
                            }

                            id: sparkCanvas
                            anchors.bottomMargin: 3
                            anchors.topMargin: 3

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var h = rate.rxHistory
                                if (h.length < 2) return

                                var maxV = 100
                                for (var i = 0; i < h.length; i++)
                                    maxV = Math.max(maxV, h[i])

                                var n = h.length
                                var pad = 2
                                function px(i) { return (i / (n - 1)) * width }
                                function py(v) { return height - pad - (v / maxV) * (height - pad * 2) }

                                // soft fill under the curve
                                ctx.beginPath()
                                ctx.moveTo(0, height)
                                for (var i = 0; i < n; i++) ctx.lineTo(px(i), py(h[i]))
                                ctx.lineTo(width, height)
                                ctx.closePath()
                                ctx.fillStyle = colors.alpha(colors.tertiary, 0.14)
                                ctx.fill()

                                // the zig-zag line
                                ctx.beginPath()
                                for (var j = 0; j < n; j++) {
                                    if (j === 0) ctx.moveTo(px(j), py(h[j]))
                                    else ctx.lineTo(px(j), py(h[j]))
                                }
                                ctx.strokeStyle = colors.tertiary
                                ctx.lineWidth = 1.5
                                ctx.lineJoin = "round"
                                ctx.stroke()
                            }
                        }
                    }

                    Rectangle { width: 1; height: parent.height - 20; color: colors.alpha(colors.outline, 0.15) }

                    // download cell — centered
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: colors.alpha(colors.primary, 0.15)
                                    border.width: 1; border.color: colors.alpha(colors.primary, 0.3)
                                    Text { anchors.centerIn: parent; text: "󰇚"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10 }
                                }
                                Text {
                                    text: rate.fmt(rate.rxKbs)
                                    color: colors.foreground
                                    font.family: colors.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.ExtraBold
                                }
                            }

                            Text {
                                text: "DOWNLOAD"
                                color: colors.alpha(colors.outline, 0.55)
                                font.family: colors.fontSans
                                font.pixelSize: 7
                                font.weight: Font.Bold
                                font.letterSpacing: 1.3
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    Rectangle { width: 1; height: parent.height - 20; color: colors.alpha(colors.outline, 0.15) }

                    // upload cell — centered
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: colors.alpha(colors.secondary, 0.15)
                                    border.width: 1; border.color: colors.alpha(colors.secondary, 0.3)
                                    Text { anchors.centerIn: parent; text: "󰕒"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 10 }
                                }
                                Text {
                                    text: rate.fmt(rate.txKbs)
                                    color: colors.foreground
                                    font.family: colors.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.ExtraBold
                                }
                            }

                            Text {
                                text: "UPLOAD"
                                color: colors.alpha(colors.outline, 0.55)
                                font.family: colors.fontSans
                                font.pixelSize: 7
                                font.weight: Font.Bold
                                font.letterSpacing: 1.3
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }

            // ── total usage since boot ──
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "󰇚 " + rate.fmtTotal(rate.totalRxMb) + "   ·   󰕒 " + rate.fmtTotal(rate.totalTxMb)
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans
                font.pixelSize: 9
                font.letterSpacing: 0.5
            }

            // ── error banner ──
            Rectangle {
                visible: root.errorText !== ""
                Layout.fillWidth: true
                height: errLabel.implicitHeight + 14
                radius: 10
                color: colors.alpha(colors.error, 0.15)
                border.width: 1
                border.color: colors.alpha(colors.error, 0.4)

                Text {
                    id: errLabel
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.margins: 8
                    text: root.errorText
                    color: colors.error
                    font.family: colors.fontSans
                    font.pixelSize: 10
                    wrapMode: Text.WrapAnywhere
                }
            }

            // search
            TextField {
                id: wifiSearch
                Layout.fillWidth: true
                implicitHeight: 40
                leftPadding: 12
                rightPadding: 12
                placeholderText: "Search networks…"
                placeholderTextColor: colors.alpha(colors.outline,0.5)
                color: colors.foreground
                font.family: colors.fontSans
                font.pixelSize: 11
                background: Rectangle {
                    radius: 12
                    color: colors.alpha(colors.surface,0.6)
                    border.width: 1
                    border.color: wifiSearch.activeFocus ? colors.alpha(colors.primary,0.5) : colors.alpha(colors.outline,0.15)
                }
                onTextChanged: root.searchQuery = text
                Keys.onEscapePressed: function(event) {
                    // leave the field first: Esc clears the query and hands focus
                    // back to the panel. A second Esc (field not focused) closes.
                    wifiSearch.text = ""
                    card.forceActiveFocus()
                    event.accepted = true
                }
            }

            // ══════════ section label ══════════
            Text {
                text: "NETWORKS (" + root.filteredNets.length + "/" + root.nets.length + ")"
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans
                font.pixelSize: 7
                font.letterSpacing: 1.3
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
            }

            // ══════════ network list ══════════
            ListView {
                id: netList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.filteredNets
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    property bool hovered: rowArea.containsMouse || fgMouse.containsMouse
                    readonly property bool isSelected: index === root.selectedIndex
                    readonly property bool isConnecting: modelData.stateChanging || modelData.state === ConnectionState.Connecting

                    // real connection feedback: failures surface in the banner, success clears states
                    Connections {
                        target: modelData
                        function onConnectionFailed(reason) {
                            if (root.connectingSsid === modelData.name.trim()) {
                                root.errorText = "Failed to join \"" + modelData.name.trim() + "\": " + root.failText(reason)
                                root.connectingSsid = ""
                                failClear.restart()
                            }
                        }
                        function onStateChanged(state) {
                            if (state === ConnectionState.Connected && root.connectingSsid === modelData.name.trim()) {
                                root.connectingSsid = ""
                                root.errorText = ""
                            }
                        }
                    }

                    width: netList.width - 8
                    height: isConnecting ? 68 : 44
                    radius: 10
                    color: hovered ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                    border.width: modelData.connected || isSelected ? 1 : 0
                    border.color: modelData.connected ? colors.alpha(colors.primary, 0.45)
                                                      : colors.alpha(colors.outline, 0.35)

                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    // Row click lives UNDER the content so the nested forget
                    // button gets its clicks first. It used to be declared last,
                    // sat on top of everything and swallowed the trash clicks.
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.selectedIndex = index   // F/C/D etc. follow the last click
                            if (modelData.connected || isConnecting) return
                            if (root.isPasswordless(modelData.security) || modelData.known) root.connectTo(modelData)
                            else root.askPsk(modelData)
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 9

                            Text {
                                text: root.strengthGlyph(modelData.signalStrength)
                                color: modelData.connected ? colors.primary
                                     : hovered ? colors.foreground
                                     : colors.alpha(colors.foreground, 0.75)
                                font.family: colors.fontSans
                                font.pixelSize: 14
                            }

                            Text {
                                text: modelData.name.trim() === "" ? "(hidden network)" : modelData.name.trim()
                                color: modelData.connected ? colors.primary : colors.foreground
                                font.family: colors.fontSans
                                font.pixelSize: 11
                                font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                visible: modelData.known && !modelData.connected
                                width: knownLabel.implicitWidth + 10
                                height: 16
                                radius: 8
                                color: colors.alpha(colors.surfaceVariant, 0.35)

                                Text {
                                    id: knownLabel
                                    anchors.centerIn: parent
                                    text: "saved"
                                    color: colors.alpha(colors.outline, 0.7)
                                    font.family: colors.fontSans
                                    font.pixelSize: 8
                                }
                            }

                            // hover-reveal: forget saved network
                            Rectangle {
                                visible: hovered && modelData.known && !modelData.connected && !isConnecting
                                width: 22; height: 22; radius: 11
                                color: fgMouse.containsMouse ? colors.alpha(colors.error, 0.25) : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    color: fgMouse.containsMouse ? colors.error : colors.alpha(colors.outline, 0.65)
                                    font.family: colors.fontSans
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: fgMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: modelData.forget()
                                }
                            }

                            Text {
                                visible: !root.isPasswordless(modelData.security)
                                text: ""
                                color: colors.alpha(colors.outline, 0.65)
                                font.family: colors.fontSans
                                font.pixelSize: 10
                            }

                            Text {
                                visible: modelData.connected
                                text: ""
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 11
                            }
                        }

                        Text {
                            visible: isConnecting
                            text: "connecting…"
                            color: colors.alpha(colors.primary, 0.9)
                            font.family: colors.fontSans
                            font.pixelSize: 9
                            SequentialAnimation on opacity {
                                running: isConnecting
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                    }
                }
            }

            // keyboard hints
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: "↑↓ select · C connect · D disconnect · S scan · F forget"
                color: colors.alpha(colors.outline, 0.5)
                font.family: colors.fontSans
                font.pixelSize: 8
                font.letterSpacing: 0.3
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.15) }

        }

        // ══════════ speed test — pinned bottom dock, never scrolls away ══════════
        Rectangle {
            id: stDock
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 14; anchors.bottomMargin: 28
            height: 130                       // FIXED budget — dock never resizes, list above never jumps
            radius: 12
            color: colors.alpha(colors.surface, 0.55)
            border.width: 1
            border.color: root.speedTesting ? colors.alpha(colors.primary, 0.35) : colors.alpha(colors.outline, 0.12)

            ColumnLayout {
                id: stDockCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        width: 120; height: 34; radius: 10
                        color: root.speedTesting ? colors.alpha(colors.surfaceVariant, 0.3)
                              : stMouse.containsMouse ? colors.alpha(colors.primary, 0.22)
                              : colors.alpha(colors.primary, 0.12)
                        border.width: 1
                        border.color: colors.alpha(colors.primary, 0.35)

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                visible: root.speedTesting
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 12
                                RotationAnimation on rotation {
                                    running: root.speedTesting
                                    loops: Animation.Infinite
                                    from: 0; to: 360; duration: 700
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.speedTesting ? "testing" : "󰓄  Speed test"
                                color: colors.primary
                                font.family: colors.fontSans
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: stMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.speedTesting
                            onClicked: root.runSpeedTest()
                        }
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    // big eased counter
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: root.shownMbps > 0 ? root.shownMbps.toFixed(1) : "0.0"
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 22
                        font.weight: Font.ExtraBold
                    }
                    Text {
                        text: "Mbps"
                        color: colors.primary
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        Layout.alignment: Qt.AlignBottom
                    }
                }

                // twisted rope: straight-line port of picked option D — 48 phase-twisted
                // verticals fake a spiral viewed from the side, tertiary dot rides the crest.
                // Idle twists slow, testing twists fast, amplitude follows live throughput.
                Rectangle {
                    Layout.fillWidth: true
                    height: 46                       // fixed — same budget as the old trace box
                    radius: 10
                    clip: true
                    color: colors.alpha(colors.surface, 0.35)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)

                    Timer {
                        interval: 50
                        running: root.open           // never burns CPU while the panel is shut
                        repeat: true
                        triggeredOnStart: true
                        onTriggered: {
                            var h = root.stSamples
                            var last = h.length > 0 ? h[h.length - 1] : 0
                            root.ropePhase += 0.07 + (root.speedTesting ? 0.23 : 0) + Math.min(0.1, last / 600)
                            stRope.requestPaint()
                        }
                    }

                    Canvas {
                        id: stRope
                        anchors.fill: parent
                        anchors.margins: 4

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()

                            var N = 48
                            var h = root.stSamples
                            var last = h.length > 0 ? h[h.length - 1] : 0
                            var boost = Math.min(1, last / 80)
                            var amp = 10 + boost * (height / 2 - 8)
                            var ph = root.ropePhase

                            for (var i = 0; i < N; i++) {
                                var x = 2 + i * ((width - 4) / (N - 1))
                                var a = i * 0.42 - ph * 3.0
                                var s = Math.abs(Math.sin(a))
                                var lh = 5 + s * amp
                                var y1 = height / 2 - lh / 2
                                ctx.strokeStyle = colors.alpha(colors.tertiary, 0.3 + Math.abs(Math.cos(a)) * 0.5)
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.moveTo(x, y1)
                                ctx.lineTo(x, y1 + lh)
                                ctx.stroke()
                            }
                        }
                    }
                }

                // download progress hairline
                Rectangle {
                    Layout.fillWidth: true
                    height: 3
                    radius: 1.5
                    color: colors.alpha(colors.surfaceVariant, 0.3)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: parent.width * root.stProgress
                        radius: 1.5
                        color: colors.primary
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }

                // status line: live phase while testing, last result when idle
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.stPhase === 1 ? "testing download…"
                          : root.stPhase === 2 ? "testing upload…"
                          : root.stPhase === 3 ? (root.shownUl > 0 ? "down " + root.shownMbps.toFixed(1) + " · up " + root.shownUl.toFixed(1) + " Mbps"
                                                                  : "down " + root.shownMbps.toFixed(1) + " Mbps · up n/a")
                          : "ready — press speed test"
                    color: root.stPhase === 3 ? colors.secondary : colors.alpha(colors.outline, 0.6)
                    font.family: colors.fontSans
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
        }
    }

    // ── download + upload speed test (curl everywhere — QML XHR buffered the
    // whole response so the counter froze; curl streams to a file we poll, so
    // live progress + a real number even on slow links) ──
    property real stRunStart: 0
    property real stDlGot: 0

    function runSpeedTest() {
        if (speedTesting) return
        speedTesting = true
        speedMbps = 0
        shownMbps = 0
        ulMbps = 0
        shownUl = 0
        stSamples = []
        stProgress = 0
        stDlGot = 0
        _lastBytes = 0
        _lastStamp = 0
        stPhase = 1
        stRunStart = new Date().getTime()

        stDlProc.running = true
        stDlPoll.restart()
        stTimeout.restart()
    }

    function finishDownload() {
        if (root.stPhase !== 1) return   // idempotent
        speedTesting = false
        stDlPoll.stop()
        stTimeout.stop()
        var secs = (new Date().getTime() - stRunStart) / 1000
        if (secs > 0.5 && root.stDlGot > 0) speedMbps = (root.stDlGot * 8) / secs / 1000000
        else speedMbps = 0
        shownMbps = speedMbps
        stProgress = Math.min(1, root.stDlGot / 5000000)
        root.stPhase = 2
        stUpProc.running = true        // upload phase
    }

    Process {
        id: stDlProc
        command: ["sh", "-c", "rm -f /tmp/.qs-dl.bin; curl -s --max-time 20 -o /tmp/.qs-dl.bin 'https://speed.cloudflare.com/__down?bytes=5000000' 2>/dev/null"]
        onExited: function (code) {
            if (root.stPhase === 1) root.finishDownload()
        }
    }
    Timer {
        id: stDlPoll
        interval: 200
        repeat: true
        onTriggered: {
            if (!root.speedTesting) { stop(); return }
            stSizeProc.command = ["stat", "-c", "%s", "/tmp/.qs-dl.bin"]
            stSizeProc.running = true
        }
    }
    Process {
        id: stSizeProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (!root.speedTesting) return
                var got = parseInt(text.trim()) || 0
                if (got <= 0) return
                root.stDlGot = got
                root.stProgress = got / 5000000
                var now = new Date().getTime()
                var secs = (now - root.stRunStart) / 1000
                if (secs > 0.5) {
                    // instantaneous rate over the last window (not cumulative avg)
                    var dt = now - root._lastStamp
                    if (root._lastStamp && dt > 0 && got > root._lastBytes) {
                        var inst = ((got - root._lastBytes) * 8) / (dt / 1000) / 1000000
                        var arr = root.stSamples.slice()
                        arr.push(inst)
                        if (arr.length > 60) arr.shift()
                        root.stSamples = arr
                    }
                    root._lastBytes = got
                    root._lastStamp = now
                    speedMbps = (got * 8) / secs / 1000000
                    shownMbps += (speedMbps - shownMbps) * 0.35
                } else {
                    root._lastBytes = got
                    root._lastStamp = now
                }
            }
        }
    }
    Timer {
        id: stTimeout
        interval: 26000
        onTriggered: {
            // never leave the panel stuck testing on a dead/slow link
            if (root.stPhase === 1) root.finishDownload()
        }
    }

    // upload phase: 8MB POST to Cloudflare. Best-effort — some networks/ISPs
    // throttle or block the endpoint; on failure we show download only (honest n/a).
    Process {
        id: stUpProc
        command: ["sh", "-c", "dd if=/dev/zero of=/tmp/.qs-upload bs=1M count=4 2>/dev/null; curl -s -o /dev/null --max-time 10 -H 'Expect:' -w '%{http_code}|%{size_upload}|%{time_total}' --data-binary @/tmp/.qs-upload https://speed.cloudflare.com/__up 2>/dev/null; rm -f /tmp/.qs-upload"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stUpOutText = text.trim()
        }
        onExited: function (code) {
            root.speedTesting = false
            var parts = root.stUpOutText.split("|")
            var up = parseFloat(parts[1]) || 0      // bytes actually sent
            var secs = parseFloat(parts[2]) || 0    // wall clock of the attempt
            if (up > 0 && secs > 0.5) {
                // partial byte counts stay usable even on --max-time aborts
                root.ulMbps = up * 8 / secs / 1000000
                root.shownUl = root.ulMbps
                root.stPhase = 3
            } else if (root.stPhase === 2) {
                // upload blocked — keep the download result, mark up as n/a
                root.ulMbps = -1
                root.shownUl = -1
                root.stPhase = 3
            } else {
                root.stPhase = 0
            }
        }
    }
}
