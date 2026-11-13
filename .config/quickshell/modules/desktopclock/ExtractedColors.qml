import QtQuick

// ExtractedColors — last-resort palette when the Matugen theme file is absent.
// Downsamples the wallpaper, picks the most saturated pixel as the hue.
Item {
    id: root

    property string source: ""
    property color primary: "#9a9a9a"
    property color secondary: "#c0c0c0"

    Image {
        id: img
        source: root.source
        visible: false
        asynchronous: true
        onStatusChanged: if (status === Image.Ready) canvas.requestPaint()
    }

    function hueOf(r, g, b, mx, mn) {
        if (mx === mn) return 0
        var h
        if (mx === r) h = ((g - b) / (mx - mn)) % 6
        else if (mx === g) h = (b - r) / (mx - mn) + 2
        else h = (r - g) / (mx - mn) + 4
        return ((h * 60) % 360 + 360) % 360 / 360
    }

    Canvas {
        id: canvas
        width: 24
        height: 14
        visible: false

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            try { ctx.drawImage(img, 0, 0, width, height) } catch (e) { return }
            var d = ctx.getImageData(0, 0, width, height).data
            var best = -1, bh = 0, bs = 0, bl = 0
            for (var i = 0; i < d.length; i += 4) {
                var r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255
                var mx = Math.max(r, g, b), mn = Math.min(r, g, b)
                var l = (mx + mn) / 2
                var s = mx === mn ? 0 : (l > 0.5 ? (mx - mn) / (2 - mx - mn) : (mx - mn) / (mx + mn))
                if (s > best) { best = s; bh = hueOf(r, g, b, mx, mn); bs = s; bl = l }
            }
            if (best < 0) return
            root.primary = Qt.hsla(bh, Math.min(0.78, Math.max(0.42, bs * 0.95)), Math.min(0.82, Math.max(0.58, bl + 0.18)), 1)
            root.secondary = Qt.hsla((bh + 0.07) % 1, 0.32, 0.74, 1)
        }
    }
}
