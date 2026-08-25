import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

// StatusPill — single glass pill that consolidates all transient indicators:
// idle inhibitor, DND, screen-recording, plus every SystemTray icon
// (LocalSend, OBS, etc.) except those already represented elsewhere
// (Spotify → NowPlaying). Appears only when *something* is active,
// otherwise fully hidden (width 0). Avoids three separate popping pills.
//
// Nice-style: one surface@0.55 pill, radius 14, outline@0.15 border,
// 13px glyphs/images, 8px gaps, 1×14 dividers at outline@0.18 between groups,
// hover lifts icon opacity to 1.
Item {
    id: root

    property var colors
    property bool dnd: false
    signal toggleDndRequested()

    // --- tray filtering ---
    readonly property var hiddenApps: ["spotify"]
    readonly property var trayItems: SystemTray.items.values.filter(function(it) {
        var s = ((it.id || "") + " " + (it.title || "")).toLowerCase()
        for (var i = 0; i < hiddenApps.length; i++)
            if (s.indexOf(hiddenApps[i]) !== -1) return false
        return true
    })

    // --- script states ---
    property string idleText: ""
    property string idleCls: ""
    readonly property bool idleActive: idleCls === "active" && idleText !== ""

    property string recText: ""
    property string recCls: ""
    readonly property bool recActive: recCls === "active" && recText !== ""

    readonly property bool hasContent: idleActive || recActive || dnd || trayItems.length > 0
    readonly property int dividerCount: (idleActive ? 1 : 0) + (dnd ? 1 : 0) + (recActive ? 1 : 0) + (trayItems.length > 0 ? 1 : 0) - (hasContent ? 1 : 0)

    implicitWidth: hasContent ? pill.implicitWidth : 0
    implicitHeight: 30
    visible: hasContent
    clip: false

    // polling — idle + recording (5s, mirrors previous ScriptIndicator intervals)
    Process {
        id: idleProc
        command: ["sh", "-c", "$HOME/.config/quickshell/scripts/idle-indicators/idle.sh"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    root.idleText = j.text ?? ""
                    root.idleCls = j.class ?? ""
                } catch (e) { root.idleText = ""; root.idleCls = "" }
            }
        }
    }
    Process {
        id: recProc
        command: ["sh", "-c", "$HOME/.config/quickshell/scripts/idle-indicators/screen-recording.sh"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text)
                    root.recText = j.text ?? ""
                    root.recCls = j.class ?? ""
                } catch (e) { root.recText = ""; root.recCls = "" }
            }
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { idleProc.running = true; recProc.running = true }
    }

    // recording blink
    SequentialAnimation on opacity {
        running: root.recActive
        loops: Animation.Infinite
        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        implicitWidth: row.implicitWidth + 22
        implicitHeight: 30
        width: implicitWidth
        height: 30
        radius: 14
        color: colors.alpha(colors.surface, 0.55)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)

        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8

            // -- idle: 󱫖 when hypridle is off (inhibited) --
            Item {
                visible: root.idleActive
                implicitWidth: idleLabel.implicitWidth
                implicitHeight: 16
                Text {
                    id: idleLabel
                    anchors.centerIn: parent
                    text: root.idleText
                    color: colors.tertiary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                    opacity: idleMa.containsMouse ? 1 : 0.92
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    id: idleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "pidof hypridle >/dev/null && pkill hypridle || uwsm-app -- hypridle &"])
                }
            }

            // divider after idle if more follows
            Rectangle {
                visible: root.idleActive && (root.dnd || root.recActive || root.trayItems.length > 0)
                width: 1; height: 14
                color: colors.alpha(colors.outline, 0.18)
                Layout.alignment: Qt.AlignVCenter
            }

            // -- DND: 󰂛 moon when silenced --
            Item {
                visible: root.dnd
                implicitWidth: dndLabel.implicitWidth
                implicitHeight: 16
                Text {
                    id: dndLabel
                    anchors.centerIn: parent
                    text: "󰂛"
                    color: colors.error
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                    opacity: dndMa.containsMouse ? 1 : 0.92
                }
                MouseArea {
                    id: dndMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleDndRequested()
                }
            }

            Rectangle {
                visible: root.dnd && (root.recActive || root.trayItems.length > 0)
                width: 1; height: 14
                color: colors.alpha(colors.outline, 0.18)
                Layout.alignment: Qt.AlignVCenter
            }

            // -- screen recording: 󰻂 --
            Item {
                visible: root.recActive
                implicitWidth: recLabel.implicitWidth
                implicitHeight: 16
                Text {
                    id: recLabel
                    anchors.centerIn: parent
                    text: root.recText
                    color: colors.error
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                    opacity: recMa.containsMouse ? 1 : 0.92
                }
                MouseArea {
                    id: recMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", "pkill -f gpu-screen-recorder; pkill -f wf-recorder &"])
                }
            }

            Rectangle {
                visible: root.recActive && root.trayItems.length > 0
                width: 1; height: 14
                color: colors.alpha(colors.outline, 0.18)
                Layout.alignment: Qt.AlignVCenter
            }

            // -- tray icons: LocalSend / OBS / Discord / etc. --
            Row {
                id: trayRow
                visible: root.trayItems.length > 0
                spacing: 8
                Repeater {
                    model: root.trayItems
                    delegate: Item {
                        id: trayEntry
                        required property var modelData
                        readonly property var item: modelData
                        width: 14; height: 14
                        Image {
                            anchors.fill: parent
                            source: trayEntry.item.icon
                            sourceSize.width: 14
                            sourceSize.height: 14
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            opacity: trayMa.containsMouse ? 1 : 0.82
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            id: trayMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (mouse.button === Qt.RightButton && trayEntry.item.hasMenu)
                                    trayEntry.item.display()
                                else
                                    trayEntry.item.activate()
                            }
                            onWheel: (wheel) => trayEntry.item.scroll(wheel.angleDelta.y, wheel.angleDelta.x > 0)
                        }
                    }
                }
            }
        }
    }
}
