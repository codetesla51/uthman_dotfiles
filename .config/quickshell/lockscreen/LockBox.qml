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

    implicitWidth: root.theme ? root.theme.boxWidth : 1180
    implicitHeight: root.theme ? root.theme.boxHeight : 930
    radius: root.theme ? root.theme.boxRadius : 18
    color: root.theme ? root.theme.plate : "#85131313"
    border.width: 1
    border.color: root.theme ? root.theme.plateBorder : "#383838"
    Behavior on color { ColorAnimation { duration: 240 } }

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
        }

        DateQuote {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: clock.bottom
            anchors.topMargin: 34
            theme: root.theme
            config: root.config
        }
    }

    // ── right top: uptime, filling the same region ───────────────────────
    Uptime {
        x: root.rightX
        y: root.bodyY
        width: root.rightW
        height: root.theme ? root.theme.uptimeHeight : 220
        theme: root.theme
    }

    SystemStats {
        x: root.rightX
        y: root.sectionRuleY
            - (root.theme ? root.theme.statsBottomGap : 48)
            - (root.theme ? root.theme.statsHeight : 232)
        width: root.rightW
        height: root.theme ? root.theme.statsHeight : 232
        theme: root.theme
    }

    // ── the rules that make the two-row grid read as a grid ──────────────
    Rectangle {
        x: root.rightX - (root.theme ? root.theme.columnGap : 48) / 2
        y: root.bodyY
        width: 1
        height: root.bodyH
        color: root.theme ? root.theme.hairlineSoft : "#111111"
    }

    Rectangle {
        x: root.pad
        y: root.sectionRuleY
        width: root.width - root.pad * 2
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
    }

    Notifications {
        x: root.rightX
        y: root.bottomBlockY
        width: root.rightW
        height: root.bottomBlockH
        theme: root.theme
        items: root.notifications
    }

    // ── footer: one line, one input ──────────────────────────────────────
    Rectangle {
        x: root.pad
        y: root.bottomRuleY
        width: root.width - root.pad * 2
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
}