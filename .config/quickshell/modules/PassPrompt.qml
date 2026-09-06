import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PassPrompt — system password prompt (SUDO_ASKPASS backend), same glass
// style as PkgManager's dialog. Flow: ask() shows, result()/state() poll.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string prompt: "Password:"
    property string password: ""
    property string state: "idle" // idle | waiting | done | cancelled
    property string errorMsg: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-passprompt"
    WlrLayershell.layer: WlrLayer.Overlay

    IpcHandler {
        target: "passprompt"
        function ask(p: string): string { root.prompt = (p && p.length) ? p : "Password:"; root.password = ""; root.errorMsg = ""; root.state = "waiting"; root.open = true; return "shown" }
        function result(): string { var v = (root.state === "done") ? root.password : ""; if(root.state === "done"){ root.password = ""; root.state = "idle" } return v }
        function st(): string { return root.state }
        function close(): void { root.open = false; if(root.state === "waiting") root.state = "cancelled" }
    }

    onOpenChanged: if(open) Qt.callLater(function(){ passField.text = ""; passField.forceActiveFocus() })

    function submit(){
        if(passField.text.trim() === ""){ root.errorMsg = "Enter password"; return }
        root.password = passField.text
        root.state = "done"
        root.open = false
    }
    function cancel(){ root.state = "cancelled"; root.open = false }

    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open ? 0.42 : 0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: {} }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 420)
        height: 250
        radius: 16
        color: colors.alpha(colors.surface, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.18)
        focus: true
        Keys.onEscapePressed: root.cancel()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            Text { text: "  Authentication required"; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold; Layout.alignment: Qt.AlignHCenter }
            Text { text: root.prompt; color: colors.alpha(colors.outline, 0.7); font.family: "FiraCode Nerd Font"; font.pixelSize: 8; wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            Rectangle {
                Layout.fillWidth: true; height: 42; radius: 10
                color: colors.alpha(colors.surface, 0.85)
                border.width: 1; border.color: passField.activeFocus ? colors.alpha(colors.primary, 0.5) : (root.errorMsg ? colors.alpha(colors.error, 0.6) : colors.alpha(colors.outline, 0.14))
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 8
                    Text { text: ""; color: colors.alpha(colors.outline, 0.6); font.family: "FiraCode Nerd Font"; font.pixelSize: 12 }
                    TextField {
                        id: passField
                        Layout.fillWidth: true
                        placeholderText: "sudo password"
                        placeholderTextColor: colors.alpha(colors.outline, 0.45)
                        color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 11
                        echoMode: TextInput.Password
                        background: null
                        selectByMouse: true
                        onAccepted: root.submit()
                    }
                }
            }
            Text { visible: root.errorMsg !== ""; text: root.errorMsg; color: colors.error; font.family: "FiraCode Nerd Font"; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 9
                    color: cancelMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.5) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                    Text { anchors.centerIn: parent; text: "Cancel"; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.cancel() }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 9
                    color: passField.text.trim() === "" ? colors.alpha(colors.surfaceVariant, 0.35) : okMa.containsMouse ? colors.alpha(colors.primary, 0.32) : colors.alpha(colors.primary, 0.22)
                    border.width: 1; border.color: passField.text.trim() === "" ? colors.alpha(colors.outline, 0.12) : colors.alpha(colors.primary, 0.5)
                    Text { anchors.centerIn: parent; text: "Unlock"; color: passField.text.trim() === "" ? colors.alpha(colors.outline, 0.6) : colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.ExtraBold }
                    MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; enabled: passField.text.trim() !== ""; onClicked: root.submit() }
                }
            }
        }
    }
}
