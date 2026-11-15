import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Preview — the same LockSurface, rendered on the off-screen LOCKPREVIEW
// output only. It is not a floating window and it never asks for keyboard
// focus, so it cannot interrupt the session. No PAM here either: this is a
// visual harness, not an auth test.
PanelWindow {
    id: win

    readonly property var previewScreen: {
        var list = Quickshell.screens
        for (var i = 0; i < list.length; i++)
            if (list[i].name === "LOCKPREVIEW") return list[i]
        return null
    }

    visible: win.previewScreen !== null
    screen: win.previewScreen
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    color: "transparent"
    WlrLayershell.namespace: "qs-lock-design"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The preview folder cannot import the bar's Colors module, so read the
    // same Matugen file directly. Only the roles the lock uses are needed.
    QtObject {
        id: palette
        property color background: "#131313"
        property color foreground: "#e2e2e2"
        property color primary: "#ffffff"
        property color secondary: "#c6c6c6"
        property color tertiary: "#e2e2e2"
        property color error: "#ffb4ab"
        property color outline: "#969696"

        function hex(h) {
            return Qt.rgba(parseInt(h.substr(1, 2), 16) / 255,
                parseInt(h.substr(3, 2), 16) / 255,
                parseInt(h.substr(5, 2), 16) / 255, 1)
        }

        function apply(css) {
            var re = /@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;/g
            var m
            var map = {}
            while ((m = re.exec(css)) !== null) map[m[1].toLowerCase()] = m[2]
            if (map["background"]) background = hex(map["background"])
            if (map["foreground"]) foreground = hex(map["foreground"])
            if (map["primary"]) primary = hex(map["primary"])
            if (map["secondary"]) secondary = hex(map["secondary"])
            if (map["tertiary"]) tertiary = hex(map["tertiary"])
            if (map["error"]) error = hex(map["error"])
            if (map["outline"]) outline = hex(map["outline"])
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/colors.css"
        printErrors: false
        onLoaded: palette.apply(text())
    }

    LockTheme { id: theme; palette: palette }
    LockConfig { id: config }

    property var sampleNotifications: [
        { nid: 3, appName: "firefox", summary: "Download complete", body: "", time: "22:38", urgent: false },
        { nid: 2, appName: "kitty", summary: "Build finished", body: "", time: "22:31", urgent: false },
        { nid: 1, appName: "system", summary: "Battery low", body: "", time: "22:14", urgent: true }
    ]


    LockSurface {
        anchors.fill: parent
        theme: theme
        config: config
        authState: "idle"
        authAttempts: 0
        authMessage: ""
        notifications: win.sampleNotifications
        autoUnlockIn: -1
        onSubmitted: function (pw) {}
    }
}