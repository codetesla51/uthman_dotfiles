import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// LockScreen — quickshell session lock. SUPER+L or hypridle calls
// `ipc call lockscreen lock`: a 650ms overlay animation plays over the live
// desktop (wallpaper zooms, screen falls to black), and the session locks at
// peak black so the cut is invisible. Fonts match hyprlock: Iceland clock,
// FiraCode quotes. Timers only run while locked.
Item {
    id: root

    property bool locking: false   // pre-lock animation playing
    property string quote: ""

    IpcHandler {
        target: "lockscreen"
        function lock(): void { root.startLock() }
    }

    function startLock() {
        if (lock.locked || locking) return
        locking = true
        lockTimer.restart()
    }

    // fires at peak black — the cut hides inside full darkness
    Timer {
        id: lockTimer
        interval: 650
        onTriggered: {
            root.locking = false
            quoteProc.running = true
            lock.locked = true
        }
    }

    Process {
        id: quoteProc
        command: ["sh", "-c", "shuf -n 1 ~/.config/hypr/scripts/quotes.txt"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: { root.quote = text.trim() }
        }
    }

    // ---- pre-lock overlay: lives above the desktop, falls to black ----
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-lockfade"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"
        visible: root.locking

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.config/theme/current/background"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            scale: root.locking ? 1.0 : 1.06
            Behavior on scale { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
        }
        Rectangle {
            id: fadeBlack
            anchors.fill: parent
            color: "black"
            opacity: 0
            states: State {
                name: "dark"; when: root.locking
                PropertyChanges { target: fadeBlack; opacity: 1 }
            }
            transitions: Transition {
                NumberAnimation { property: "opacity"; duration: 650; easing.type: Easing.InOutCubic }
            }
        }
    }

    // ---- the actual session lock ----
    WlSessionLock {
        id: lock
        property bool shouldLock: false
        locked: shouldLock

        function setLocked(v) { shouldLock = v }

        WlSessionLockSurface {
            color: "black"
            // grab keyboard focus per surface when the lock engages —
            // without this the password field never receives keystrokes
            Connections {
                target: lock
                function onLockedChanged() {
                    if (lock.locked) {
                        inputField.clear()
                        focusTimer.restart()
                    }
                }
            }
            Timer {
                id: focusTimer
                interval: 300
                onTriggered: inputField.forceActiveFocus()
            }
            Rectangle {
                anchors.fill: parent
                Image {
                    anchors.fill: parent
                    source: "file://" + Quickshell.env("HOME") + "/.config/theme/current/background"
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.45)
                }

                // content rises in as the lock engages
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 18
                    opacity: lock.locked ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

                    Text {
                        id: clockText
                        text: Qt.formatDateTime(new Date(), "hh:mm")
                        color: "white"
                        font.family: "Iceland"
                        font.pixelSize: 160
                        font.weight: Font.Light
                        Layout.alignment: Qt.AlignHCenter
                        Timer {
                            interval: 1000; running: lock.locked; repeat: true
                            onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm")
                        }
                    }
                    Text {
                        text: Qt.formatDateTime(new Date(), "dddd, MMMM dd")
                        color: Qt.rgba(1, 1, 1, 0.7)
                        font.family: "Iceland"
                        font.pixelSize: 30
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: root.quote
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 15
                        font.italic: true
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: 640
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 400
                        Layout.preferredHeight: 56
                        Layout.topMargin: 10
                        radius: 28
                        color: pam.failed ? Qt.rgba(1, 0.3, 0.3, 0.14) : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
                        border.color: inputField.activeFocus ? "white" : Qt.rgba(1, 1, 1, 0.2)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        TextField {
                            id: inputField
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            placeholderText: "enter password"
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.5)
                            color: "white"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 14
                            echoMode: TextInput.Password
                            background: null
                            onAccepted: pam.start()
                        }
                    }
                    Text {
                        id: statusText
                        text: ""
                        color: "#ff9e64"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        Layout.alignment: Qt.AlignHCenter
                    }
                    PamContext {
                        id: pam
                        property bool failed: false
                        // PAM is a conversation: start() opens it, then PAM
                        // asks for the password (responseRequired) and we
                        // hand over the field text. Without respond() the
                        // session hangs forever and completed never fires.
                        onResponseRequiredChanged: {
                            if (pam.responseRequired) pam.respond(inputField.text)
                        }
                        onError: function(err) {
                            failed = true
                            statusText.text = "auth error — see log"
                            failClear.restart()
                        }
                        onCompleted: function(result) {
                            if (result === PamResult.Success) {
                                failed = false
                                statusText.text = ""
                                inputField.clear()
                                lock.setLocked(false)
                            } else {
                                failed = true
                                statusText.text = "wrong password"
                                inputField.clear()
                                failClear.restart()
                            }
                        }
                    }
                    Timer {
                        id: failClear
                        interval: 1200
                        onTriggered: pam.failed = false
                    }
                }

                RowLayout {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 24
                    spacing: 12
                    Text {
                        id: batText
                        text: ""
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Qt.formatDateTime(new Date(), "ddd MMM dd")
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                    }
                }
                Process {
                    id: batProc
                    command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1 | sed 's/^/battery /;s/$/%/'"]
                    stdout: StdioCollector {
                        waitForEnd: true
                        onStreamFinished: { batText.text = text.trim() }
                    }
                }
                Timer {
                    interval: 30000; running: lock.locked; repeat: true; triggeredOnStart: true
                    onTriggered: { if (lock.locked) batProc.running = true }
                }
            }
        }
    }
}
