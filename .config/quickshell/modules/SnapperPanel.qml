import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// SnapperPanel — btrfs snapshot manager: list / create / delete snapshots
// for the root config. Ops run through sudo -A + the PassPrompt module, so
// the amber password dialog pops whenever auth is needed (sudo caches the
// credential ~15min, so refresh after the first prompt is promptless).
// Toggle: ipc call snapper (SUPER ALT S).
PanelWindow {
    id: root
    property var colors
    property bool open: false

    // [{ number, type, date, description, cleanup }]
    property var snapshots: []
    property string status: ""
    property bool busy: false
    property int pendingDel: -1
    property int curAction: 0 // 0 list · 1 create · 2 delete

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-snapper"
    WlrLayershell.layer: WlrLayer.Overlay

    IpcHandler { target: "snapper"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if(open) { root.pendingDel = -1; root.refresh(); Qt.callLater(function(){ card.forceActiveFocus() }) }

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function sudoCmd(cmd) { return "SUDO_ASKPASS=" + q(Quickshell.env("HOME") + "/.local/bin/askpass") + " sudo -A " + cmd }

    // list / create / delete all ride one shell: action; then re-list in the
    // same process (sudo creds are cached, so no second prompt)
    function refresh() { run(0, "") }
    function create() {
        var d = descField.text.trim()
        if (d === "") { root.status = "description required"; return }
        run(1, d)
    }
    function removeSnapshot(num) { run(2, String(num)) }

    function run(action, arg) {
        if (root.busy) return
        root.busy = true
        root.status = action === 0 ? "loading…" : "working…"
        var cmd
        if (action === 0) cmd = root.sudoCmd("snapper --jsonout -c root list 2>&1")
        else if (action === 1) cmd = root.sudoCmd("snapper -c root create -d " + q(arg) + " 2>&1; echo '---LIST---'; snapper --jsonout -c root list 2>&1")
        else cmd = root.sudoCmd("snapper -c root delete " + q(arg) + " 2>&1; echo '---LIST---'; snapper --jsonout -c root list 2>&1")
        snapProc.command = ["sh", "-c", cmd]
        root.curAction = action
        snapProc.running = true
    }
    Process {
        id: snapProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.busy = false
                var t = text
                var head = t, body = t
                var sep = t.indexOf("---LIST---")
                if (sep !== -1) { head = t.slice(0, sep); body = t.slice(sep + 10) }
                if (/sudo:|Sorry, try again/.test(head)) {
                    root.status = "authentication cancelled"
                    return
                }
                if (/^error:|^ERROR/.test(head.trim()) || (sep !== -1 && /error:/.test(head))) {
                    root.status = head.trim().split("\n")[0]
                    return
                }
                if (root.curAction === 1) root.status = "snapshot created"
                else if (root.curAction === 2) root.status = "snapshot deleted"
                else if (sep === -1) { root.status = "couldn't reach snapper"; return }
                var i = body.indexOf("{")
                if (i === -1) { root.status = "couldn't read snapshots"; return }
                try {
                    var d = JSON.parse(body.slice(i))
                    var keys = Object.keys(d)
                    var cfg = keys.length > 0 ? keys[0] : "root"
                    var list = d[cfg] || []
                    var out = []
                    for (var k = 0; k < list.length; k++) {
                        var s = list[k]
                        out.push({ number: s.number, type: s.type, date: s.date || "",
                                   description: s.description || "", cleanup: s.cleanup || "" })
                    }
                    root.snapshots = out
                    root.status = out.length + " snapshots"
                } catch (e) {
                    root.status = "parse failed"
                }
            }
        }
    }
    Timer { interval: 3000; running: root.pendingDel !== -1; repeat: false; onTriggered: root.pendingDel = -1 }

    // ================= UI =================
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.42 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open = false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: 520
        radius: 16
        color: colors.alpha(colors.surface, 0.4)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.14)
        clip: true
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
        Keys.onEscapePressed: root.open = false
        focus: root.open

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // ── header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    text: "󰏖  SNAPSHOTS"
                    color: colors.alpha(colors.foreground, 0.85)
                    font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                }
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: refMa.containsMouse ? colors.alpha(colors.tertiary, 0.2) : colors.alpha(colors.tertiary, 0.08)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.25)
                    Text { anchors.centerIn: parent; text: ""; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 11 }
                    MouseArea { id: refMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.refresh() }
                }
            }

            // ── create row ──
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 12
                    color: colors.alpha(colors.surface, 0.55)
                    border.width: 1
                    border.color: descField.activeFocus ? colors.alpha(colors.primary, 0.5) : colors.alpha(colors.outline, 0.14)
                    TextField {
                        id: descField
                        anchors.fill: parent
                        anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: Text.AlignVCenter
                        placeholderText: "snapshot description…"
                        placeholderTextColor: colors.alpha(colors.outline, 0.45)
                        color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10
                        background: null
                        selectByMouse: true
                        onAccepted: root.create()
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 84; height: 32; radius: 16
                    color: root.busy ? colors.alpha(colors.surfaceVariant, 0.4) : createMa.containsMouse ? colors.alpha(colors.primary, 0.32) : colors.alpha(colors.primary, 0.18)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.4)
                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "working…" : "snapshot"
                        color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                    }
                    MouseArea { id: createMa; anchors.fill: parent; hoverEnabled: true; enabled: !root.busy; onClicked: root.create() }
                }
            }

            // ── status line ──
            Text {
                Layout.fillWidth: true
                visible: root.status !== ""
                text: root.status
                elide: Text.ElideRight
                color: colors.alpha(colors.outline, 0.6)
                font.family: colors.fontSans; font.pixelSize: 8
            }

            // ── snapshot list ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: colors.alpha(colors.surface, 0.3)
                border.width: 1
                border.color: colors.alpha(colors.outline, 0.08)
                clip: true
                ListView {
                    id: snapList
                    anchors.fill: parent
                    anchors.margins: 4
                    model: root.snapshots
                    clip: true
                    spacing: 1
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 5; onPositionChanged: {} }
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property var s: modelData
                        width: snapList.width
                        height: 46
                        radius: 10
                        color: rowMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.35) : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                                text: s.number
                                color: s.description === "current" ? colors.alpha(colors.outline, 0.5) : colors.foreground
                                font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold
                            }
                            // type chip
                            Rectangle {
                                Layout.preferredWidth: 42; height: 22; radius: 11
                                color: colors.alpha(s.type === "single" ? colors.tertiary : s.type === "pre" ? colors.primary : colors.secondary, 0.15)
                                border.width: 1; border.color: colors.alpha(s.type === "single" ? colors.tertiary : s.type === "pre" ? colors.primary : colors.secondary, 0.3)
                                Text {
                                    anchors.centerIn: parent
                                    text: s.type.toUpperCase()
                                    color: s.type === "single" ? colors.tertiary : s.type === "pre" ? colors.primary : colors.secondary
                                    font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    Layout.fillWidth: true
                                    text: s.description
                                    elide: Text.ElideRight
                                    color: s.description === "current" ? colors.alpha(colors.foreground, 0.45)
                                         : colors.foreground
                                    font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: s.date.length > 0 ? s.date.slice(5, 16) : "—"
                                    color: colors.alpha(colors.outline, 0.5)
                                    font.family: colors.fontSans; font.pixelSize: 8
                                }
                            }
                            Rectangle {
                                visible: s.cleanup !== ""
                                Layout.preferredWidth: 44; height: 18; radius: 9
                                color: colors.alpha(colors.surfaceVariant, 0.5)
                                Text {
                                    anchors.centerIn: parent
                                    text: s.cleanup.toUpperCase()
                                    color: colors.alpha(colors.outline, 0.7)
                                    font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold
                                }
                            }
                            // delete — arm-then-confirm, no accidental zaps
                            Rectangle {
                                visible: s.description !== "current"
                                Layout.preferredWidth: 22; height: 22; radius: 11
                                color: root.pendingDel === s.number
                                    ? colors.alpha(colors.error, 0.35)
                                    : delMa.containsMouse ? colors.alpha(colors.error, 0.2) : colors.alpha(colors.surfaceVariant, 0.35)
                                border.width: 1
                                border.color: root.pendingDel === s.number ? colors.alpha(colors.error, 0.7)
                                    : delMa.containsMouse ? colors.alpha(colors.error, 0.5) : colors.alpha(colors.outline, 0.12)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.pendingDel === s.number ? "confirm" : "󰅖"
                                    color: root.pendingDel === s.number ? colors.error : colors.alpha(colors.outline, 0.75)
                                    font.family: colors.fontSans; font.pixelSize: root.pendingDel === s.number ? 7 : 11
                                    font.weight: root.pendingDel === s.number ? Font.Bold : Font.Normal
                                }
                                MouseArea {
                                    id: delMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        if (root.pendingDel === s.number) { root.pendingDel = -1; root.removeSnapshot(s.number) }
                                        else root.pendingDel = s.number
                                    }
                                }
                            }
                        }
                        MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }
                }
            }

            // ── footer hint ──
            Text {
                Layout.fillWidth: true
                text: "create/delete run through sudo · PassPrompt handles auth"
                horizontalAlignment: Text.AlignHCenter
                color: colors.alpha(colors.outline, 0.4)
                font.family: colors.fontSans; font.pixelSize: 7
            }
        }
    }
}