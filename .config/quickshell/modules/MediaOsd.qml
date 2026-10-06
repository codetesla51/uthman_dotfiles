import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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

    // screen height for vertical centring — a stretched window would make the
    // compositor blur the whole column, not just the chip
    readonly property int screenH: {
        try {
            var ss = Quickshell.screens
            var list = (ss && ss.values) ? ss.values : ss
            if (list && list.length) return list[0].height || 900
        } catch (e) {}
        return 900
    }

    anchors { left: true; top: true }
    margins { left: 12; top: Math.max(0, Math.round((root.screenH - chip.bodyH) / 2)) }
    implicitWidth: chip.bodyW
    implicitHeight: chip.bodyH
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.show
    WlrLayershell.namespace: "qs-osd"

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

    OsdChip {
        id: chip
        anchors.fill: parent
        colors: root.colors
        vertical: true
        tailLength: 130
        // surface @ 0.78 + primary @ 0.25 hairline — the fill the OSD shipped
        // with before it became a chip. OsdChip already defaults to exactly
        // this, so don't override it.
        stroke: colors.alpha(colors.primary, 0.25)
        // no opacity anywhere: the fade-out never rendered anyway (the window
        // hides on _show=false), and the fade-in left the chip looking dim.
        // Scale alone does the entrance.
        opacity: 1
        scale: root.show ? 1 : 0.9
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.Bezier; easing.bezierCurve: [0.2, 0.9, 0.3, 1.2] } }

        // glyph rides the circle lobe
        iconSlot: Text {
            anchors.centerIn: parent
            text: root.mode === "volume"
                    ? (root.off ? root.chr_mute : (root.value <= 33 ? root.chr_low : root.chr_high))
                    : root.mode === "mic"
                      ? (root.off ? root.chr_micoff : root.chr_mic)
                    : (root.value <= 20 ? root.chr_night : root.chr_sun)
            color: root.off ? colors.error : colors.primary
            font.family: colors.fontSans
            font.pixelSize: 20
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // level bar alone on the tail, vertically centred in the band
        tailSlot: Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: 10
            height: parent.height
            radius: 5
            color: colors.alpha(colors.outline, 0.35)

            Rectangle {
                width: parent.width
                height: parent.height * root.value / 100
                radius: 5
                anchors.bottom: parent.bottom
                color: root.off ? colors.error
                     : root.mode === "brightness" ? colors.tertiary
                     : colors.primary
                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }
    }

    // glyph constants — filled by scripts/gen-glyphs.py (verified codepoints)
    readonly property string chr_mute: "󰖁"
    readonly property string chr_low: ""
    readonly property string chr_high: "󰕾"
    readonly property string chr_mic: ""
    readonly property string chr_micoff: ""
    readonly property string chr_sun: "󰖙"
    readonly property string chr_night: "󰖔"
}
