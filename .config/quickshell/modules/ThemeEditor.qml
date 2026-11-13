import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../components/Bloom.js" as Bloom

// ThemeEditor — post-wallpaper theme tweaks (mode / scheme + live preview).
// Port of ui-options/theme option A (control strip). Opens after an explicit
// wallpaper pick (Wallshelf) or via SUPER ALT G. Apply re-runs getTheme with
// the chosen flags on the current wallpaper; choices persist in cache.
// Contrast is fixed at the getTheme default (0.2) — no control surfaces it.
// Preview: every mode/scheme change (700ms debounce) runs matugen --dry-run
// and paints the swatches with exactly what Apply would generate.
// HEIGHT BUDGET 740: margins 32 + header 30 + 5x10 gaps + wprow 84 + mode 92
//   + scheme 262 + palette 100 + footer 56 + status 30.
// TYPE SCALE: 9 caps labels · 11 body · 13 titles. Spacing: 16 / 10 / 14.
FloatingWindow {
    id: root
    property var colors
    property bool open: false
    property string fontUi: "JetBrainsMono Nerd Font Mono"

    title: "ThemeEditor"
    implicitWidth: 460
    implicitHeight: 740
    minimumSize: Qt.size(440, 700)
    maximumSize: Qt.size(480, 800)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here on purpose. shell.qml owns target "themeedit"
    // and lazy-loads this module; a second handler for the same target wins
    // nothing and logs "registered but will not be used".

    // ── state ──
    property string mode: "dark"
    property string scheme: "scheme-fidelity"
    property double contrast: 0.2   // fixed at getTheme default; not surfaced
    property string wallPath: ""
    property string wallName: ""
    property bool working: false
    property string statusMsg: ""
    property bool statusErr: false
    // live preview: what Apply would generate ("" = not yet previewed)
    property string pvPrimary: ""
    property string pvSecondary: ""
    property string pvTertiary: ""
    property string pvKey: ""
    readonly property string stateFile: Quickshell.env("HOME") + "/.cache/quickshell/themeedit.json"
    readonly property var schemes: [
        { k: "scheme-content", t: "content" },
        { k: "scheme-expressive", t: "expressive" },
        { k: "scheme-fidelity", t: "fidelity" },
        { k: "scheme-fruit-salad", t: "fruit-salad" },
        { k: "scheme-monochrome", t: "monochrome" },
        { k: "scheme-neutral", t: "neutral" },
        { k: "scheme-rainbow", t: "rainbow" },
        { k: "scheme-tonal-spot", t: "tonal-spot" },
        { k: "scheme-vibrant", t: "vibrant" },
        { k: "scheme-smart", t: "smart" }
    ]

    function schemeName(k) { return String(k).replace(/^scheme-/, "") }

    onOpenChanged: {
        if (root.open) {
            root.statusMsg = ""
            root.statusErr = false
            loadProc.running = true
            wallProc.running = true
            card.forceActiveFocus()
            // take focus: dim_inactive would otherwise leave this IPC-opened
            // popup permanently darkened (no nodim rule on this Hyprland)
            Quickshell.execDetached(["sh", "-c", "sleep 0.4; hyprctl dispatch focuswindow 'title:ThemeEditor' >/dev/null 2>&1"])
            openAnim.restart()
        } else closeAnim.restart()
    }

    // current wallpaper: the live background symlink
    Process {
        id: wallProc
        command: ["sh", "-c", "readlink \"$HOME/.config/theme/current/background\" 2>/dev/null || readlink \"$HOME/.config/omarchy/current/background\" 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var p = text.trim()
                if (p !== "") {
                    root.wallPath = p
                    root.wallName = p.split("/").pop()
                    pvTimer.restart()
                }
            }
        }
    }
    // last choices (written on every successful apply)
    Process {
        id: loadProc
        command: ["sh", "-c", "cat \"" + root.stateFile + "\" 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var o = null
                try { o = JSON.parse(text) } catch (e) { o = null }
                if (!o) return
                if (o.mode === "dark" || o.mode === "light") root.mode = o.mode
                if (typeof o.scheme === "string" && o.scheme.indexOf("scheme-") === 0) root.scheme = o.scheme
                root.contrast = 0.2   // stale files may hold slider-era values; fixed now
            }
        }
    }
    // the heavy run: getTheme recolors everything off the current wallpaper
    Process {
        id: applyProc
        stdout: StdioCollector { id: applyOut; waitForEnd: true }
        onExited: function (code) {
            root.working = false
            if (code === 0) {
                root.statusErr = false
                root.statusMsg = "Applied " + root.schemeName(root.scheme) + " · " + root.mode
                Quickshell.execDetached(["sh", "-c", "printf '%s' '{\"mode\":\"" + root.mode + "\",\"scheme\":\"" + root.scheme + "\",\"contrast\":" + root.contrast + "}' > \"" + root.stateFile + "\""])
            } else {
                root.statusErr = true
                root.statusMsg = "matugen failed — kept previous theme"
            }
            statusClear.restart()
        }
    }
    Timer { id: statusClear; interval: 6000; onTriggered: { root.statusMsg = ""; root.statusErr = false } }

    // live preview: dry-run matugen off the current wallpaper and paint the
    // swatches with exactly what Apply would generate. Debounced 700ms; a run
    // in flight coalesces (never two matugens at once).
    function pvNowKey() { return root.mode + "|" + root.scheme }
    // dry-run JSON nests per-mode for some modes ({dark:{color}, light:{color}})
    // and flat ({color}) for others — take the matching branch first
    function pvPick(node, m) {
        if (!node) return ""
        if (typeof node.color === "string") return node.color
        var sub = node[m] || node.default
        if (sub && typeof sub.color === "string") return sub.color
        return ""
    }
    onModeChanged: pvTimer.restart()
    onSchemeChanged: pvTimer.restart()
    Timer {
        id: pvTimer
        interval: 700; repeat: false
        onTriggered: {
            if (!root.open || root.wallPath === "") return
            if (previewProc.running) { pvTimer.restart(); return }
            root.pvKey = root.pvNowKey()
            previewProc.command = ["sh", "-c", "matugen image '" + root.wallPath.replace(/'/g, "'\\''") + "' -m '" + root.mode + "' -t '" + root.scheme + "' --contrast 0.2 --source-color-index 0 --dry-run -j hex 2>/dev/null"]
            previewProc.running = true
        }
    }
    Process {
        id: previewProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var o = null
                try { o = JSON.parse(text) } catch (e) { o = null }
                var c = o && o.colors
                var p1 = root.pvPick(c && c.primary, root.mode)
                var p2 = root.pvPick(c && c.secondary, root.mode)
                var p3 = root.pvPick(c && c.tertiary, root.mode)
                if (p1 !== "" && p2 !== "" && p3 !== "") {
                    root.pvPrimary = p1
                    root.pvSecondary = p2
                    root.pvTertiary = p3
                }
                if (root.pvKey !== root.pvNowKey()) pvTimer.restart()
            }
        }
    }

    function doApply() {
        if (root.working || root.wallPath === "") return
        root.working = true
        root.statusMsg = ""
        root.statusErr = false
        applyProc.command = [Quickshell.env("HOME") + "/.local/bin/getTheme", "-m", root.mode, "-t", root.scheme, "-c", String(root.contrast), root.wallPath]
        applyProc.running = true
    }
    function openTheme() {
        Quickshell.execDetached(["quickshell", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", "theme", "toggle"])
    }

    // ================= UI =================
    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: card; property: "rotation"; from: Bloom.panelRotate; to: 0; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Bloom.normal; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
        NumberAnimation { target: card; property: "scale"; from: Bloom.panelScale; to: 1; duration: Bloom.panel; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.spring }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: card; property: "rotation"; to: Bloom.panelRotate; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
        NumberAnimation { target: card; property: "scale"; to: Bloom.panelScale; duration: Bloom.close; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.out }
    }

    component Cap: Text {
        color: colors.alpha(colors.outline, 0.75)
        font.family: root.fontUi
        font.pixelSize: 9
        font.weight: Font.Bold
        font.letterSpacing: 1.2
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: "Theme editor"
                color: colors.foreground
                font.family: root.fontUi
                font.pixelSize: 13
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            // ── wallpaper row ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                spacing: 14
                Rectangle {
                    width: 64; height: 64; radius: 10
                    Layout.alignment: Qt.AlignVCenter
                    clip: true
                    color: colors.alpha(colors.tertiary, 0.25)
                    border.width: 1
                    border.color: colors.alpha(colors.tertiary, 0.45)
                    Image {
                        anchors.fill: parent
                        source: root.wallPath !== "" ? "file://" + root.wallPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 5
                    Text {
                        text: root.wallName !== "" ? root.wallName : "no wallpaper"
                        color: colors.foreground
                        font.family: root.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: root.schemeName(root.scheme) + " · " + root.mode
                        color: colors.secondary
                        font.family: root.fontUi
                        font.pixelSize: 11
                        Layout.fillWidth: true
                    }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 76; implicitHeight: 32; radius: 8
                    color: chMa.containsMouse ? colors.alpha(colors.secondary, 0.16) : "transparent"
                    border.width: 1
                    border.color: colors.alpha(colors.secondary, 0.5)
                    transform: Translate { y: chMa.containsMouse ? -2 : 0; Behavior on y { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } } }
                    Text { anchors.centerIn: parent; text: "Change"; color: colors.secondary; font.family: root.fontUi; font.pixelSize: 11; font.weight: Font.DemiBold }
                    MouseArea { id: chMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openTheme() }
                }
            }

            // ── mode ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Cap { text: "MODE" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: ["dark", "light"]
                        Rectangle {
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 38; radius: 9
                            color: root.mode === modelData ? colors.alpha(colors.primary, 0.2) : "transparent"
                            border.width: 1
                            border.color: root.mode === modelData ? colors.alpha(colors.primary, 0.55) : colors.alpha(colors.outline, 0.2)
                            transform: Translate { y: segMa.containsMouse && root.mode !== modelData ? -2 : 0; Behavior on y { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } } }
                            Text { anchors.centerIn: parent; text: modelData === "dark" ? "Dark" : "Light"; color: root.mode === modelData ? colors.primary : colors.alpha(colors.outline, 0.8); font.family: root.fontUi; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea { id: segMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mode = modelData }
                        }
                    }
                }
            }

            // ── scheme ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Cap { text: "COLOR SCHEME" }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    Repeater {
                        model: root.schemes
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 40; radius: 9
                            color: root.scheme === modelData.k ? colors.alpha(colors.primary, 0.16) : colors.alpha(colors.surface, 0.5)
                            border.width: 1
                            border.color: root.scheme === modelData.k ? colors.alpha(colors.primary, 0.6) : colors.alpha(colors.outline, 0.2)
                            transform: Translate { y: chipMa.containsMouse ? -2 : 0; Behavior on y { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10
                                Text {
                                    text: modelData.t
                                    color: root.scheme === modelData.k ? colors.primary : colors.foreground
                                    font.family: root.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    spacing: 4
                                    Repeater {
                                        model: [colors.primary, colors.secondary, colors.tertiary]
                                        Rectangle { required property var modelData; width: 9; height: 9; radius: 4.5; color: modelData }
                                    }
                                }
                            }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.scheme = modelData.k }
                        }
                    }
                }
            }

            // ── live palette: preview of what Apply generates ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Cap { text: root.pvPrimary !== "" ? "PREVIEW · " + root.schemeName(root.scheme) + " " + root.mode : "LIVE PALETTE" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: [
                            { t: "primary", c: root.pvPrimary !== "" ? root.pvPrimary : colors.primary },
                            { t: "secondary", c: root.pvSecondary !== "" ? root.pvSecondary : colors.secondary },
                            { t: "tertiary", c: root.pvTertiary !== "" ? root.pvTertiary : colors.tertiary },
                            { t: "surface", c: colors.surfaceVariant }
                        ]
                        ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4
                            Rectangle { Layout.fillWidth: true; implicitHeight: 34; radius: 9; color: modelData.c; border.width: 1; border.color: colors.alpha(colors.outline, 0.2) }
                            Text { text: modelData.t; color: colors.alpha(colors.outline, 0.7); font.family: root.fontUi; font.pixelSize: 9; Layout.fillWidth: true; elide: Text.ElideRight }
                        }
                    }
                }
            }

            // ── footer: status slot (fixed height, swaps in place) + apply ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: root.statusMsg !== ""
                    text: root.statusMsg
                    color: root.statusErr ? colors.error : colors.primary
                    font.family: root.fontUi
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44; radius: 10
                    color: root.working ? colors.alpha(colors.primary, 0.4) : colors.primary
                    opacity: root.working ? 0.7 : 1
                    transform: Translate { y: apMa.containsMouse && !root.working ? -2 : 0; Behavior on y { NumberAnimation { duration: Bloom.fast; easing.type: Easing.Bezier; easing.bezierCurve: Bloom.move } } }
                    Text { anchors.centerIn: parent; text: root.working ? "Working…" : "Apply theme"; color: colors.background; font.family: root.fontUi; font.pixelSize: 13; font.weight: Font.Bold }
                    Rectangle {
                        visible: root.working
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        height: 2
                        width: 0
                        radius: 1
                        color: colors.surfaceVariant
                    }
                    MouseArea { id: apMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.working; onClicked: root.doApply() }
                }
                Text {
                    text: "esc closes"
                    color: colors.alpha(colors.outline, 0.7)
                    font.family: root.fontUi
                    font.pixelSize: 10
                }
            }
        }
    }
}
