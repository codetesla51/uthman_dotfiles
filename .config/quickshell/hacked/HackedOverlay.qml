import Quickshell
import Quickshell.Wayland
import QtQuick

// Ransomware-awareness simulation. This file only draws pixels: it never
// reads, encrypts, deletes or uploads anything. Release it with `hacked off`
// (or SUPER+SHIFT+ESC).
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "#07080c"
    focusable: false
    visible: true
    WlrLayershell.namespace: "qs-hacked"
    WlrLayershell.layer: WlrLayer.Overlay

    property string mono: "FiraCode Nerd Font"
    property color blood: "#ff2f4f"
    property color acid: "#27ff9d"
    property color amber: "#ffc857"
    property color bone: "#f2e9df"
    property color dim: "#8a8378"

    property int remaining: 72 * 3600
    property string victimId: "7F3A-9C21-4E8D-B0A6"
    property string btcAddress: "bc1q7f3a9c21e8db0a6x9k2m4p8s5v1n0r2t"
    property bool toastOn: false
    property string toastText: ""

    function two(n) { return n < 10 ? "0" + n : "" + n }
    function fmtTime(s) {
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        return two(h) + ":" + two(m) + ":" + two(sec)
    }
    function showToast(t) { root.toastText = t; root.toastOn = true; toastTimer.restart() }

    // ── background ──────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#07080c" }

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: root.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.30, 0.02, 0.06, 0.55) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Item {
        anchors.fill: parent
        opacity: 0.55
        Repeater {
            model: Math.ceil(root.height / 4)
            Rectangle { x: 0; y: index * 4; width: root.width; height: 1; color: "#000000"; opacity: 0.35 }
        }
    }

    // ── status bar ──────────────────────────────────────────────────────
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 40
        color: Qt.rgba(0, 0, 0, 0.42)
        border.width: 1
        border.color: Qt.rgba(1, 0.18, 0.31, 0.20)

        Row {
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            height: 14
            spacing: 10
            Rectangle { width: 8; height: 8; radius: 4; color: root.blood; y: 3 }
            Text { text: "SECURELOCK v4.2"; color: root.blood; font.family: root.mono; font.pixelSize: 10; font.bold: true }
            Text { text: "AES-256-GCM"; color: Qt.rgba(0.95, 0.91, 0.87, 0.45); font.family: root.mono; font.pixelSize: 10 }
        }

        Text {
            anchors.centerIn: parent
            text: "TOR RELAY 185.243.115.84:443"
            color: Qt.rgba(0.95, 0.91, 0.87, 0.42)
            font.family: root.mono
            font.pixelSize: 10
        }

        Text {
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            text: "KEY DELETION IN " + root.fmtTime(root.remaining)
            color: root.amber
            font.family: root.mono
            font.pixelSize: 10
            font.bold: true
        }
    }

    // ── main ransom block ───────────────────────────────────────────────
    Column {
        anchors { top: parent.top; topMargin: 78; horizontalCenter: parent.horizontalCenter }
        width: Math.min(root.width * 0.68, 820)
        spacing: 15

        Item {
            width: parent.width
            height: 58
            Item {
                width: 48; height: 58
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    x: 10; y: 0; width: 28; height: 30; radius: 14
                    color: "transparent"; border.width: 4; border.color: root.blood
                }
                Rectangle { x: 0; y: 22; width: 48; height: 34; radius: 6; color: root.blood }
                Rectangle { x: 21; y: 31; width: 6; height: 11; radius: 3; color: "#07080c" }
            }
        }

        Text {
            width: parent.width
            text: "THIS LAPTOP HAS BEEN LOCKED"
            color: root.blood
            font.family: root.mono
            font.bold: true
            font.pixelSize: Math.min(root.width * 0.048, 42)
            font.letterSpacing: 1
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: "All documents, photos, passwords and browser data on this device are encrypted with AES-256. The decryption key has been removed from this machine."
            color: Qt.rgba(0.95, 0.91, 0.87, 0.80)
            font.family: root.mono
            font.pixelSize: 15
            lineHeight: 1.5
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Item {
            width: parent.width
            height: 136
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, 760)
                height: 136
                radius: 10
                color: Qt.rgba(1.0, 0.18, 0.31, 0.05)
                border.width: 1
                border.color: Qt.rgba(1.0, 0.18, 0.31, 0.30)

                Row {
                    anchors.centerIn: parent
                    spacing: 22

                    Item {
                        width: 100; height: 100
                        Rectangle { anchors.fill: parent; radius: 4; color: "#0c0e13"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14) }
                        Grid {
                            anchors.centerIn: parent
                            columns: 11; rows: 11; spacing: 2
                            Repeater {
                                model: 121
                                Rectangle {
                                    width: 6; height: 6
                                    color: ((index * 7 + 3) % 5 < 2) ? "#e9e2d8" : "#0c0e13"
                                }
                            }
                        }
                    }

                    Column {
                        spacing: 4
                        Text { text: "RELEASE FEE"; color: root.dim; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 2; font.bold: true }
                        Text { text: "0.045 BTC"; color: root.amber; font.family: root.mono; font.pixelSize: 34; font.bold: true }
                        Text { text: root.btcAddress; color: root.bone; font.family: root.mono; font.pixelSize: 13 }
                        Text { text: "Send the exact amount, then include your Victim ID."; color: Qt.rgba(0.95, 0.91, 0.87, 0.55); font.family: root.mono; font.pixelSize: 11 }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 46
            Row {
                anchors.centerIn: parent
                height: 20
                spacing: 28
                Text {
                    text: "VICTIM ID  " + root.victimId
                    color: Qt.rgba(0.95, 0.91, 0.87, 0.70)
                    font.family: root.mono
                    font.pixelSize: 13
                }
                Text {
                    text: "DECRYPTION KEY DELETION IN " + root.fmtTime(root.remaining)
                    color: root.blood
                    font.family: root.mono
                    font.pixelSize: 13
                    font.bold: true
                }
            }
        }

        Item {
            width: parent.width
            height: 54
            Row {
                anchors.centerIn: parent
                spacing: 14

                Rectangle {
                    width: 280; height: 52; radius: 8
                    color: payArea.containsMouse ? "#ff4a63" : root.blood
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Text {
                        anchors.centerIn: parent
                        text: "I HAVE PAID — UNLOCK"
                        color: "#0b0407"
                        font.family: root.mono
                        font.pixelSize: 13
                        font.bold: true
                    }
                    MouseArea {
                        id: payArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showToast("Payment not found on the blockchain. Wait for 3 confirmations, then try again.")
                    }
                }

                Rectangle {
                    width: 200; height: 52; radius: 8
                    color: helpArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.16)
                    Text {
                        anchors.centerIn: parent
                        text: "HOW TO BUY BTC"
                        color: root.bone
                        font.family: root.mono
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: helpArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showToast("Visit any exchange. This is a simulation — no payment is possible.")
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Do not power off the device. Do not contact law enforcement. Removing this screen will destroy the key."
            color: Qt.rgba(0.95, 0.91, 0.87, 0.42)
            font.family: root.mono
            font.pixelSize: 11
            lineHeight: 1.4
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    // ── encryption summary ──────────────────────────────────────────────
    Rectangle {
        anchors { left: parent.left; bottom: parent.bottom; margins: 22 }
        width: Math.min(360, root.width * 0.28)
        height: 168
        radius: 8
        color: Qt.rgba(0.01, 0.014, 0.02, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 0.18, 0.31, 0.28)
        visible: root.height >= 820

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 26
            radius: 8
            color: Qt.rgba(1.0, 0.18, 0.31, 0.10)
            Text {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "ENCRYPTION SUMMARY"
                color: root.blood
                font.family: root.mono
                font.pixelSize: 10
                font.bold: true
            }
        }

        Column {
            x: 12
            y: 38
            width: parent.width - 24
            spacing: 10
            Repeater {
                model: [
                    { name: "Documents", pct: 1.0 },
                    { name: "Photos", pct: 1.0 },
                    { name: "Passwords", pct: 1.0 }
                ]
                delegate: Item {
                    width: parent.width
                    height: 22
                    Text { text: modelData.name; color: Qt.rgba(0.95, 0.91, 0.87, 0.72); font.family: root.mono; font.pixelSize: 10 }
                    Text { anchors.right: parent.right; text: "ENCRYPTED"; color: root.acid; font.family: root.mono; font.pixelSize: 9 }
                    Rectangle {
                        y: 16; width: parent.width; height: 3; color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle { width: parent.width * modelData.pct; height: parent.height; color: root.acid }
                    }
                }
            }
        }
    }

    // ── operator console ────────────────────────────────────────────────
    Rectangle {
        anchors { right: parent.right; bottom: parent.bottom; margins: 22 }
        width: Math.min(400, root.width * 0.30)
        height: 168
        radius: 8
        color: Qt.rgba(0.01, 0.014, 0.02, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 0.18, 0.31, 0.28)
        visible: root.height >= 820

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 26
            radius: 8
            color: Qt.rgba(1.0, 0.18, 0.31, 0.10)
            Text {
                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                text: "OPERATOR CONSOLE // TTY0"
                color: root.blood
                font.family: root.mono
                font.pixelSize: 10
                font.bold: true
            }
        }

        Text {
            x: 12
            y: 36
            width: parent.width - 24
            text: "> mount --bind /dev/mapper/crypt /mnt/locked\n> aes256-gcm key rotated\n> 1,248 files sealed\n> recovery key uploaded to relay\n> awaiting payment ..."
            color: Qt.rgba(0.15, 1.0, 0.61, 0.60)
            font.family: root.mono
            font.pixelSize: 9
            lineHeight: 1.5
        }

        Rectangle {
            x: 12
            y: 140
            width: 7
            height: 11
            color: root.acid
            SequentialAnimation on opacity {
                running: true
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0; duration: 520 }
                NumberAnimation { from: 0; to: 1; duration: 520 }
            }
        }
    }

    // ── toast ───────────────────────────────────────────────────────────
    Rectangle {
        anchors { bottom: parent.bottom; bottomMargin: 210; horizontalCenter: parent.horizontalCenter }
        width: Math.min(560, root.width * 0.6)
        height: 46
        radius: 6
        color: Qt.rgba(0.06, 0.02, 0.03, 0.97)
        border.width: 1
        border.color: Qt.rgba(1, 0.18, 0.31, 0.45)
        opacity: root.toastOn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            width: parent.width - 24
            text: root.toastText
            color: root.bone
            font.family: root.mono
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Timer {
        id: toastTimer
        interval: 4200
        repeat: false
        onTriggered: root.toastOn = false
    }

    Text {
        anchors { bottom: parent.bottom; bottomMargin: 7; horizontalCenter: parent.horizontalCenter }
        text: "SIMULATION · no files were encrypted · SUPER+SHIFT+ESC to exit"
        color: Qt.rgba(0.95, 0.91, 0.87, 0.26)
        font.family: root.mono
        font.pixelSize: 9
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: if (root.remaining > 0) root.remaining--
    }
}
