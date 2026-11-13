import QtQuick

// Wallpaper — two stacked images, crossfading when the path changes.
// Nothing else animates in this module.
//
// Image.source is a QUrl, so it is never compared with `===` against the
// pending string. Any Ready status while a path is pending is the load we
// asked for, because only one image is ever given a new source at a time.
Item {
    id: root

    property string path: ""
    property bool animate: true
    property bool showingB: false
    property string pending: ""

    function show(p) {
        if (!p || p === "")
            return
        if (p === pending)
            return
        pending = p
        if (showingB)
            imgA.source = p
        else
            imgB.source = p
    }

    function finish() {
        if (pending === "")
            return
        pending = ""
        showingB = !showingB
    }

    onPathChanged: show(path)

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.showingB ? 0 : 1
        onStatusChanged: if (status === Image.Ready && root.pending !== "") root.finish()
        Behavior on opacity {
            NumberAnimation { duration: root.animate ? 600 : 0; easing.type: Easing.OutCubic }
        }
    }

    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.showingB ? 1 : 0
        onStatusChanged: if (status === Image.Ready && root.pending !== "") root.finish()
        Behavior on opacity {
            NumberAnimation { duration: root.animate ? 600 : 0; easing.type: Easing.OutCubic }
        }
    }
}