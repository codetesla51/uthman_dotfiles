import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One notification toast. Self-managing lifetime:
// created via createObject(), plays entrance, auto-expires (unless Critical),
// fades out on dismiss() and destroys itself. Null-safe throughout.
//
// Layout: header row (small app icon + app name + ×), then thumbnail LEFT /
// text RIGHT, then actions. Nothing renders full-width or oversized.
Rectangle {
    id: root

    required property var notification
    required property var colors
    signal expired()

    readonly property bool alive: notification !== null
    readonly property bool critical: alive && notification.urgency === NotificationUrgency.Critical
    property string state_: "open"

    width: 380
    height: content.height + 24
    radius: 16
    clip: true
    color: colors.alpha(colors.background, 0.88)
    border.width: 1
    border.color: critical ? colors.alpha(colors.error, 0.5)
                           : colors.alpha(colors.outline, 0.3)

    opacity: 0
    transform: Translate { id: slide }

    function dismiss() {
        if (state_ !== "open") return
        state_ = "closing"
        if (alive) notification.tracked = false
        exitAnim.start()
    }

    Component.onCompleted: {

        if (alive && !critical && notification.expireTimeout > 0)
            expiryTimer.interval = notification.expireTimeout
        else if (!critical)
            expiryTimer.interval = 5000
        else
            expiryTimer.interval = 0
        if (expiryTimer.interval > 0) expiryTimer.restart()
        enterAnim.start()
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: slide; property: "x"; from: -24; to: 0; duration: 200; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
            NumberAnimation { target: slide; property: "x"; to: -24; duration: 150; easing.type: Easing.InCubic }
        }
        ScriptAction { script: root.destroy() }
    }

    Timer {
        id: expiryTimer
        onTriggered: root.dismiss()
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 13 }
        spacing: 6

        // ── row 1: tiny app icon · app name · close ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.alive ? notification.appName : ""
                color: colors.alpha(colors.outline, 0.9)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                width: 20; height: 20; radius: 10
                color: closeMouse.containsMouse ? colors.alpha(colors.error, 0.25) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: closeMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7)
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.dismiss()
                }
            }
        }

        // ── row 2: thumbnail left · summary+body right ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Image {
                id: preview
                visible: root.alive && notification.image !== ""
                source: root.alive ? notification.image : ""
                Layout.preferredWidth: visible ? 56 : 0
                Layout.preferredHeight: visible ? 56 : 0
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true

                Text {
                    text: root.alive ? notification.summary : ""
                    color: colors.foreground
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }

                Text {
                    visible: root.alive && notification.body !== ""
                    text: root.alive ? notification.body.replace(/<[^>]*>/g, "") : ""
                    color: colors.on_surface
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.letterSpacing: 0.3
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── row 3: save for screenshots only ──
        Row {
            Layout.fillWidth: true
            spacing: 6
            visible: root.alive && notification.image !== ""
            Rectangle {
                width: 68; height: 22; radius: 11
                color: saveMa.containsMouse ? colors.alpha(colors.primary,0.18) : colors.alpha(colors.surfaceVariant,0.35)
                border.width: 1; border.color: colors.alpha(colors.outline,0.2)
                Text { anchors.centerIn: parent; text: "Save"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10 }
                MouseArea {
                    id: saveMa; anchors.fill: parent; hoverEnabled:true
                    onClicked: {
                        // save screenshot image to Pictures
                        var src = notification.image || ""
                        // handle file:// prefix
                        if (src && src.startsWith("file://")) src = src.substring(7)
                                                var safe = src.replace(/'/g, "'\\''")
                        Quickshell.execDetached(["sh","-c","mkdir -p ~/Pictures/Screenshots; cp -- '"+safe+"' ~/Pictures/Screenshots/ 2>/dev/null; cp -- '"+safe+"' /tmp/ 2>/dev/null; notify-send -u normal 'Screenshot saved' 'Saved to ~/Pictures/Screenshots' 2>/dev/null || true"])
                        console.log("[toast] saved", src)
                        root.dismiss()
                    }
                }
            }
        }
    }
    // whole-card click = dismiss (behind interactive children)
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: root.state_ === "open"
        onClicked: root.dismiss()
    }
}
