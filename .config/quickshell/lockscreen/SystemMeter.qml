import QtQuick

// SystemMeter — one label/value row over a real sparkline. The graph is
// fixed to 0..100%, not auto-scaled, so "quiet" and "busy" always look
// different. History is an array of 0..1 fractions.
Item {
    id: root

    property var theme
    property string label: ""
    property string glyph: ""
    property string valueText: ""
    property string detailText: ""
    property var history: []
    property color tint: root.theme ? root.theme.primary : "#ffffff"

    implicitHeight: 56

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.theme ? root.theme.meterHeaderHeight : 16

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                theme: root.theme
                glyph: root.glyph
                size: 12
                tint: root.tint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 9
                font.letterSpacing: 1.2
                font.weight: Font.DemiBold
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.detailText
                color: root.theme ? root.theme.quiet : "#565656"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize : 9
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.valueText
                color: root.theme ? root.theme.foreground : "#e2e2e2"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.smallSize : 10
                font.weight: Font.Medium
            }
        }
    }

    Canvas {
        id: graph
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        onWidthChanged: requestPaint()

        Connections {
            target: root
            function onHistoryChanged() { graph.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var hist = root.history || []
            var n = hist.length
            if (n < 2) return

            var bottom = height - 1
            var top = 4
            var usable = bottom - top

            function px(i) { return i * width / (n - 1) }
            function py(v) {
                return bottom - Math.max(0, Math.min(1, v)) * usable
            }

            // Quarter rules: the scale is fixed 0..100%, so quiet always
            // sits low and busy always sits high.
            ctx.strokeStyle = root.theme
                ? root.theme.alpha(root.theme.foreground, 0.055)
                : "rgba(255,255,255,0.055)"
            ctx.lineWidth = 1
            for (var g = 1; g <= 3; g++) {
                var gy = bottom - (g / 4) * usable
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(width, gy)
                ctx.stroke()
            }

            ctx.beginPath()
            ctx.moveTo(px(0), py(hist[0]))
            for (var i = 1; i < n; i++) ctx.lineTo(px(i), py(hist[i]))
            ctx.lineTo(width, bottom)
            ctx.lineTo(0, bottom)
            ctx.closePath()
            ctx.fillStyle = root.theme
                ? root.theme.alpha(root.tint, 0.12) : "rgba(255,255,255,0.10)"
            ctx.fill()

            ctx.beginPath()
            ctx.moveTo(px(0), py(hist[0]))
            for (var j = 1; j < n; j++) ctx.lineTo(px(j), py(hist[j]))
            ctx.strokeStyle = root.theme ? root.theme.alpha(root.tint, 0.92) : "#ffffff"
            ctx.lineWidth = 1.5
            ctx.stroke()

            // The live head, so a flat run still reads as "now".
            ctx.beginPath()
            ctx.arc(width - 1, py(hist[n - 1]), 2, 0, Math.PI * 2)
            ctx.fillStyle = root.theme ? root.theme.alpha(root.tint, 0.95) : "#ffffff"
            ctx.fill()
        }
    }
}