import QtQuick

// LockTheme — every visual token for the lock screen. The palette comes from
// the bar's live Matugen Colors object; the fallbacks keep the lock legible
// if it is ever previewed without the shell.
//
// Design: "Quiet Hours" — one translucent glass plate over the wallpaper,
// rounded and lit by a single hairline. Two columns split by a rule, a fixed
// footer row, and one loud element per region: the clock and the uptime.
QtObject {
    id: root

    property var palette: null

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // ── palette ──────────────────────────────────────────────────────────
    readonly property color background: root.palette ? root.palette.background : "#131313"
    readonly property color foreground: root.palette ? root.palette.foreground : "#e2e2e2"
    readonly property color primary: root.palette ? root.palette.primary : "#ffffff"
    readonly property color secondary: root.palette ? root.palette.secondary : "#c6c6c6"
    readonly property color tertiary: root.palette ? root.palette.tertiary : "#e2e2e2"
    readonly property color error: root.palette ? root.palette.error : "#ffb4ab"
    readonly property color success: root.palette ? root.palette.secondary : "#c6c6c6"
    readonly property color outline: root.palette ? root.palette.outline : "#969696"

    readonly property color muted: root.alpha(root.foreground, 0.62)
    readonly property color quiet: root.alpha(root.foreground, 0.38)

    // One line per failed attempt. Kept here so the copy follows the theme
    // rather than living in the input component.
    readonly property var wrongPasswordLines: [
        "Nice try, genius.",
        "Oh, you forgot.",
        "Bold guess. Wrong.",
        "Close. Not even.",
        "That's not it, champ.",
        "Your keyboard believes in you.",
        "Memory: 0. Confidence: 10.",
        "Even the dots are disappointed.",
        "Nope. Try the one you actually use.",
        "Almost. In another timeline."
    ]

    // Glass: enough background to read text, enough transparency to see the
    // wallpaper move through it. The sheen is the top-half light catch.
    readonly property color plate: root.alpha(root.background, 0.40)
    readonly property color plateBorder: root.alpha(root.outline, 0.30)
    readonly property color sheen: root.alpha(root.foreground, 0.07)
    readonly property color hairline: root.alpha(root.foreground, 0.14)
    readonly property color hairlineSoft: root.alpha(root.foreground, 0.10)
    readonly property color fieldLine: root.alpha(root.foreground, 0.32)
    readonly property color fieldLineFocus: root.alpha(root.primary, 0.85)
    readonly property color artBorder: root.alpha(root.foreground, 0.14)
    readonly property real backdropDim: 0.26

    // Compatibility aliases kept for old preview paths.
    readonly property color surface: root.plate
    readonly property color surfaceRaised: root.alpha(root.foreground, 0.06)
    readonly property color boxBackground: root.plate
    readonly property color boxBorder: root.plateBorder
    readonly property color panelBackground: "transparent"

    // ── type ─────────────────────────────────────────────────────────────
    readonly property string clockFamily: "Iceberg"
    readonly property string uiFamily: "FiraCode Nerd Font"
    readonly property int clockSize: 170
    readonly property real clockLineHeight: 0.74
    readonly property real clockTracking: -4
    readonly property int dateSize: 17
    readonly property int quoteSize: 13
    readonly property int headingSize: 11
    readonly property real headingTracking: 1.4
    readonly property int bodySize: 14
    readonly property int smallSize: 11
    readonly property int tinySize: 10
    readonly property int fieldSize: 17
    readonly property int uptimeValueSize: 102

    // ── layout ───────────────────────────────────────────────────────────
    readonly property int boxWidth: 1340
    readonly property int boxHeight: 930
    readonly property int boxRadius: 22
    readonly property int boxPadding: 56
    readonly property int bodyBottomGap: 26
    readonly property int bottomReserved: 136
    readonly property int leftWidth: 690
    readonly property int columnGap: 56
    readonly property int artSize: 60
    readonly property int artRadius: 12
    readonly property int musicHeight: 170
    readonly property int lyricsHeight: 56
    readonly property int lyricsRailWidth: 2
    readonly property int notificationsHeight: 170
    readonly property int bottomBlockGap: 28
    readonly property int passwordWidth: 580
    readonly property int passwordRowHeight: 52
    readonly property int passwordTopGap: 28
    readonly property int notificationRowHeight: 40
    readonly property int uptimeHeight: 220
    readonly property int statsHeight: 232
    readonly property int statsBottomGap: 48
    readonly property int meterHeight: 86
    readonly property int meterTopMargin: 18
    readonly property int meterGap: 20
    readonly property int meterHeaderHeight: 16
    readonly property int weatherHeight: 24

    // Kept because LockSurface derives its fit from the box.
    readonly property int gap: root.columnGap
    readonly property int sectionGap: 24
    readonly property int columnWidth: 480

    // ── motion ───────────────────────────────────────────────────────────
    // One entrance on lock, one exit on unlock, and the minute tick. No
    // idle animation, so the lock costs nothing while it sits there.
    readonly property int lockInMs: 620
    readonly property int lockOutMs: 420
    readonly property real lockInScale: 0.92
    readonly property real lockOutScale: 0.97
    readonly property real introShift: 32
    readonly property real outroShift: 24
    readonly property int refocusDelayMs: 80
    readonly property int minuteTickMs: 260

    readonly property string passwordIndicator: "echo"
}