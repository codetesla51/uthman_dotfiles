import Quickshell
import Quickshell.Io
import QtQuick

// MediaOsd — quickshell replacement for omarchy's swayosd.
// Glass pill at top-center showing volume / mic / brightness level.
// Fn keys hit IPC target "media" → we run the command, read real state,
// flash this overlay for ~1.4s. Hyprland binds live in bindings.conf.
PanelWindow {
    id: root

    property var colors
    property string mode: "volume"        // volume | mic | brightness
    property int value: 0
    property bool off: false              // muted / mic-muted (dim state)
    readonly property bool show: _show
    property bool _show: false

    anchors { top: true }
    margins { top: 70 }
    implicitWidth: 280
    implicitHeight: 64
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.show

    IpcHandler {
        target: "media"
        function volup(): void { root._media(["pamixer", "-i", "5"], "volume") }
        function voldown(): void { root._media(["pamixer", "-d", "5"], "volume") }
        function volmute(): void { root._media(["pamixer", "-t"], "volume") }
        function micmute(): void { root._media(["pamixer", "--default-source", "-t"], "mic") }
        function briup(): void { root._media(["brightnessctl", "set", "5%+", "-q"], "brightness") }
        function bridown(): void { root._media(["brightnessctl", "set", "5%-", "-q"], "brightness") }
        function brimax(): void { root._media(["brightnessctl", "set", "100%", "-q"], "brightness") }
        function brimin(): void { root._media(["brightnessctl", "set", "1%", "-q"], "brightness") }
    }

    function _media(cmd, m) {
        mode = m
        actProc.command = cmd
        actProc.running = true
    }

    // run action, then read fresh state, then show
    Process {
        id: actProc
        stdout: StdioCollector {}
        onExited: probeProc.running = true
    }

    Process {
        id: probeProc
        command: ["sh", "-c",
            "echo \"v=$(pamixer --get-volume 2>/dev/null || echo 0);vm=$(pamixer --get-mute 2>/dev/null || echo false);" +
            "m=$(pamixer --default-source --get-mute 2>/dev/null || echo false);" +
            "b=$(( $(brightnessctl g 2>/dev/null || echo 0) * 100 / $(brightnessctl m 2>/dev/null || echo 1) ))\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var kv = {}
                text.trim().split(";").forEach(function (pair) {
                    var i = pair.indexOf("=")
                    if (i > 0) kv[pair.slice(0, i)] = pair.slice(i + 1).trim()
                })
                if (root.mode === "volume") {
                    root.value = parseInt(kv.v) || 0
                    root.off = kv.vm === "true"
                } else if (root.mode === "mic") {
                    root.off = kv.m === "true"
                    root.value = root.off ? 0 : 100
                } else {
                    root.value = parseInt(kv.b) || 0
                    root.off = false
                }
                root._show = true
                hideTimer.restart()
            }
        }
    }

    Timer { id: hideTimer; interval: 1400; onTriggered: root._show = false }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        color: colors.alpha(colors.surface, 0.78)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.25)
        opacity: root.show ? 1 : 0
        scale: root.show ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.margins: 16
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "volume"
                        ? (root.off ? chr_mute : (root.value <= 33 ? chr_low : chr_high))
                        : root.mode === "mic"
                          ? (root.off ? chr_micoff : chr_mic)
                        : (root.value <= 20 ? chr_night : chr_sun)
                color: root.off ? colors.error : colors.primary
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 20
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            // label + bar column
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                width: parent.width - 32 - 20

                Text {
                    text: root.mode === "volume" ? (root.off ? "MUTED" : "VOLUME")
                        : root.mode === "mic" ? (root.off ? "MIC MUTED" : "MICROPHONE")
                        : "BRIGHTNESS"
                    color: root.off ? colors.error : colors.foreground
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                }

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: colors.alpha(colors.outline, 0.18)

                    Rectangle {
                        width: parent.width * root.value / 100
                        height: parent.height
                        radius: 4
                        color: root.off ? colors.error
                             : root.mode === "brightness" ? colors.tertiary
                             : colors.primary
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }
            }
        }
    }

    // glyph constants — filled by scripts/gen-glyphs.py (verified codepoints)
    readonly property string chr_mute: "󰝯"
    readonly property string chr_low: ""
    readonly property string chr_high: "󰛨"
    readonly property string chr_mic: ""
    readonly property string chr_micoff: ""
    readonly property string chr_sun: "󰖙"
    readonly property string chr_night: "󰕯"
}
