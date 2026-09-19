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
    color: colors.alpha(colors.background, 0.78)
    border.width: 1
    border.color: critical ? colors.alpha(colors.error, 0.5)
                           : colors.alpha(colors.outline, 0.15)

    opacity: 0
    transform: Translate { id: slide }


    // compact per-app Phosphor icon (mirrors NotificationCenter.appGlyph)
    function appGlyph(name) {
        var n = String(name || "").toLowerCase()
        if (n.indexOf("whatsapp") !== -1) return ""
        if (n.indexOf("firefox") !== -1) return ""
        if (n.indexOf("mozilla") !== -1) return ""
        if (n.indexOf("chrome") !== -1) return ""
        if (n.indexOf("chromium") !== -1) return ""
        if (n.indexOf("spotify") !== -1) return ""
        if (n.indexOf("telegram") !== -1) return ""
        if (n.indexOf("discord") !== -1) return ""
        if (n.indexOf("ghostty") !== -1) return ""
        if (n.indexOf("kitty") !== -1) return ""
        if (n.indexOf("terminal") !== -1) return ""
        if (n.indexOf("console") !== -1) return ""
        if (n.indexOf("volume") !== -1) return ""
        if (n.indexOf("audio") !== -1) return ""
        if (n.indexOf("wpctl") !== -1) return ""
        if (n.indexOf("pactl") !== -1) return ""
        if (n.indexOf("speaker") !== -1) return ""
        if (n.indexOf("mic") !== -1) return ""
        if (n.indexOf("battery") !== -1) return ""
        if (n.indexOf("power") !== -1) return ""
        if (n.indexOf("tlp") !== -1) return ""
        if (n.indexOf("wifi") !== -1) return ""
        if (n.indexOf("network") !== -1) return ""
        if (n.indexOf("nmcli") !== -1) return ""
        if (n.indexOf("iwctl") !== -1) return ""
        if (n.indexOf("bluetooth") !== -1) return ""
        if (n.indexOf("screenshot") !== -1) return ""
        if (n.indexOf("shot") !== -1) return ""
        if (n.indexOf("camera") !== -1) return ""
        if (n.indexOf("clipboard") !== -1) return ""
        if (n.indexOf("cliphist") !== -1) return ""
        if (n.indexOf("music") !== -1) return ""
        if (n.indexOf("mpv") !== -1) return ""
        if (n.indexOf("video") !== -1) return ""
        if (n.indexOf("mail") !== -1) return ""
        if (n.indexOf("thunderbird") !== -1) return ""
        if (n.indexOf("envelope") !== -1) return ""
        if (n.indexOf("calendar") !== -1) return ""
        if (n.indexOf("download") !== -1) return ""
        if (n.indexOf("brightness") !== -1) return ""
        if (n.indexOf("sunset") !== -1) return ""
        if (n.indexOf("night") !== -1) return ""
        if (n.indexOf("image") !== -1) return ""
        if (n.indexOf("chat") !== -1) return ""
        if (n.indexOf("note") !== -1) return ""
        if (n.indexOf("github") !== -1) return ""
        if (n.indexOf("git") !== -1) return ""
        if (n.indexOf("brave") !== -1) return ""
        if (n.indexOf("vivaldi") !== -1) return ""
        if (n.indexOf("edge") !== -1) return ""
        if (n.indexOf("opera") !== -1) return ""
        if (n.indexOf("zen") !== -1) return ""
        if (n.indexOf("grim") !== -1) return ""
        if (n.indexOf("slurp") !== -1) return ""
        if (n.indexOf("flameshot") !== -1) return ""
        if (n.indexOf("swappy") !== -1) return ""
        if (n.indexOf("obs") !== -1) return ""
        if (n.indexOf("recorder") !== -1) return ""
        if (n.indexOf("swayosd") !== -1) return ""
        if (n.indexOf("upower") !== -1) return ""
        if (n.indexOf("mpd") !== -1) return ""
        if (n.indexOf("ncmpcpp") !== -1) return ""
        if (n.indexOf("pacman") !== -1) return ""
        if (n.indexOf("yay") !== -1) return ""
        if (n.indexOf("paru") !== -1) return ""
        if (n.indexOf("update") !== -1) return ""
        if (n.indexOf("keepassxc") !== -1) return ""
        if (n.indexOf("password") !== -1) return ""
        if (n.indexOf("nautilus") !== -1) return ""
        if (n.indexOf("thunar") !== -1) return ""
        if (n.indexOf("dolphin") !== -1) return ""
        if (n.indexOf("filemanager") !== -1) return ""
        if (n.indexOf("nautilus") !== -1) return ""
        if (n.indexOf("code") !== -1) return ""
        if (n.indexOf("zed") !== -1) return ""
        if (n.indexOf("nvim") !== -1) return ""
        if (n.indexOf("neovim") !== -1) return ""
        if (n.indexOf("phone") !== -1) return ""
        if (n.indexOf("hyprlock") !== -1) return ""
        if (n.indexOf("lock") !== -1) return ""
        if (n.indexOf("weather") !== -1) return ""
        if (n.indexOf("usb") !== -1) return ""
        if (n.indexOf("udisk") !== -1) return ""
        if (n.indexOf("timer") !== -1) return ""
        if (n.indexOf("pomodoro") !== -1) return ""
        if (n.indexOf("alarm") !== -1) return ""
        if (n.indexOf("watchcat") !== -1) return ""
        return ""
    }

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
                readonly property string ag: root.appGlyph(root.alive ? notification.appName : "")
                visible: ag !== ""
                text: ag
                color: colors.alpha(colors.primary, 0.9)
                font.family: "Phosphor"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.alive ? notification.appName : ""
                color: colors.alpha(colors.outline, 0.9)
                font.family: colors.fontSans
                font.pixelSize: 10
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                width: 20; height: 20; radius: 10
                color: closeMouse.containsMouse ? colors.alpha(colors.error, 0.25) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: closeMouse.containsMouse ? colors.foreground : colors.alpha(colors.outline, 0.7)
                    font.family: "Phosphor"
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
                    text: root.alive ? (notification.summary || "").replace(/<[^>]*>/g, "").substring(0, 120) : ""
                    color: colors.foreground
                    font.family: colors.fontSans
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    visible: root.alive && notification.body !== ""
                    text: root.alive ? (notification.body || "").replace(/<[^>]*>/g, "").substring(0, 200) : ""
                    color: colors.on_surface
                    font.family: colors.fontSans
                    font.pixelSize: 11
                    font.letterSpacing: 0.3
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // ── row 2.5: action buttons (invoke the sender's actions) ──
        Row {
            Layout.fillWidth: true
            spacing: 6
            visible: root.alive && notification.actions !== undefined && notification.actions.length > 0

            Repeater {
                model: root.alive ? notification.actions : []

                delegate: Rectangle {
                    id: tAct
                    required property var modelData
                    visible: modelData.identifier !== undefined && modelData.identifier !== "default" && modelData.text !== ""
                    width: tActLbl.implicitWidth + 18
                    height: 24
                    radius: 12
                    color: tActMa.containsMouse ? colors.alpha(colors.primary, 0.25)
                                               : colors.alpha(colors.surfaceVariant, 0.35)
                    border.width: 1
                    border.color: colors.alpha(colors.primary, 0.35)

                    Text {
                        id: tActLbl
                        anchors.centerIn: parent
                        text: tAct.modelData.text || ""
                        color: colors.foreground
                        font.family: colors.fontSans
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: tActMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            tAct.modelData.invoke()
                            root.dismiss()
                        }
                    }
                }
            }
        }

        // ── row 3: save for screenshots only ──
        Row {
            Layout.fillWidth: true
            spacing: 6
            visible: root.alive && notification.image !== "" && /\.(png|jpe?g|webp)$/i.test(notification.image)
            Rectangle {
                width: 68; height: 22; radius: 11
                color: saveMa.containsMouse ? colors.alpha(colors.primary,0.18) : colors.alpha(colors.surfaceVariant,0.35)
                border.width: 1; border.color: colors.alpha(colors.outline,0.2)
                Text { anchors.centerIn: parent; text: "Save"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 10 }
                MouseArea {
                    id: saveMa; anchors.fill: parent; hoverEnabled:true
                    onClicked: {
                        // save screenshot image to Pictures
                        var src = notification.image || ""
                        // handle file:// prefix
                        if (src && src.startsWith("file://")) src = src.substring(7)
                                                var safe = src.replace(/'/g, "'\\''")
                        Quickshell.execDetached(["sh","-c","mkdir -p ~/Pictures/Screenshots; cp -- '"+safe+"' ~/Pictures/Screenshots/ 2>/dev/null; cp -- '"+safe+"' /tmp/ 2>/dev/null; notify-send -u normal -a 'Screenshot' 'Screenshot saved' 'Saved to ~/Pictures/Screenshots' 2>/dev/null || true"])
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
