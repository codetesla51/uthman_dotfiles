import Quickshell
import Quickshell.Io
import QtQuick

// Palette parsed live from Matugen's ~/.config/quickshell/colors.css.
// Matugen-generated palette — theme changes propagate instantly
// via FileView's native file watching.
Item {
    id: root

    property string colorsFile: Quickshell.env("HOME") + "/.config/quickshell/colors.css"

    property color background: "#17130f"
    property color foreground: "#ebe1da"
    property color primary: "#f3bc87"
    property color secondary: "#dfc1a8"
    property color tertiary: "#9bcee3"
    property color error: "#ffb4ab"
    property color surface: "#17130f"
    property color on_surface: "#efe5df"
    property color surfaceVariant: "#50453b"
    property color outline: "#a39487"

    readonly property real pillBg: 0.6
    readonly property real pillBgHover: 0.8
    readonly property real pillBorder: 0.15
    readonly property real pillBorderHover: 0.45

    function apply(css) {
        var re = /@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;/g
        var m
        var map = {}
        while ((m = re.exec(css)) !== null) {
            map[m[1].toLowerCase()] = m[2]
        }
        if (map["background"]) background = hexToColor(map["background"])
        if (map["foreground"]) foreground = hexToColor(map["foreground"])
        if (map["primary"]) primary = hexToColor(map["primary"])
        if (map["secondary"]) secondary = hexToColor(map["secondary"])
        if (map["tertiary"]) tertiary = hexToColor(map["tertiary"])
        if (map["error"]) error = hexToColor(map["error"])
        if (map["surface"]) surface = hexToColor(map["surface"])
        if (map["on_surface"]) on_surface = hexToColor(map["on_surface"])
        if (map["surface_variant"]) surfaceVariant = hexToColor(map["surface_variant"])
        if (map["outline"]) outline = hexToColor(map["outline"])
    }

    function hexToColor(h) {
        var r = parseInt(h.substr(1, 2), 16) / 255
        var g = parseInt(h.substr(3, 2), 16) / 255
        var b = parseInt(h.substr(5, 2), 16) / 255
        return Qt.rgba(r, g, b, 1)
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // poll cheaply; text() triggers an async read, onLoaded applies
    // Matugen REPLACES colors.css (new inode) on every theme switch, which
    // silently breaks FileView's watcher. Poll + force a fresh read by
    // resetting path — cheap for a 300-byte file, bulletproof against replaces.
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!root.colorsFile) return
            colorsView.path = ""
            colorsView.path = root.colorsFile
        }
    }

    FileView {
        id: colorsView
        path: root.colorsFile
        printErrors: false
        onLoaded: root.apply(text())
    }
}
