import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PassPrompt — system password prompt (SUDO_ASKPASS backend). Flow:
// ask() shows, result()/st() poll. Reskinned to the approved mock:
// 420px dialog, lock chip header, password field with eye toggle,
// caps/error row, Cancel/Allow footer. Geometry follows the mock verbatim.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string prompt: "Password:"
    property string password: ""
    property string state: "idle" // idle | waiting | done | cancelled
    property string errorMsg: ""
    property bool capsOn: false

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

    onOpenChanged: { if(open){ Qt.callLater(function(){ passField.text = ""; passField.forceActiveFocus() }); capsProc.running = true; openAnim.restart() } else closeAnim.restart() }

    // caps-lock state: sysfs LED brightness, no X dependency
    Process {
        id: capsProc
        command: ["cat", "/sys/class/leds/input3::capslock/brightness"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.capsOn = (text.trim() === "1") }
    }
    Timer { interval: 500; running: root.open; repeat: true; onTriggered: capsProc.running = true }

    // prompt splits on " — ": who needs it / why
    readonly property var promptParts: String(root.prompt).split(" — ")
    readonly property string whoText: (root.promptParts[0] || "Authentication") + " needs your password"
    readonly property string whyText: root.promptParts.length > 1 ? root.promptParts[1] : ""

    function submit(){
        if(passField.text.trim() === ""){
            root.errorMsg = "Enter password"
            shakeAnim.restart()
            return
        }
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
        width: Math.min(parent.width * 0.92, 420)
        height: col.implicitHeight + 36
        radius: 10
        color: colors.alpha(colors.surface, 0.62)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.22)
        focus: true
        Keys.onEscapePressed: root.cancel()
        transform: Translate { id: shakeT }

        // mock pop: 280ms overshoot entrance
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }
        // mock shake keyframes: -6 / 5 / -3 / 2 over 320ms
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: shakeT; property: "x"; to: -6; duration: 64 }
            NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 64 }
            NumberAnimation { target: shakeT; property: "x"; to: -3; duration: 64 }
            NumberAnimation { target: shakeT; property: "x"; to: 2; duration: 64 }
            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 64 }
        }

        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18; anchors.rightMargin: 18
            spacing: 14
            // header — 44px lock chip + who/why
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Rectangle {
                    width: 44; height: 44; radius: 8
                    color: colors.primary
                    Text { anchors.centerIn: parent; text: ""; color: colors.background; font.family: colors.fontSans; font.pixelSize: 22 }
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: root.whoText; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 15; font.weight: Font.ExtraBold; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { visible: root.whyText !== ""; text: root.whyText; color: colors.outline; font.family: colors.fontSans; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
            // field — 42px password row with eye toggle
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 42; radius: 6
                color: colors.alpha(colors.background, 0.7)
                border.width: 1
                border.color: root.errorMsg !== "" ? colors.error : (passField.activeFocus ? colors.primary : colors.alpha(colors.outline, 0.25))
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 14; spacing: 0
                    TextField {
                        id: passField
                        Layout.fillWidth: true; Layout.fillHeight: true
                        placeholderText: "sudo password"
                        placeholderTextColor: colors.alpha(colors.outline, 0.7)
                        color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14
                        echoMode: passShown ? TextInput.Normal : TextInput.Password
                        property bool passShown: false
                        background: null
                        selectByMouse: true
                        onAccepted: root.submit()
                        onTextChanged: { root.errorMsg = "" }
                    }
                    Text {
                        text: passField.passShown ? "󰛑" : "󰛐"
                        color: eyeMa.containsMouse || passField.passShown ? colors.primary : colors.outline
                        font.family: colors.fontSans; font.pixelSize: 18
                        Layout.preferredWidth: 40; Layout.fillHeight: true
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        MouseArea { id: eyeMa; anchors.fill: parent; hoverEnabled: true; onClicked: { passField.passShown = !passField.passShown; passField.forceActiveFocus() } }
                    }
                }
            }
            // message row — caps warning + error
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 16
                spacing: 10
                Text { visible: root.capsOn; text: "Caps Lock is on"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 11 }
                Text { text: root.errorMsg; color: colors.error; font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            // footer — note + Cancel / Allow
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "Stays unlocked for 5 minutes"; color: colors.outline; font.family: colors.fontSans; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    Layout.preferredWidth: cancelTxt.implicitWidth + 40; Layout.preferredHeight: 36; radius: 6
                    color: cancelMa.containsMouse ? colors.alpha(colors.surfaceVariant, 0.6) : colors.alpha(colors.surfaceVariant, 0.6)
                    border.width: 1; border.color: colors.alpha(colors.outline, 0.2)
                    scale: cancelMa.pressed ? 0.96 : 1
                    Text { id: cancelTxt; anchors.centerIn: parent; text: "Cancel"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                    MouseArea { id: cancelMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.cancel() }
                }
                Rectangle {
                    Layout.preferredWidth: allowTxt.implicitWidth + 40; Layout.preferredHeight: 36; radius: 6
                    color: passField.text.trim() === "" ? colors.alpha(colors.surfaceVariant, 0.7) : colors.primary
                    scale: allowMa.pressed ? 0.96 : 1
                    Text { id: allowTxt; anchors.centerIn: parent; text: "Allow"; color: passField.text.trim() === "" ? colors.outline : colors.background; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold }
                    MouseArea { id: allowMa; anchors.fill: parent; hoverEnabled: true; enabled: passField.text.trim() !== ""; onClicked: root.submit() }
                }
            }
        }
    }
}
