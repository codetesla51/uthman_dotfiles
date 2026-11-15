import QtQuick

// Wallpaper — two stacked images with one uninterruptible dissolve.
//
// The hidden slot loads the next image; only that exact URL may commit. A
// path arriving while loading replaces the pending target, and a path
// arriving mid-fade is queued until the dissolve ends. That keeps the old
// and new wallpapers from ever chasing each other or both sticking around.
Item {
    id: root

    property string path: ""
    property bool animate: true

    // The clock gates the subject reveal on this: true only when the new
    // backdrop is fully in place.
    readonly property bool settled: pendingPath === "" && !fading && loadingTarget === 0
    property string currentPath: ""
    // diagnostics: at rest exactly one of these is 1
    readonly property real opacityA: imgA.opacity
    readonly property real opacityB: imgB.opacity
    readonly property int statusA: imgA.status
    readonly property int statusB: imgB.status

    property string pendingPath: ""
    property string loadingPath: ""
    property string loadingUrl: ""
    property int loadingTarget: 0        // 0 none, 1 imgA, 2 imgB
    property int fadeMs: 0
    property bool fading: false
    property bool hasShown: false
    property bool showingB: false

    function urlFor(p) {
        return p && p.length > 0 ? Qt.resolvedUrl(p).toString() : ""
    }

    function request(p) {
        if (!p || p.length === 0)
            return
        if (p === root.pendingPath)
            return
        if (p === root.currentPath && root.pendingPath === "")
            return
        root.pendingPath = p
        root.pump()
    }

    function pump() {
        if (root.pendingPath === "" || root.fading || root.loadingTarget !== 0)
            return
        var target = root.showingB ? 1 : 2
        var img = target === 1 ? imgA : imgB
        root.loadingTarget = target
        root.loadingPath = root.pendingPath
        root.loadingUrl = root.urlFor(root.loadingPath)
        if (img.source.toString() === root.loadingUrl && img.status === Image.Ready) {
            root.finishLoad()
            return
        }
        img.source = root.loadingUrl
    }

    function imageReady(which) {
        if (root.loadingTarget !== which)
            return
        var img = which === 1 ? imgA : imgB
        if (img.source.toString() !== root.loadingUrl || img.status !== Image.Ready)
            return
        if (root.pendingPath === "") {
            root.loadingTarget = 0
            root.loadingPath = ""
            root.loadingUrl = ""
            return
        }
        if (root.pendingPath !== root.loadingPath) {
            // A newer path arrived while this one decoded: skip the stale one.
            root.loadingPath = root.pendingPath
            root.loadingUrl = root.urlFor(root.loadingPath)
            img.source = root.loadingUrl
            return
        }
        root.finishLoad()
    }

    function finishLoad() {
        if (root.loadingTarget === 0 || root.pendingPath === "")
            return
        var which = root.loadingTarget
        root.loadingTarget = 0
        root.loadingPath = ""
        root.loadingUrl = ""
        root.fadeMs = root.animate && root.hasShown ? 340 : 0
        root.hasShown = true
        root.currentPath = root.pendingPath
        root.pendingPath = ""
        root.showingB = which === 2
        root.fading = true
        fadeTimer.restart()
    }

    function failLoad(which) {
        if (root.loadingTarget !== which)
            return
        root.loadingTarget = 0
        root.loadingPath = ""
        root.loadingUrl = ""
        root.pendingPath = ""
        root.fading = false
    }

    Timer {
        id: fadeTimer
        interval: Math.max(0, root.fadeMs)
        repeat: false
        onTriggered: {
            root.fading = false
            if (root.pendingPath === root.currentPath)
                root.pendingPath = ""
            if (root.pendingPath !== "")
                root.pump()
        }
    }

    onPathChanged: request(path)
    Component.onCompleted: request(path)

    Image {
        id: imgA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.showingB ? 0 : 1
        onStatusChanged: {
            if (status === Image.Ready)
                root.imageReady(1)
            else if (status === Image.Error && root.loadingTarget === 1)
                root.failLoad(1)
        }
        Behavior on opacity {
            NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
    }

    Image {
        id: imgB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        opacity: root.showingB ? 1 : 0
        onStatusChanged: {
            if (status === Image.Ready)
                root.imageReady(2)
            else if (status === Image.Error && root.loadingTarget === 2)
                root.failLoad(2)
        }
        Behavior on opacity {
            NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic }
        }
    }
}
