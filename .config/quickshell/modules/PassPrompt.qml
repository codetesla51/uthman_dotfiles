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
    visible: root.open || closeAnim.running
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

    onOpenChanged: { if(open){ Qt.callLater(function(){ passField.text = ""; passField.forceActiveFocus() }); openAnim.restart() } else closeAnim.restart() }

    function submit(){
        if(passField.text.trim() === ""){ root.errorMsg = "Enter password"; return }
        root.password = passField.text
        root.state = "done"
        root.open = false
    }
    function cancel(){ root.state = "cancelled"; root.open = false }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: {} }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 420)
        height: 292
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: true
        Keys.onEscapePressed: root.cancel()

        // bezier pair — open pops with overshoot bounce (fast), close hurries
        // out with none. Same curves as the notification drawer.
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12
            // hero — lock medallion + title + prompt whisper
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Rectangle {
                    width: 40; height: 40; radius: 20
                    color: colors.alpha(colors.primary, 0.15)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                    Layout.alignment: Qt.AlignHCenter
                    Text { anchors.centerIn: parent; text: ""; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 17; font.weight: Font.Bold }
                }
                Text { text: "Authentication required"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold; Layout.alignment: Qt.AlignHCenter }
                Text { text: root.prompt; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
            }
            Rectangle {
                Layout.fillWidth: true; height: 42; radius: 10
                color: colors.alpha(colors.surface, 0.85)
                border.width: 1; border.color: passField.activeFocus ? colors.alpha(colors.primary, 0.5) : (root.errorMsg ? colors.alpha(colors.error, 0.6) : colors.alpha(colors.outline, 0.14))
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 8
                    TextField {
                        id: passField
                        Layout.fillWidth: true
                        placeholderText: "sudo password"
                        placeholderTextColor: colors.alpha(colors.outline, 0.45)
                        color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11
                        echoMode: TextInput.Password
                        background: null
                        selectByMouse: true
                        onAccepted: root.submit()
                    }
                }
            }
            Text { visible: root.errorMsg !== ""; text: root.errorMsg; color: colors.error; font.family: colors.fontSans; font.pixelSize: 9; Layout.alignment: Qt.AlignHCenter }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 9
                    color: cancelMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.5) : colors.alpha(colors.surface, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                    scale: cancelMa.containsMouse ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                    Text { anchors.centerIn: parent; text: "Cancel"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.cancel() }
                }
                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 9
                    color: passField.text.trim() === "" ? colors.alpha(colors.surfaceVariant, 0.35) : okMa.containsMouse ? colors.alpha(colors.primary, 0.32) : colors.alpha(colors.primary, 0.22)
                    border.width: 1; border.color: passField.text.trim() === "" ? colors.alpha(colors.outline, 0.12) : colors.alpha(colors.primary, 0.5)
                    scale: (passField.text.trim() !== "" && okMa.containsMouse) ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] } }
                    Text { anchors.centerIn: parent; text: "Unlock"; color: passField.text.trim() === "" ? colors.alpha(colors.outline, 0.6) : colors.primary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.ExtraBold }
                    MouseArea { id: okMa; anchors.fill: parent; hoverEnabled: true; enabled: passField.text.trim() !== ""; onClicked: root.submit() }
                }
            }
        }
    }
}
