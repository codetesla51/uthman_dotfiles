import Quickshell
import Quickshell.Io
import QtQuick

// QuoteSource — one quote per line from the configured quote file.
// The pick happens once per instance (once per lock) so the line does not
// flicker while the screen is up. A missing file is an empty state.
QtObject {
    id: root

    property var config
    property string text: ""
    property bool ready: false

    readonly property string path: root.config ? root.config.quotePath : ""

    function pick() {
        var lines = String(rawText).split("\n")
        var usable = []
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line !== "" && line.charAt(0) !== "#")
                usable.push(line)
        }
        if (usable.length === 0) {
            root.text = ""
            root.ready = true
            return
        }
        root.text = usable[Math.floor(Math.random() * usable.length)]
        root.ready = true
    }

    property string rawText: ""

    property FileView view: FileView {
        path: root.path
        printErrors: false
        onLoaded: {
            root.rawText = text()
            root.pick()
        }
        onLoadFailed: {
            root.rawText = ""
            root.ready = true
        }
    }
}