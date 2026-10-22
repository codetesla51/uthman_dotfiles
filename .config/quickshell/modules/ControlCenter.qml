import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

// Control Center — "Focus" layout. Regular floating window (SUPER ALT P).
//
//   header   clock | weather | feels / humidity / wind
//   middle   now playing (artist art as background) | volume, brightness, network
//   bottom   week + pixel bot, then screen time showcase
//
// Height budget (720): 720 - 18 top - 18 bottom - 14 gap - 14 gap
// = 684 content. Header 68 + middle 328 + bottom 260 = 684.
//
// Same integrations as before: Mpris, cava, wttr.in, wpctl/brightnessctl,
// `screentime --export`, NetRate, PixelBot, WeatherIcon.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    // Body copy follows the shared font knob (FiraCode Nerd Font), matching
    // the previous control panel. Glyphs stay on the same family so the
    // private-use icon codepoints still resolve.
    readonly property string uiFont: colors ? colors.fontSans : "FiraCode Nerd Font"

    // ── state ────────────────────────────────────────────────────────────
    property real brightness: 0
    property real volume: 0
    property bool muted: false

    property string weatherTemp: "--°"
    property string weatherFeel: "--°"
    property string weatherLoc: "—"
    property string weatherCond: "…"
    property string weatherKind: "partly"
    property string weatherHumidity: "—"
    property string weatherWind: "—"

    function condKind(c) {
        var t = String(c || "").toLowerCase()
        if (t.indexOf("thunder") !== -1 || t.indexOf("storm") !== -1) return "storm"
        if (t.indexOf("snow") !== -1 || t.indexOf("sleet") !== -1 || t.indexOf("hail") !== -1) return "snow"
        if (t.indexOf("rain") !== -1 || t.indexOf("drizzle") !== -1 || t.indexOf("shower") !== -1) return "rain"
        if (t.indexOf("fog") !== -1 || t.indexOf("mist") !== -1 || t.indexOf("haze") !== -1) return "fog"
        if (t.indexOf("partly") !== -1 || t.indexOf("part") !== -1) return "partly"
        if (t.indexOf("clear") !== -1 || t.indexOf("sun") !== -1) return "clear"
        if (t.indexOf("cloud") !== -1 || t.indexOf("overcast") !== -1) return "cloud"
        return "partly"
    }
    function hiResArt(u) {
        var s = String(u || "")
        if (s.indexOf("googleusercontent.com") === -1) return s
        return s.replace(/([=&])w\d+-h\d+([-_a-z0-9]*)/gi, "$1w640-h640")
    }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    function fmtClock(sec) {
        var s = Math.floor(sec); var m = Math.floor(s / 60); s = s % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function fmtHM(secs) {
        var m = Math.round(secs / 60)
        return Math.floor(m / 60) + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
    }

    // ── clock + week ─────────────────────────────────────────────────────
    property string clockText: "--:--"
    Timer {
        interval: 1000; running: root.open; repeat: true; triggeredOnStart: true
        onTriggered: {
            var n = new Date()
            root.clockText = Qt.formatTime(n, "HH:mm")
        }
    }
    property var weekDays: []
    property string monthLabel: ""
    property string weekLabel: ""
    function isoWeek(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        var day = (t.getUTCDay() + 6) % 7
        t.setUTCDate(t.getUTCDate() - day + 3)
        var first = new Date(Date.UTC(t.getUTCFullYear(), 0, 4))
        var fday = (first.getUTCDay() + 6) % 7
        first.setUTCDate(first.getUTCDate() - fday + 3)
        return 1 + Math.round((t - first) / (7 * 864e5))
    }
    function buildWeek() {
        var n = new Date()
        var off = (n.getDay() + 6) % 7
        var mon = new Date(n.getFullYear(), n.getMonth(), n.getDate() - off)
        var names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var out = []
        for (var i = 0; i < 7; i++) {
            var d = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i)
            out.push({ dow: names[i], day: d.getDate(), today: i === off, wknd: i >= 5 })
        }
        weekDays = out
        monthLabel = Qt.formatDate(n, "MMMM yyyy")
        weekLabel = "Week " + isoWeek(n)
    }

    // ── media ────────────────────────────────────────────────────────────
    property var player: Mpris.players.values.find(function(p){ return p.isPlaying }) || Mpris.players.values[0] || null
    readonly property bool hasPlayer: player !== null
    readonly property bool isPlaying: hasPlayer && player.playbackState === MprisPlaybackState.Playing
    property string npTitle: hasPlayer ? (player.trackTitle || "Unknown") : "Nothing playing"
    property string npArtist: {
        if (!hasPlayer) return ""
        var a = player.trackArtist
        return a && a.length > 0 ? a : "Unknown artist"
    }
    property real npPos: {
        if (!hasPlayer || !player.length || player.length <= 0) return 0
        return Math.max(0, Math.min(1, player.position / player.length))
    }
    property string npCur: (!hasPlayer || player.length <= 0) ? "0:00" : fmtClock(player.position)
    property string npTot: (!hasPlayer || player.length <= 0) ? "0:00" : fmtClock(player.length)
    // position only ticks when asked to
    Timer { interval: 1000; running: root.open && root.isPlaying; repeat: true; onTriggered: if (root.hasPlayer) root.player.positionChanged() }

    // visualizer — live cava feed (24 values, drawn as 48 mirrored bars)
    readonly property int vizBars: 24
    readonly property int vizDraw: 48
    property var vizLevels: []
    function vizApply(line) {
        var parts = line.trim().split(";")
        if (parts.length < root.vizBars) return
        var arr = new Array(root.vizBars)
        for (var i = 0; i < root.vizBars; i++)
            arr[i] = Math.max(0, Math.min(100, parseInt(parts[i]) || 0))
        vizLevels = arr
    }
    function vizLevel(i) {
        if (vizLevels.length < vizBars) return 0
        var p = i * (vizBars - 1) / (vizDraw - 1)
        var a = Math.floor(p), b = Math.min(vizBars - 1, a + 1)
        return (vizLevels[a] + (vizLevels[b] - vizLevels[a]) * (p - a)) / 100
    }
    Process {
        id: vizProc
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/scripts/cava-qs.conf"]
        running: root.open
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line){ root.vizApply(line) } }
    }

    // ── screen time (same `screentime` daemon as ScreenTime.qml) ─────────
    // Defaults are empty on purpose: the showcase only shows measured data.
    property var activityLast7: []
    property int chartHi: -1
    readonly property real weekMax: {
        var m = 1
        for (var i = 0; i < activityLast7.length; i++)
            if (activityLast7[i].secs > m) m = activityLast7[i].secs
        return m
    }
    readonly property real avgDay: {
        if (activityLast7.length === 0) return 0
        var total = 0
        for (var i = 0; i < activityLast7.length; i++) total += activityLast7[i].secs
        return total / activityLast7.length
    }
    readonly property real usageToday: activityLast7.length > 0 ? activityLast7[activityLast7.length - 1].secs : 0
    Process {
        id: activityFetcher
        command: ["screentime", "--export", "all"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(text)
                    var src = j.last7 || []
                    var days = []
                    for (var i = 0; i < src.length; i++) {
                        days.push({
                            display: src[i].display || src[i].day || "",
                            secs: src[i].secs || 0,
                            today: !!src[i].today
                        })
                    }
                    if (days.length > 0) root.activityLast7 = days
                } catch (e) {}
            }
        }
    }

    // ── system controls ──────────────────────────────────────────────────
    property real _volSent: -1
    property real _briSent: -1
    function setBrightness(v){ Quickshell.execDetached(["sh","-c","brightnessctl set "+Math.round(v*100)+"% >/dev/null 2>&1 &"]) }
    function setVolume(v){ Quickshell.execDetached(["sh","-c","wpctl set-volume @DEFAULT_AUDIO_SINK@ "+v.toFixed(2)+" >/dev/null 2>&1 || pactl set-sink-volume @DEFAULT_SINK@ "+Math.round(v*100)+"% >/dev/null 2>&1 &"]) }
    function toggleMute(){ root.muted = !root.muted; Quickshell.execDetached(["sh","-c","wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1 &"]) }
    function dragVolume(v) {
        if (root.muted) root.toggleMute()
        root.volume = v
        if (Math.abs(v - _volSent) > 0.05) { _volSent = v; root.setVolume(v) }
    }
    function dragBrightness(v) {
        root.brightness = Math.max(0.01, v)
        if (Math.abs(v - _briSent) > 0.05) { _briSent = v; root.setBrightness(root.brightness) }
    }
    Process {
        id: volProbe
        command: ["sh", "-c", "echo \"v=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null);b=$(brightnessctl g 2>/dev/null):$(brightnessctl m 2>/dev/null)\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var t = text.trim()
                var vm = t.match(/Volume:\s*([0-9.]+)/)
                if (vm) root.volume = Math.max(0, Math.min(1, parseFloat(vm[1])))
                root.muted = t.indexOf("MUTED") !== -1
                var bm = t.match(/b=(\d+):(\d+)/)
                if (bm && parseInt(bm[2]) > 0)
                    root.brightness = Math.max(0, Math.min(1, parseInt(bm[1]) / parseInt(bm[2])))
            }
        }
    }
    Process {
        id: weatherProc
        command: ["sh", "-c", "curl -s --max-time 8 'wttr.in/Lagos,Nigeria?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var j = JSON.parse(text)
                    var cur = j.current_condition[0]
                    root.weatherTemp = cur.temp_C + "°"
                    root.weatherFeel = cur.FeelsLikeC + "°"
                    root.weatherCond = cur.weatherDesc[0].value.trim()
                    root.weatherKind = root.condKind(root.weatherCond)
                    root.weatherHumidity = (cur.humidity || "--") + "%"
                    root.weatherWind = (cur.windspeedKmph || "--") + " km/h"
                    var area = j.nearest_area[0]
                    if (area) root.weatherLoc = area.areaName[0].value
                } catch (e) {}
            }
        }
    }

    NetRate { id: netRate }

    // ── window ───────────────────────────────────────────────────────────
    title: "Control Center"
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(980, 720)
    maximumSize: Qt.size(980, 720)
    color: "transparent"
    visible: root.open || closeAnim.running

    onOpenChanged: if (open) {
        weatherProc.running = true; volProbe.running = true
        activityFetcher.running = true
        root.buildWeek()
        Qt.callLater(function(){ card.forceActiveFocus() })
        openAnim.restart()
    } else closeAnim.restart()

    // ── small building blocks ────────────────────────────────────────────
    component Card: Rectangle {
        radius: 16
        color: root.colors.alpha(root.colors.surface, 0.45)
        border.width: 1
        border.color: root.colors.alpha(root.colors.outline, 0.10)
    }

    // 20-segment slider. Drag, click or scroll.
    component SegBar: Item {
        id: sb
        property real value: 0
        property int count: 20
        property color onColor
        property color offColor
        signal moved(real v)
        signal released()
        readonly property int lit: Math.round(value * count)
        height: 24
        Row {
            anchors.fill: parent
            spacing: 3
            Repeater {
                model: sb.count
                Rectangle {
                    width: (sb.width - (sb.count - 1) * 3) / sb.count
                    height: sb.height
                    radius: 3
                    color: index < sb.lit ? sb.onColor : sb.offColor
                    Behavior on color { ColorAnimation { duration: 100 } }
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function setFrom(x) { sb.moved(Math.max(0, Math.min(1, x / width))) }
            onPressed: function(mouse){ setFrom(mouse.x) }
            onPositionChanged: function(mouse){ if (pressed) setFrom(mouse.x) }
            onReleased: sb.released()
            onWheel: function(w){ sb.moved(Math.max(0, Math.min(1, sb.value + (w.angleDelta.y > 0 ? 0.05 : -0.05)))); sb.released() }
        }
    }

    component Glyph: Text {
        font.family: root.colors ? root.colors.fontSans : "FiraCode Nerd Font"
        font.pixelSize: 18
        verticalAlignment: Text.AlignVCenter
    }

    // ── layout ───────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.15)
        clip: true
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.34, 1.35, 0.64, 1, 1, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0.8, 0.2, 1, 1, 1] }
        }

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── HEADER ──
            Card {
                id: headerCard
                Layout.fillWidth: true
                Layout.minimumHeight: 68
                Layout.preferredHeight: 68
                Layout.maximumHeight: 68
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 26; anchors.rightMargin: 26
                    spacing: 24

                    Text {
                        text: root.clockText
                        color: colors.foreground
                        font.family: "Iceberg"; font.pixelSize: 34; font.weight: Font.Normal
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle { width: 1; height: 28; color: colors.alpha(colors.primary, 0.16) }
                    RowLayout {
                        spacing: 8
                        WeatherIcon {
                            width: 28; height: 28
                            kind: root.weatherKind
                            animate: root.open
                            tint: colors.tertiary
                            tintStrength: 0.5
                        }
                        Text { text: root.weatherTemp; color: colors.foreground; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { text: root.weatherCond + " · " + root.weatherLoc; color: colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 13 }
                    }
                    Item { Layout.fillWidth: true }
                    Repeater {
                        model: [
                            { g: "󰔏", l: "Feels", v: root.weatherFeel, c: colors.tertiary },
                            { g: "󰸊", l: "Humidity", v: root.weatherHumidity, c: colors.primary },
                            { g: "󰖝", l: "Wind", v: root.weatherWind, c: colors.primary }
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            spacing: 8
                            Glyph { text: modelData.g; color: modelData.c; font.pixelSize: 20 }
                            ColumnLayout {
                                spacing: 0
                                Text { text: modelData.l; color: colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 12 }
                                Text { text: modelData.v; color: colors.foreground; font.family: root.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }

            // ── MIDDLE ──
            RowLayout {
                id: midRow
                Layout.fillWidth: true
                Layout.minimumHeight: 328
                Layout.preferredHeight: 328
                Layout.maximumHeight: 328
                spacing: 14

                // Now playing — artist picture is the card background
                Card {
                    id: npCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        id: npBgLayer
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle { width: npBgLayer.width; height: npBgLayer.height; radius: 16 }
                        }
                        Image {
                            anchors.fill: parent
                            source: root.hasPlayer ? root.hiResArt(root.player.trackArtUrl) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            mipmap: true
                            sourceSize: Qt.size(640, 640)
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: colors.alpha(colors.background, 0.45) }
                                GradientStop { position: 0.4; color: colors.alpha(colors.background, 0.55) }
                                GradientStop { position: 1.0; color: colors.alpha(colors.background, 0.92) }
                            }
                        }
                    }

                    ColumnLayout {
                        id: npContent
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 0

                        Text { text: "NOW PLAYING"; color: colors.alpha(colors.foreground, 0.7); font.family: root.uiFont; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                        Text {
                            Layout.fillWidth: true; Layout.topMargin: 4
                            text: root.npTitle
                            color: colors.foreground
                            font.family: root.uiFont; font.pixelSize: 34; font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.hasPlayer ? root.npArtist : "No player"
                            color: colors.alpha(colors.foreground, 0.85)
                            font.family: root.uiFont; font.pixelSize: 16
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.topMargin: 16
                            spacing: 12
                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: prevMa.containsMouse ? colors.alpha(colors.background, 0.75) : colors.alpha(colors.background, 0.5)
                                border.width: 1; border.color: colors.alpha(colors.foreground, 0.28)
                                scale: prevMa.containsMouse ? 1.06 : 1
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Glyph { anchors.centerIn: parent; text: "󰒮"; color: colors.foreground; font.pixelSize: 17 }
                                MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled: true; onClicked: if (root.hasPlayer && root.player.canGoPrevious) root.player.previous() }
                            }
                            Rectangle {
                                width: 54; height: 54; radius: 27
                                color: colors.primary
                                opacity: playMa.containsMouse ? 0.92 : 1
                                scale: playMa.containsMouse ? 1.06 : 1
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Glyph { anchors.centerIn: parent; text: root.isPlaying ? "󰏤" : "󰐊"; color: colors.background; font.pixelSize: 22 }
                                MouseArea { id: playMa; anchors.fill: parent; hoverEnabled: true; onClicked: if (root.hasPlayer && root.player.canTogglePlaying) root.player.togglePlaying() }
                            }
                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: nextMa.containsMouse ? colors.alpha(colors.background, 0.75) : colors.alpha(colors.background, 0.5)
                                border.width: 1; border.color: colors.alpha(colors.foreground, 0.28)
                                scale: nextMa.containsMouse ? 1.06 : 1
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Glyph { anchors.centerIn: parent; text: "󰒭"; color: colors.foreground; font.pixelSize: 17 }
                                MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; onClicked: if (root.hasPlayer && root.player.canGoNext) root.player.next() }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // mirrored visualizer — lit up to the playhead, gradient primary -> tertiary
                        Item {
                            id: vizBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            Row {
                                id: vizRow
                                anchors.fill: parent
                                spacing: 3
                                Repeater {
                                    model: root.vizDraw
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property real f: index / (root.vizDraw - 1)
                                        width: (vizRow.width - (root.vizDraw - 1) * vizRow.spacing) / root.vizDraw
                                        height: Math.max(4, vizRow.height * root.vizLevel(index))
                                        radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: f < root.npPos ? root.mix(colors.primary, colors.tertiary, f) : colors.alpha(colors.foreground, 0.32)
                                        Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                                    }
                                }
                            }
                        }

                        // seek
                        Item {
                            id: seekBar
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.preferredHeight: 14
                            function seekTo(x) {
                                if (!root.hasPlayer || !root.player.length || !root.player.canSeek) return
                                root.player.position = Math.max(0, Math.min(1, x / width)) * root.player.length
                            }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: colors.alpha(colors.foreground, 0.25) }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * root.npPos; height: 4; radius: 2; color: colors.primary }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: function(mouse){ seekBar.seekTo(mouse.x) }
                                onPositionChanged: function(mouse){ if (pressed) seekBar.seekTo(mouse.x) }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Text { text: root.npCur; color: colors.alpha(colors.foreground, 0.85); font.family: root.uiFont; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                            Text { text: root.npTot; color: colors.alpha(colors.foreground, 0.85); font.family: root.uiFont; font.pixelSize: 12 }
                        }
                    }
                }

                // Side column
                ColumnLayout {
                    id: sideRail
                    Layout.preferredWidth: 300
                    Layout.maximumWidth: 300
                    Layout.minimumWidth: 300
                    Layout.fillHeight: true
                    spacing: 14

                    // Volume
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18; anchors.rightMargin: 18
                            spacing: 12
                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: colors.primary
                                Glyph { anchors.centerIn: parent; text: root.muted ? "󰝟" : "󰕾"; color: colors.background }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMute() }
                            }
                            SegBar {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                value: root.muted ? 0 : root.volume
                                onColor: colors.primary
                                offColor: colors.alpha(colors.foreground, 0.14)
                                onMoved: function(v){ root.dragVolume(v) }
                                onReleased: { root.setVolume(root.volume); root._volSent = root.volume }
                            }
                            Text {
                                Layout.preferredWidth: 42
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: root.muted ? "Muted" : Math.round(root.volume * 100)
                                color: colors.foreground
                                font.family: root.uiFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Brightness
                    Card {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18; anchors.rightMargin: 18
                            spacing: 12
                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: colors.primary
                                Glyph { anchors.centerIn: parent; text: "󰃠"; color: colors.background }
                            }
                            SegBar {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                value: root.brightness
                                onColor: colors.primary
                                offColor: colors.alpha(colors.foreground, 0.14)
                                onMoved: function(v){ root.dragBrightness(v) }
                                onReleased: { root.setBrightness(root.brightness); root._briSent = root.brightness }
                            }
                            Text {
                                Layout.preferredWidth: 42
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(root.brightness * 100)
                                color: colors.foreground
                                font.family: root.uiFont; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                        }
                    }

                    // Network
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Network"; color: colors.foreground; font.family: root.uiFont; font.pixelSize: 15; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Text { text: "Since boot · " + netRate.fmtTotal(netRate.totalRxMb + netRate.totalTxMb); color: colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 12 }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 8
                                color: colors.alpha(colors.surfaceVariant, 0.3)
                                Canvas {
                                    id: netGraph
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    Connections {
                                        target: netRate
                                        function onRxHistoryChanged() { netGraph.requestPaint() }
                                        function onTxHistoryChanged() { netGraph.requestPaint() }
                                    }
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        var W = width, H = height
                                        ctx.clearRect(0, 0, W, H)
                                        var rx = netRate.rxHistory, tx = netRate.txHistory
                                        if (rx.length < 2) return
                                        function curve(h, stroke, lw) {
                                            var maxV = 12
                                            for (var i = 0; i < rx.length; i++) maxV = Math.max(maxV, rx[i])
                                            var n = h.length, pts = []
                                            for (var i2 = 0; i2 < n; i2++) pts.push({ x: (i2 / (n - 1)) * W, y: H - 2 - (h[i2] / maxV) * (H - 8) })
                                            ctx.beginPath(); ctx.moveTo(pts[0].x, pts[0].y)
                                            for (var k = 1; k < pts.length; k++) {
                                                var cpx = (pts[k - 1].x + pts[k].x) / 2
                                                ctx.bezierCurveTo(cpx, pts[k - 1].y, cpx, pts[k].y, pts[k].x, pts[k].y)
                                            }
                                            ctx.strokeStyle = stroke; ctx.lineWidth = lw; ctx.lineJoin = "round"; ctx.stroke()
                                            return pts
                                        }
                                        if (tx.length >= 2) curve(tx, colors.tertiary, 1.6)
                                        var pts = curve(rx, colors.primary, 2)
                                        ctx.lineTo(pts[pts.length - 1].x, H); ctx.lineTo(0, H); ctx.closePath()
                                        var g = ctx.createLinearGradient(0, 0, 0, H)
                                        g.addColorStop(0, colors.alpha(colors.primary, 0.28))
                                        g.addColorStop(1, "transparent")
                                        ctx.fillStyle = g; ctx.fill()
                                        ctx.beginPath(); ctx.arc(pts[pts.length - 1].x - 1, pts[pts.length - 1].y, 3, 0, Math.PI * 2)
                                        ctx.fillStyle = colors.primary; ctx.fill()
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Glyph { text: "󰇚"; color: colors.primary; font.pixelSize: 16 }
                                Text { text: netRate.fmt(netRate.rxKbs); color: colors.foreground; font.family: root.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Glyph { text: "󰕒"; color: colors.tertiary; font.pixelSize: 16 }
                                Text { text: netRate.fmt(netRate.txKbs); color: colors.foreground; font.family: root.uiFont; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }

            // ── BOTTOM ──
            ColumnLayout {
                id: bottomColumn
                Layout.fillWidth: true
                Layout.minimumHeight: 260
                Layout.preferredHeight: 260
                Layout.maximumHeight: 260
                spacing: 14

                RowLayout {
                    id: weekRow
                    Layout.fillWidth: true
                    Layout.minimumHeight: 96
                    Layout.preferredHeight: 96
                    Layout.maximumHeight: 96
                    spacing: 14

                    // Week — square tiles
                    Card {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 22; anchors.rightMargin: 22
                            spacing: 26
                            ColumnLayout {
                                spacing: 0
                                Text { text: root.monthLabel; color: colors.foreground; font.family: root.uiFont; font.pixelSize: 16; font.weight: Font.Bold }
                                Text { text: root.weekLabel; color: colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 13 }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    spacing: Math.max(6, (width - 7 * 64) / 6)
                                    Repeater {
                                        model: root.weekDays
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: 64; height: 64; radius: 12
                                            color: modelData.today ? colors.primary : colors.alpha(colors.primary, 0.07)
                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 2
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.dow; color: modelData.today ? colors.background : colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 12 }
                                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.day; color: modelData.today ? colors.background : (modelData.wknd ? colors.alpha(colors.foreground, 0.55) : colors.foreground); font.family: root.uiFont; font.pixelSize: 20; font.weight: Font.DemiBold }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Pixel bot
                    Card {
                        Layout.preferredWidth: 210
                        Layout.maximumWidth: 210
                        Layout.minimumWidth: 210
                        Layout.fillHeight: true
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18; anchors.rightMargin: 18
                            spacing: 14
                            Rectangle {
                                width: 62; height: 62; radius: 12
                                color: colors.alpha(colors.background, 0.5)
                                clip: true
                                PixelBot {
                                    id: ccBot
                                    active: root.open
                                    registerIpc: false
                                    colors: root.colors
                                    pixelScale: 3
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                }
                            }
                            ColumnLayout {
                                spacing: 0
                                Text { text: "Pixel bot"; color: colors.foreground; font.family: root.uiFont; font.pixelSize: 15; font.weight: Font.Bold }
                                Text { text: ccBot.mood; color: ccBot.mood === "error" ? colors.error : colors.primary; font.family: root.uiFont; font.pixelSize: 13 }
                            }
                        }
                    }
                }

                // Screen time showcase
                Card {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        anchors.leftMargin: 22; anchors.rightMargin: 22
                        spacing: 28

                        ColumnLayout {
                            Layout.preferredWidth: 190
                            Layout.maximumWidth: 190
                            Layout.fillHeight: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6
                            Text { text: "SCREEN TIME TODAY"; color: colors.alpha(colors.foreground, 0.68); font.family: root.uiFont; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                            Text { text: root.usageToday > 0 ? root.fmtHM(root.usageToday) : "—"; color: colors.foreground; font.family: "Iceberg"; font.pixelSize: 40; font.weight: Font.Normal }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 4

                            Item {
                                id: weekChartBox
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 0
                                property int pad: 6
                                function chartX(i) {
                                    var n = Math.max(1, root.activityLast7.length - 1)
                                    return pad + i * ((width - pad * 2) / n)
                                }
                                function chartY(v) {
                                    return (height - 8) - (v / Math.max(1, root.weekMax)) * (height - 16)
                                }

                                Canvas {
                                    id: weekChart
                                    anchors.fill: parent
                                    Connections {
                                        target: root
                                        function onActivityLast7Changed() { weekChart.requestPaint() }
                                        function onChartHiChanged() { weekChart.requestPaint() }
                                    }
                                    onVisibleChanged: if (visible) requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var days = root.activityLast7
                                        if (days.length === 0) return
                                        var mx = Math.max(1, root.weekMax)
                                        var pad = 6
                                        function X(i) { return pad + i * ((width - pad * 2) / Math.max(1, days.length - 1)) }
                                        function Y(v) { return (height - 8) - (v / mx) * (height - 16) }
                                        var acc = colors.tertiary

                                        // Area fill under the smooth curve, exactly like ScreenTime.
                                        ctx.beginPath()
                                        ctx.moveTo(X(0), Y(days[0].secs))
                                        for (var i = 1; i < days.length; i++) {
                                            var cx = (X(i - 1) + X(i)) / 2
                                            ctx.bezierCurveTo(cx, Y(days[i - 1].secs), cx, Y(days[i].secs), X(i), Y(days[i].secs))
                                        }
                                        ctx.lineTo(X(days.length - 1), height)
                                        ctx.lineTo(X(0), height)
                                        ctx.closePath()
                                        ctx.fillStyle = colors.alpha(acc, 0.14)
                                        ctx.fill()

                                        // Average hairline.
                                        ctx.beginPath()
                                        ctx.moveTo(0, Y(root.avgDay))
                                        ctx.lineTo(width, Y(root.avgDay))
                                        ctx.strokeStyle = colors.alpha(colors.outline, 0.5)
                                        ctx.lineWidth = 1
                                        ctx.stroke()

                                        // The curve itself.
                                        ctx.beginPath()
                                        ctx.moveTo(X(0), Y(days[0].secs))
                                        for (var j = 1; j < days.length; j++) {
                                            var cx2 = (X(j - 1) + X(j)) / 2
                                            ctx.bezierCurveTo(cx2, Y(days[j - 1].secs), cx2, Y(days[j].secs), X(j), Y(days[j].secs))
                                        }
                                        ctx.strokeStyle = acc
                                        ctx.lineWidth = 2.5
                                        ctx.lineJoin = "round"
                                        ctx.lineCap = "round"
                                        ctx.stroke()

                                        // Hovered-day guide, or today when nothing is hovered.
                                        var hi = root.chartHi >= 0 && root.chartHi < days.length ? root.chartHi : days.length - 1
                                        ctx.beginPath()
                                        ctx.moveTo(X(hi), 0)
                                        ctx.lineTo(X(hi), height)
                                        ctx.strokeStyle = colors.alpha(colors.outline, root.chartHi >= 0 ? 0.35 : 0)
                                        ctx.lineWidth = 1
                                        ctx.stroke()

                                        var tx = X(hi), ty = Y(days[hi].secs)
                                        ctx.beginPath()
                                        ctx.arc(tx, ty, 9, 0, 2 * Math.PI)
                                        ctx.fillStyle = colors.alpha(acc, 0.2)
                                        ctx.fill()
                                        ctx.beginPath()
                                        ctx.arc(tx, ty, 4.5, 0, 2 * Math.PI)
                                        ctx.fillStyle = acc
                                        ctx.fill()
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onPositionChanged: function(m) {
                                        var n = Math.max(1, root.activityLast7.length - 1)
                                        var i = Math.round((m.x - weekChartBox.pad) / ((width - weekChartBox.pad * 2) / n))
                                        root.chartHi = Math.max(0, Math.min(n, i))
                                    }
                                    onExited: root.chartHi = -1
                                }

                                Rectangle {
                                    readonly property var hoveredDay: root.chartHi >= 0 && root.chartHi < root.activityLast7.length ? root.activityLast7[root.chartHi] : null
                                    visible: hoveredDay !== null
                                    width: 104; height: 40; radius: 8
                                    x: hoveredDay ? Math.min(Math.max(weekChartBox.chartX(root.chartHi) - 52, 2), Math.max(2, weekChartBox.width - 106)) : 2
                                    y: hoveredDay ? Math.max(2, Math.min(weekChartBox.chartY(hoveredDay.secs) - 44, weekChartBox.height - 42)) : 2
                                    color: colors.alpha(colors.surface, 0.96)
                                    border.width: 1; border.color: colors.alpha(colors.outline, 0.25)
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 0
                                        Text {
                                            text: { if (root.chartHi < 0 || root.chartHi >= root.activityLast7.length) return ""; var p = String(root.activityLast7[root.chartHi].display).split(" "); return (p[0] + " " + (p[2] || "")).trim() }
                                            color: colors.foreground
                                            font.family: root.uiFont; font.pixelSize: 11; font.weight: Font.Bold
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                        Text {
                                            text: { if (root.chartHi < 0 || root.chartHi >= root.activityLast7.length) return ""; return root.fmtHM(root.activityLast7[root.chartHi].secs) }
                                            color: colors.tertiary
                                            font.family: root.uiFont; font.pixelSize: 11
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Repeater {
                                    model: root.activityLast7
                                    Text {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: { var p = String(modelData.display).split(" "); return (p[0] + " " + (p[2] || "")).trim() }
                                        color: index === root.activityLast7.length - 1 ? colors.foreground : colors.alpha(colors.outline, 0.7)
                                        font.family: root.uiFont; font.pixelSize: 11
                                        font.weight: index === root.activityLast7.length - 1 ? Font.Bold : Font.Normal
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
