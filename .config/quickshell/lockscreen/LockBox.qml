import QtQuick
import "sources"

// LockBox — composition only. One glass plate over the blurred backdrop: a
// two-column body split by a hairline, a full-width rule above the bottom
// row, and one centered password line in the footer. The clock and the uptime
// are the loud elements; everything else stays quiet.
Rectangle {
    id: root

    property var theme
    property var config
    property string authState: "idle"
    property int authAttempts: 0
    property string authMessage: ""
    property var notifications: []
    property int autoUnlockIn: -1

    signal submitted(string password)
    signal introFinished()

    // 0 → 1 while the plate assembles. Every region takes its own slice of
    // this timeline, so the screen builds itself instead of fading in as one
    // flat card: clock, then date, then the right column, then the bottom
    // row, and the password last.
    property real reveal: 0
    readonly property int introMs: root.theme && root.theme.lockRevealMs > 0
        ? root.theme.lockRevealMs : 1150

    function phase(start, end) {
        var span = Math.max(0.0001, end - start)
        var t = (root.reveal - start) / span
        if (t <= 0) return 0
        if (t >= 1) return 1
        return t * t * (3 - 2 * t)
    }

    function drift(start, end, distance) {
        return (1 - root.phase(start, end)) * distance
    }

    implicitWidth: root.theme ? root.theme.boxWidth : 1180
    implicitHeight: root.theme ? root.theme.boxHeight : 930
    radius: root.theme ? root.theme.boxRadius : 18
    color: root.theme ? root.theme.plate : "#85131313"
    border.width: 1
    // The edge catches the light on arrival and settles to its resting
    // weight, which separates the plate from the wallpaper as it fades up.
    border.color: root.theme
        ? Qt.rgba(root.theme.plateBorder.r, root.theme.plateBorder.g,
                  root.theme.plateBorder.b,
                  Math.min(1, root.theme.plateBorder.a
                      + 0.22 * (1 - root.phase(0.0, 0.55))))
        : "#383838"

    // Top-half light catch — the difference between "dark card" and glass.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: root.theme ? root.theme.sheen : "#0efedad7"
            }
            GradientStop {
                position: 0.55
                color: root.theme ? root.theme.alpha(root.theme.foreground, 0.0)
                    : "#00fedad7"
            }
        }
    }

    // One soft light sweep crosses the glass while the plate is arriving.
    // It is inset from the rounded edge and clipped, so it never paints the
    // plate's square corners.
    Item {
        id: sweepClip
        anchors.fill: parent
        anchors.margins: root.radius
        clip: true

        Rectangle {
            id: sweep
            width: root.width * 0.46
            height: root.height * 1.7
            y: -root.height * 0.35
            x: -sweep.width * 1.4
            rotation: 12
            opacity: 0
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.47
                    color: root.theme
                        ? root.theme.alpha(root.theme.foreground, 0.11)
                        : "#1cffffff"
                }
                GradientStop {
                    position: 0.53
                    color: root.theme
                        ? root.theme.alpha(root.theme.foreground, 0.11)
                        : "#1cffffff"
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }
    }
    readonly property int pad: root.theme ? root.theme.boxPadding : 52
    readonly property int bodyY: root.pad
    readonly property int bottomRuleY: root.height - (root.theme ? root.theme.bottomReserved : 112)
    readonly property int bodyBottom: root.bottomRuleY - (root.theme ? root.theme.bodyBottomGap : 24)
    readonly property int bodyH: root.bodyBottom - root.bodyY
    readonly property int leftW: root.theme ? root.theme.leftWidth : 600
    readonly property int rightX: root.pad + root.leftW + (root.theme ? root.theme.columnGap : 48)
    readonly property int rightW: root.width - root.pad - root.rightX
    readonly property int bottomBlockH: root.theme ? root.theme.notificationsHeight : 156
    readonly property int bottomBlockY: root.bodyBottom - root.bottomBlockH
    readonly property int sectionRuleY: root.bottomBlockY
        - (root.theme ? root.theme.bottomBlockGap : 26)

    WeatherSource {
        id: weatherSource
        config: root.config
    }

    // ── header is gone: the clock and uptime start at the top edge ──────
    Weather {
        x: root.rightX
        y: root.bodyY - 4
        width: root.rightW
        theme: root.theme
        source: weatherSource
        opacity: root.phase(0.14, 0.54)
        transform: Translate { y: root.drift(0.14, 0.54, 18) }
    }

    // ── left top: clock, then the date and quote along its baseline ──────
    Item {
        id: leftCol
        x: root.pad
        y: root.bodyY
        width: root.leftW
        height: root.sectionRuleY - root.bodyY

        Clock {
            id: clock
            theme: root.theme
            opacity: root.phase(0.02, 0.44)
            transform: Translate { y: root.drift(0.02, 0.44, 26) }
        }

        DateQuote {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: clock.bottom
            anchors.topMargin: 34
            theme: root.theme
            config: root.config
            opacity: root.phase(0.10, 0.50)
            transform: Translate { y: root.drift(0.10, 0.50, 16) }
        }
    }

    // ── right top: uptime, filling the same region ───────────────────────
    Uptime {
        x: root.rightX
        y: root.bodyY
        width: root.rightW
        height: root.theme ? root.theme.uptimeHeight : 220
        theme: root.theme
        opacity: root.phase(0.18, 0.58)
        transform: Translate { y: root.drift(0.18, 0.58, 24) }
    }

    SystemStats {
        x: root.rightX
        y: root.sectionRuleY
            - (root.theme ? root.theme.statsBottomGap : 48)
            - (root.theme ? root.theme.statsHeight : 232)
        width: root.rightW
        height: root.theme ? root.theme.statsHeight : 232
        theme: root.theme
        opacity: root.phase(0.30, 0.72)
        transform: Translate { y: root.drift(0.30, 0.72, 22) }
    }

    // ── the rules that make the two-row grid read as a grid ──────────────
    Rectangle {
        x: root.rightX - (root.theme ? root.theme.columnGap : 48) / 2
        y: root.bodyY
        width: 1
        height: root.bodyH * root.phase(0.22, 0.60)
        color: root.theme ? root.theme.hairlineSoft : "#111111"
    }

    Rectangle {
        x: root.pad
        y: root.sectionRuleY
        width: (root.width - root.pad * 2) * root.phase(0.34, 0.70)
        height: 1
        color: root.theme ? root.theme.hairline : "#212121"
    }

    // ── bottom row: music left, recent notifications right ───────────────
    Music {
        x: root.pad
        y: root.bottomBlockY
        width: root.leftW
        height: root.bottomBlockH
        theme: root.theme
        config: root.config
        opacity: root.phase(0.38, 0.80)
        transform: Translate { y: root.drift(0.38, 0.80, 20) }
    }

    Notifications {
        x: root.rightX
        y: root.bottomBlockY
        width: root.rightW
        height: root.bottomBlockH
        theme: root.theme
        items: root.notifications
        opacity: root.phase(0.44, 0.86)
        transform: Translate { y: root.drift(0.44, 0.86, 20) }
    }

    // ── footer: one line, one input ──────────────────────────────────────
    Rectangle {
        x: root.pad
        y: root.bottomRuleY
        width: (root.width - root.pad * 2) * root.phase(0.50, 0.78)
        height: 1
        color: root.theme ? root.theme.hairline : "#212121"
    }

    PasswordField {
        id: password
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottomRuleY + (root.theme ? root.theme.passwordTopGap : 28)
        width: root.theme ? root.theme.passwordWidth : 580
        theme: root.theme
        state: root.authState
        attempts: root.authAttempts
        message: root.authMessage
        headline: root.authState === "error" ? "Authentication error" : ""
        onSubmitted: function (pw) { root.submitted(pw) }
        opacity: root.phase(0.56, 0.94)
        transform: Translate { y: root.drift(0.56, 0.94, 14) }
    }

    // Footer: the message sits in the empty space on the input's left,
    // vertically centred on the same row. No box, no glyph, no rule — just
    // the words. Status stays on the right.
    Item {
        id: footerMeta
        x: root.pad
        y: root.bottomRuleY + (root.theme ? root.theme.passwordTopGap : 28)
        width: root.width - root.pad * 2
        height: root.theme ? root.theme.passwordRowHeight : 52
        opacity: root.phase(0.60, 0.98)
        transform: Translate { y: root.drift(0.60, 0.98, 10) }

        Column {
            id: footerMessage
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, password.x - root.pad - 28)
            spacing: 4
            opacity: root.footerTitle !== "" ? 1.0 : 0.0
            visible: opacity > 0

            transform: Translate {
                id: footerLift
                y: root.footerTitle !== "" ? 0 : 5
                Behavior on y {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            Text {
                width: parent.width
                text: root.footerTitle
                color: root.footerColor
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.fieldSize - 1 : 16
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft

                Behavior on color {
                    ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
            }

            Text {
                width: parent.width
                visible: root.footerDetail !== ""
                text: root.footerDetail
                color: root.theme ? root.theme.muted : "#8c8c8c"
                font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                font.pixelSize: root.theme ? root.theme.tinySize + 1 : 11
                elide: Text.ElideRight
                maximumLineCount: 1
                horizontalAlignment: Text.AlignLeft
            }
        }

        Status {
            id: status
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            active: root.visible
        }
    }

    readonly property bool footerAlert: password.showAlert

    readonly property color footerColor: {
        if (root.footerAlert) return password.alertColor
        if (root.authState === "checking")
            return root.theme ? root.theme.muted : "#8c8c8c"
        if (root.theme) return root.theme.primary
        return "#ffffff"
    }

    readonly property string footerTitle: {
        if (root.footerAlert) return password.alertTitle
        if (root.authState === "checking") return "Logging in…"
        if (status.capsLock) return "Caps Lock is on"
        return ""
    }

    readonly property string footerDetail: {
        if (root.footerAlert) return password.alertDetail
        if (status.capsLock) return "Passwords are case-sensitive."
        return ""
    }

    function focusPassword() {
        password.focusInput()
    }

    // The cascade driver. Linear on purpose: each region maps its own slice
    // of `reveal` through `phase()`, so the easing lives with the region and
    // the sections overlap instead of firing one after another.
    NumberAnimation {
        id: revealAnim
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: root.introMs
        easing.type: Easing.Linear
        onFinished: root.introFinished()
    }

    // One crossing of light, timed to pass over the clock and land on the
    // footer just as the password appears.
    // The sweep is derived from the same reveal clock as the content, so
    // shortening or lengthening the intro can never leave the light pass
    // arriving after the password has already landed.
    SequentialAnimation {
        id: sweepAnim
        PauseAnimation { duration: Math.round(root.introMs * 0.10) }
        ParallelAnimation {
            NumberAnimation {
                target: sweep
                property: "x"
                from: -sweep.width * 1.4
                to: root.width + sweep.width * 0.4
                duration: Math.round(root.introMs * 0.84)
                easing.type: Easing.Bezier
                easing.bezierCurve: [0.4, 0, 0.25, 1]
            }
            SequentialAnimation {
                NumberAnimation {
                    target: sweep
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Math.round(root.introMs * 0.16)
                    easing.type: Easing.OutCubic
                }
                PauseAnimation { duration: Math.round(root.introMs * 0.44) }
                NumberAnimation {
                    target: sweep
                    property: "opacity"
                    to: 0
                    duration: Math.round(root.introMs * 0.20)
                    easing.type: Easing.InCubic
                }
            }
        }
    }

    Component.onCompleted: {
        revealAnim.start()
        sweepAnim.start()
    }
}