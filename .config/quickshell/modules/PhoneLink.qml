import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

// PhoneLink — KDE Connect plugin: send/receive files, clipboard sync.
// Phone must have KDE Connect app installed and paired.
// Toggle: ipc call phonelink · SUPER ALT F · PluginMenu tile.
FloatingWindow {
    id: root

    property var colors
    property bool open: false
    property string deviceName: "Phone"
    property string deviceId: ""
    property bool connected: false
    property int battery: -1
    property var recentFiles: []    // [{name, path, time}]

    title: "PhoneLink"
    implicitWidth: 340
    implicitHeight: 420
    color: "transparent"
    visible: root.open

    IpcHandler { target: "phonelink"; function toggle(): void { root.open = !root.open } }

    // ---------- device discovery ----------
    function refreshDevices() {
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["kdeconnect-cli", "--list-devices"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Parse: "- A05s: b7819341d6fd42509093fe301cd7fc1d (paired)"
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var m = lines[i].match(/- (.+?): ([a-f0-9]+) \((\w+)\)/)
                    if (m && m[3] === "paired") {
                        root.deviceName = m[1]
                        root.deviceId = m[2]
                        root.connected = true
                        batteryProc.running = true
                        return
                    }
                }
                root.connected = false
                root.deviceId = ""
            }
        }
    }

    Process {
        id: batteryProc
        command: ["~/.config/quickshell/scripts/kde-battery.sh", root.deviceId]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // Fallback: try D-Bus for battery
                dbusBatteryProc.running = true
            }
        }
    }

    Process {
        id: dbusBatteryProc
        command: ["~/.config/quickshell/scripts/kde-battery.sh", root.deviceId]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var val = parseInt(text.trim())
                root.battery = isNaN(val) ? -1 : val
            }
        }
    }

    Timer { interval: 15000; running: true; repeat: true; onTriggered: root.refreshDevices() }
    Component.onCompleted: refreshDevices()

    // ---------- clipboard ----------
    function sendClipboard() {
        clipSendProc.running = true
    }
    function receiveClipboard() {
        clipRecvProc.running = true
    }

    Process {
        id: clipSendProc
        command: ["~/.config/quickshell/scripts/kde-send-clipboard.sh", root.deviceId]
        stdout: StdioCollector {}
    }
    Process {
        id: clipRecvProc
        command: ["~/.config/quickshell/scripts/kde-receive-clipboard.sh", root.deviceId]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var txt = text.trim()
                if (txt) {
                    // Copy received text to local clipboard
                    Quickshell.execDetached(["sh", "-c", "echo '" + txt.replace(/'/g, "'\\''") + "' | wl-copy"])
                    recvLabel.text = "Copied to clipboard"
                    recvTimer.restart()
                }
            }
        }
    }

    property string lastRecv: ""
    Text { id: recvLabel; visible: false }

    Timer { id: recvTimer; interval: 2000; onTriggered: recvLabel.text = "" }

    // ---------- send file ----------
    function openFilePicker() { filePickerProc.running = true }
    function sendFile(path) {
        if (!path || !root.deviceId) return
        fileSendProc.command = ["kdeconnect-cli", "-d", root.deviceId, "--share", path]
        fileSendProc.running = true
        // Add to recent
        var name = path.split("/").pop()
        var entry = { name: name, path: path, time: Qt.formatDateTime(new Date(), "HH:mm") }
        var arr = [entry]
        for (var i = 0; i < recentFiles.length && i < 9; i++) arr.push(recentFiles[i])
        recentFiles = arr
    }

    Process {
        id: fileSendProc
        command: ["kdeconnect-cli", "-d", root.deviceId, "--share", "/dev/null"]
        stdout: StdioCollector {}
    }

    // File picker — GTK native via helper (better than QML FileDialog)
    Process {
        id: filePickerProc
        command: ["~/.config/quickshell/scripts/filepicker.py"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var path = text.trim()
                if (path) root.sendFile(path)
            }
        }
    }
    FileDialog {
        id: filePicker
        title: "Send to " + root.deviceName
        nameFilters: ["All files (*)"]
        onAccepted: {
            var path = selectedFile.toString().replace("file://", "")
            root.sendFile(path)
        }
    }

    // ---------- UI ----------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        color: colors.alpha(colors.background, 0.92)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.connected ? colors.secondary : colors.error
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: root.connected ? root.deviceName : "No device"
                    color: colors.foreground
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                    Layout.fillWidth: true
                }
                Rectangle {
                    visible: root.battery >= 0
                    radius: 8
                    height: 20
                    width: batRow.implicitWidth + 12
                    color: colors.alpha(root.battery <= 20 ? colors.error : colors.secondary, 0.15)
                    border.width: 1
                    border.color: colors.alpha(root.battery <= 20 ? colors.error : colors.secondary, 0.4)
                    Row {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: root.battery <= 20 ? "low" : root.battery + "%"
                            color: root.battery <= 20 ? colors.error : colors.secondary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                    }
                }
                Rectangle {
                    width: 24; height: 24; radius: 12
                    color: refreshMa.containsMouse ? colors.alpha(colors.primary, 0.15) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: listProc.running ? "" : "refresh"
                        color: colors.primary
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: listProc.running ? 10 : 8
                        font.weight: Font.Bold
                        RotationAnimation on rotation { running: listProc.running; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
                    }
                    MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.refreshDevices() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // action buttons
            Text {
                text: "QUICK ACTIONS"
                color: colors.alpha(colors.outline, 0.65)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 12
                    color: sendMa.containsMouse ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: sendMa.containsMouse ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.1)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: "send"
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "file"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 8
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                    MouseArea { id: sendMa; anchors.fill: parent; hoverEnabled: true; onClicked: filePickerProc.running = true }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 12
                    color: clipMa.containsMouse ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: clipMa.containsMouse ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.1)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: "clipboard"
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "send"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 8
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                    MouseArea { id: clipMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.sendClipboard() }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 12
                    color: recvMa.containsMouse ? colors.alpha(colors.primary, 0.15) : colors.alpha(colors.surfaceVariant, 0.25)
                    border.width: 1
                    border.color: recvMa.containsMouse ? colors.alpha(colors.primary, 0.4) : colors.alpha(colors.outline, 0.1)
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: "clipboard"
                            color: colors.primary
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.ExtraBold
                            Layout.alignment: Qt.AlignHCenter
                        }
                        Text {
                            text: "receive"
                            color: colors.alpha(colors.outline, 0.6)
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 8
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                    MouseArea { id: recvMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.receiveClipboard() }
                }
            }

            // status message
            Text {
                visible: recvLabel.text !== ""
                text: recvLabel.text
                color: colors.secondary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                Layout.alignment: Qt.AlignHCenter
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // recent files
            Text {
                text: "RECENT"
                color: colors.alpha(colors.outline, 0.65)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1.5
            }

            Repeater {
                model: root.recentFiles
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: modelData.name
                        color: colors.foreground
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: modelData.time
                        color: colors.alpha(colors.outline, 0.5)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 8
                    }
                }
            }

            Text {
                visible: root.recentFiles.length === 0
                text: "no files sent yet"
                color: colors.alpha(colors.outline, 0.4)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                Layout.alignment: Qt.AlignHCenter
            }

            Item { Layout.fillHeight: true }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
