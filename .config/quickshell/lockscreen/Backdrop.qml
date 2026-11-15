import QtQuick
import Qt5Compat.GraphicalEffects

// Backdrop — the wallpaper, held back by one flat scrim, plus a true
// frosted patch under the plate: the wallpaper is captured, blurred and
// masked to the plate's rounded rectangle. The blur is frozen after the
// intro so an idle lock costs nothing. Set "background": "screenshot" in
// lockscreen.json to use the capture slot.
Item {
    id: root

    property var theme
    property var config
    property var glassRect: null
    property real glassRadius: 18
    property real glassOpacity: 1
    property bool glassLive: true
    // Animated by the lock surface: 0 while the desktop is still visible,
    // theme.backdropDim once the lock has settled.
    property real dim: 0

    readonly property string chosen: {
        if (!root.config) return ""
        if (root.config.backgroundSource === "screenshot"
                && root.config.screenshotPath !== "")
            return root.config.screenshotPath
        return root.config.wallpaperPath
    }
    readonly property string source: root.chosen !== ""
        ? "file://" + root.chosen : ""

    Rectangle {
        anchors.fill: parent
        color: root.theme ? root.theme.background : "#131313"
    }

    Image {
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: source !== "" && status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme ? root.theme.background : "#131313"
        opacity: root.dim
    }

    // The wallpaper again, offscreen, as the blur's source. hideSource keeps
    // it out of the normal scene while the effect still gets its texture.
    Item {
        id: wallSource
        width: root.width
        height: root.height

        Image {
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            onStatusChanged: if (status === Image.Ready) plateTexture.scheduleUpdate()
        }
    }

    ShaderEffectSource {
        id: plateTexture
        sourceItem: wallSource
        hideSource: true
        live: root.glassLive
        recursive: false
        sourceRect: root.glassRect
            ? Qt.rect(root.glassRect.x, root.glassRect.y,
                      root.glassRect.width, root.glassRect.height)
            : Qt.rect(0, 0, 1, 1)
        textureSize: root.glassRect
            ? Qt.size(Math.max(1, Math.floor(root.glassRect.width / 2)),
                      Math.max(1, Math.floor(root.glassRect.height / 2)))
            : Qt.size(1, 1)
    }

    FastBlur {
        id: glassBlur
        x: root.glassRect ? root.glassRect.x : 0
        y: root.glassRect ? root.glassRect.y : 0
        width: root.glassRect ? root.glassRect.width : 0
        height: root.glassRect ? root.glassRect.height : 0
        source: plateTexture
        radius: 26
        cached: true
        visible: false
    }

    Rectangle {
        id: glassMask
        x: root.glassRect ? root.glassRect.x : 0
        y: root.glassRect ? root.glassRect.y : 0
        width: root.glassRect ? root.glassRect.width : 0
        height: root.glassRect ? root.glassRect.height : 0
        radius: root.glassRadius
        visible: false
    }

    OpacityMask {
        x: root.glassRect ? root.glassRect.x : 0
        y: root.glassRect ? root.glassRect.y : 0
        width: root.glassRect ? root.glassRect.width : 0
        height: root.glassRect ? root.glassRect.height : 0
        source: glassBlur
        maskSource: glassMask
        cached: true
        opacity: root.glassOpacity
        visible: root.glassRect !== null
    }

    // One capture is enough once the intro has settled. If the surface is
    // reused and the box moves, update the frozen texture on demand.
    onGlassRectChanged: if (!root.glassLive) plateTexture.scheduleUpdate()

    Timer {
        interval: 1400
        running: true
        onTriggered: root.glassLive = false
    }
}