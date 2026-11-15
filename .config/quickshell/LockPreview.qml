import Quickshell
import Quickshell.Wayland
import QtQuick
import "components"
import "lockscreen"

// Design harness only — not part of the shell, never autoloaded.
//
// Run it against a headless output and REMOVE that output when done:
//   hyprctl output create headless LOCKPREVIEW
//   quickshell -p ~/.config/quickshell/LockPreview.qml
//   grim -o LOCKPREVIEW /tmp/lock.png
//   hyprctl output remove LOCKPREVIEW
// A leftover output is captured by plain `grim`, so it shows up as a frozen
// lock plate stuck to the side of every screenshot.
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

    Colors { id: palette }
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