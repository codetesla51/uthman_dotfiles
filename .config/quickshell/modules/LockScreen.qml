import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Lock Screen — quickshell version, nice like hyprlock, with blur bg, clock, input, battery
WlSessionLock {
    id: lock
    property bool shouldLock: false
    locked: shouldLock

    WlSessionLockSurface {
        color: "black"
        Rectangle {
            anchors.fill: parent
            // background with blur — use current wallpaper
            Image {
                anchors.fill: parent
                source: "file:///home/uthman/.config/omarchy/current/background"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0,0,0,0.45)
            }
            // blur effect via layer
            layer.enabled: true
            layer.effect: null

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20
                // Clock — big like hyprlock
                Text {
                    id: clockText
                    text: Qt.formatDateTime(new Date(), "hh:mm")
                    color: "white"
                    font.family: "Iceberg"
                    font.pixelSize: 120
                    font.weight: Font.Light
                    Layout.alignment: Qt.AlignHCenter
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm") }
                }
                Text {
                    id: dateText
                    text: Qt.formatDateTime(new Date(), "dddd, MMMM dd")
                    color: Qt.rgba(1,1,1,0.7)
                    font.family: "Iceberg"
                    font.pixelSize: 22
                    Layout.alignment: Qt.AlignHCenter
                    Timer { interval: 60000; running: true; repeat: true; onTriggered: dateText.text = Qt.formatDateTime(new Date(), "dddd, MMMM dd") }
                }

                // Input field — password
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 400
                    Layout.preferredHeight: 56
                    radius: 28
                    color: Qt.rgba(1,1,1,0.12)
                    border.width: 1
                    border.color: inputField.activeFocus ? "white" : Qt.rgba(1,1,1,0.2)
                    TextField {
                        id: inputField
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        placeholderText: " enter password"
                        placeholderTextColor: Qt.rgba(1,1,1,0.5)
                        color: "white"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        background: null
                        onAccepted: {
                            pam.start()
                        }
                        Keys.onEscapePressed: lock.shouldLock = false
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
                    onCompleted: function(result){
                        if(result === PamResult.Success){
                            statusText.text = ""
                            lock.shouldLock = false
                            lock.unlock()
                        } else {
                            statusText.text = "wrong password"
                            inputField.clear()
                        }
                    }
                }
            }

            // bottom bar — battery and sysinfo like hyprlock
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 24
                spacing: 12
                Text {
                    id: batText
                    text: ""
                    color: Qt.rgba(1,1,1,0.6)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    Timer {
                        interval: 5000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: {
                            var xhr=new XMLHttpRequest()
                            xhr.open("GET","file:///home/uthman/.config/hypr/scripts/battery.sh",false)
                            try{ xhr.send(); batText.text=xhr.responseText.trim() }catch(e){ batText.text="" }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    id: sysText
                    text: ""
                    color: Qt.rgba(1,1,1,0.6)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    Timer {
                        interval: 10000; running: true; repeat: true; triggeredOnStart: true
                        onTriggered: {
                            var xhr=new XMLHttpRequest()
                            xhr.open("GET","file:///home/uthman/.config/hypr/scripts/sysinfo.sh",false)
                            try{ xhr.send(); sysText.text=xhr.responseText.trim() }catch(e){ sysText.text="" }
                        }
                    }
                }
            }
        }
    }
}
