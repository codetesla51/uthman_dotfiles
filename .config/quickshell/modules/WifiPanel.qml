import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Wi-Fi panel — network selector + password entry + live throughput + speed test.
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
        return sig >= 80 ? "󰤟" : sig >= 60 ? "󰤞" : sig >= 40 ? "󰤝" : "󰤜"
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
                root.failClear.restart()
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
    property string askPwSsid: ""   // which row shows the password field

    function connectSelected() {
        var n = root.filteredNets[root.selectedIndex]
        if (!n || n.connected) return
        if (!n.security || n.security === WifiSecurityType.None || n.known) root.connectTo(n)
        else root.askPwSsid = n.name.trim()
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
    visible: root.open
    WlrLayershell.namespace: "qs-wifi"
    WlrLayershell.layer: WlrLayer.Overlay

    IpcHandler {
        target: "wifi"
        function toggle(): void { root.open = !root.open }
    }

    // entrance animation lives here, not on the card: the card's own `visible`
    // never changes when this window toggles, so card.onVisibleChanged never fires
    // and the first open after a reload left the card parked off-screen.
    onOpenChanged: {
        if (root.open) { slide.x = card.width + 8; slideIn.restart() }
        else { root.connectingSsid = ""; root.errorText = "" }
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
        color: colors.alpha(colors.background, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(event){
            if (wifiSearch.activeFocus) return
            var txt = event.text ? event.text.toLowerCase() : ""
            if (txt === "s" || event.key === Qt.Key_S) {
                if (root.wifiDev) { root.wifiDev.scannerEnabled = false; root.wifiDev.scannerEnabled = true; root.scanSpinning = true }
                event.accepted = true
            } else if (txt === "t" || event.key === Qt.Key_T) { root.runSpeedTest(); event.accepted = true }
            else if (event.key === Qt.Key_C || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.connectSelected(); event.accepted = true }
            else if (event.key === Qt.Key_D) { if (root.connectedNet) root.connectedNet.disconnect(); event.accepted = true }
            else if (event.key === Qt.Key_F) { root.forgetSelected(); event.accepted = true }
            else if (event.key === Qt.Key_Down) { root.moveSel(1); event.accepted = true }
            else if (event.key === Qt.Key_Up) { root.moveSel(-1); event.accepted = true }
        }

        transform: Translate { id: slide }
        Component.onCompleted: slide.x = width + 8
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "x"; from: card.width + 8; to: 0; duration: 250; easing.type: Easing.OutCubic }
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
                            text: "signal " + ((root.connectedNet || {}).signalStrength ?? 0) + "%"
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
                text: "󰇚 " + rate.fmtTotal(rate.totalRxMb) + "   \u00B7   󰕒 " + rate.fmtTotal(rate.totalTxMb)
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
                placeholderText: "Search networks…  (S)"
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

                    property bool hovered: rowArea.containsMouse
                    readonly property bool askPw: root.askPwSsid === modelData.name.trim()
                    readonly property bool isSelected: index === root.selectedIndex
                    readonly property bool isConnecting: modelData.stateChanging || modelData.state === ConnectionState.Connecting

                    // real connection feedback: failures surface in the banner, success clears states
                    Connections {
                        target: modelData
                        function onConnectionFailed(reason) {
                            if (root.connectingSsid === modelData.name.trim()) {
                                root.errorText = "Failed to join \"" + modelData.name.trim() + "\": " + root.failText(reason)
                                root.connectingSsid = ""
                                root.failClear.restart()
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
                    height: askPw ? 120 : isConnecting ? 68 : 44
                    radius: 10
                    color: hovered ? colors.alpha(colors.surfaceVariant, 0.3) : "transparent"
                    border.width: modelData.connected || isSelected ? 1 : 0
                    border.color: modelData.connected ? colors.alpha(colors.primary, 0.45)
                                                      : colors.alpha(colors.outline, 0.35)

                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

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
                                visible: modelData.security !== undefined && modelData.security !== WifiSecurityType.None
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

                        // password entry (secured + unknown only)
                        RowLayout {
                            visible: askPw
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: pwField
                                Layout.fillWidth: true
                                implicitHeight: 36
                                leftPadding: 12
                                rightPadding: 12
                                topPadding: 8
                                bottomPadding: 8
                                echoMode: TextInput.Password
                                font.family: colors.fontSans
                                font.pixelSize: 12
                                color: colors.foreground
                                placeholderText: "Enter WiFi password…"
                                placeholderTextColor: colors.alpha(colors.outline,0.6)
                                background: Rectangle {
                                    radius: 10
                                    color: colors.alpha(colors.surface, 0.85)
                                    border.width: 1
                                    border.color: pwField.activeFocus ? colors.alpha(colors.primary,0.5) : colors.alpha(colors.primary,0.3)
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                }
                                onAccepted: joinTap.tap()
                            }

                            Rectangle {
                                width: 64; height: 36; radius: 10
                                color: pwField.text.length >= 8 ? colors.primary : colors.alpha(colors.surfaceVariant,0.35)
                                border.width: 1
                                border.color: pwField.text.length >= 8 ? colors.primary : colors.alpha(colors.outline,0.15)
                                Text {
                                    anchors.centerIn: parent
                                    text: "Join"
                                    color: pwField.text.length >= 8 ? colors.background : colors.alpha(colors.outline,0.6)
                                    font.family: colors.fontSans
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                }

                                TapHandler {
                                    id: joinTap
                                    function tap() {
                                        if (pwField.text.length < 8) return
                                        root.connectingSsid = modelData.name.trim()
                                        root.connectWatch.restart()
                                        modelData.connectWithPsk(pwField.text)
                                        pwField.text = ""
                                        root.askPwSsid = ""
                                    }
                                }
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

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !askPw
                        propagateComposedEvents: true
                        onClicked: {
                            if (modelData.connected || isConnecting) return
                            if (!modelData.security || modelData.security === WifiSecurityType.None || modelData.known) {
                                root.connectTo(modelData)
                            } else {
                                if (root.askPwSsid === modelData.name.trim()) {
                                    root.askPwSsid = ""
                                } else {
                                    root.askPwSsid = modelData.name.trim()
                                    Qt.callLater(function(){ pwField.forceActiveFocus() })
                                }
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

                // live zig-zag of instantaneous throughput while testing
                Rectangle {
                    Layout.fillWidth: true
                    height: 46                       // fixed — shows live samples while testing, last run idle
                    radius: 10
                    clip: true
                    color: colors.alpha(colors.surface, 0.35)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)

                    Canvas {
                        id: stChart
                        anchors.fill: parent
                        anchors.margins: 4

                        Connections {
                            target: root
                            function onStSamplesChanged() { stChart.requestPaint() }
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()

                            // faint baseline + mid guide so the box reads as a chart even when empty
                            ctx.strokeStyle = colors.alpha(colors.outline, 0.12)
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            ctx.moveTo(0, height - 1); ctx.lineTo(width, height - 1)
                            ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2)
                            ctx.stroke()

                            var h = root.stSamples
                            if (h.length < 2) return

                            var maxV = 5
                            for (var i = 0; i < h.length; i++) maxV = Math.max(maxV, h[i])

                            var n = h.length
                            function px(i) { return (i / Math.max(59, n - 1)) * width }
                            function py(v) { return height - 2 - (v / maxV) * (height - 6) }

                            ctx.beginPath()
                            ctx.moveTo(0, height)
                            for (var i = 0; i < n; i++) ctx.lineTo(px(i), py(h[i]))
                            ctx.lineTo(px(n - 1), height)
                            ctx.closePath()
                            ctx.fillStyle = colors.alpha(colors.primary, 0.14)
                            ctx.fill()

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
                    Text {
                        anchors.centerIn: parent
                        visible: !root.speedTesting && root.stSamples.length < 2
                        text: "throughput trace appears while testing"
                        color: colors.alpha(colors.outline, 0.5)
                        font.family: colors.fontSans
                        font.pixelSize: 8
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
        root.stUpProc.running = true   // upload phase
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
        command: ["sh", "-c", "dd if=/dev/zero of=/tmp/.qs-upload bs=1M count=8 2>/dev/null; curl -s -o /dev/null --max-time 12 -H 'Expect:' -w '%{http_code}|%{speed_upload}' --data-binary @/tmp/.qs-upload https://speed.cloudflare.com/__up 2>/dev/null; rm -f /tmp/.qs-upload"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stUpOutText = text.trim()
        }
        onExited: function (code) {
            root.speedTesting = false
            var parts = root.stUpOutText.split("|")
            var http = parseInt(parts[0]) || 0
            var up = parseInt(parts[1]) || 0
            if (code === 0 && http === 200 && up > 0) {
                root.ulMbps = up * 8 / 1000000
                root.shownUl = root.ulMbps
                root.stPhase = 3
            } else if (root.stPhase === 2) {
                // upload blocked/throttled — keep the download result, mark up as n/a
                root.ulMbps = -1
                root.shownUl = -1
                root.stPhase = 3
            } else {
                root.stPhase = 0
            }
        }
    }
}
