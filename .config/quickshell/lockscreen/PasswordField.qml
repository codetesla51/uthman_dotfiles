import QtQuick
import QtQuick.Controls

// PasswordField — the footer's centered input. Typed characters turn into a
// row of little shapes (pac-man, ghosts, polygons, stars) instead of the usual
// dots; nothing in the field itself is an icon. One faded hairline and a soft
// centre glow carry the line. The footer owns the message beside the field;
// this component only reports its state and never draws a box around it.
Item {
    id: root

    property var theme
    property string state: "idle"      // idle | checking | failed | error | success
    property int attempts: 0
    property string message: ""        // PAM's own error text, passed through
    property string headline: ""

    signal submitted(string password)
    signal lengthChanged(int length)

    readonly property bool busy: root.state === "checking"
    readonly property bool bad: root.state === "failed" || root.state === "error"
    readonly property bool done: root.state === "success"
    readonly property int enteredLength: input.text.length
    readonly property alias text: input.text

    readonly property int rowHeight: root.theme ? root.theme.passwordRowHeight : 52

    // A password can be arbitrarily long; the shape row is clipped to the
    // field and right-aligns once it overflows, so the newest shapes stay
    // visible and the input never grows. 400 is only a sanity cap for
    // pathological pastes.
    readonly property int shownShapes: Math.min(input.text.length, 400)
    readonly property int firstVisible: input.text.length - root.shownShapes

    // One shape per typed character; the font decides the look.
    // pac-man, space invader, ghost, hexagon, octagon, triangle,
    // diamond, pentagon, rhombus, flower, snowflake, cube, circle, square,
    // star, heart, bolt, shapes.
    readonly property var passwordGlyphs: [
        "󰮯", "󰯉", "󱙝", "󰋘", "󰏃", "󰔶",
        "󰮊", "󰜁", "󰜋", "󰉊", "󰜗", "󰆧",
        "", "", "", "", "", ""
    ]

    readonly property color alertColor: root.theme
        ? (root.bad ? root.theme.error : root.theme.success)
        : "#ffffff"

    // One line per attempt, cycling through the list in LockTheme. The seed
    // offsets the list per session so repeated locks don't always open with
    // the same joke.
    readonly property int messageSeed: Math.floor(Math.random() * 1000)
    readonly property string funny: {
        var lines = root.theme ? root.theme.wrongPasswordLines : null
        if (!lines || lines.length === 0) return "Wrong password."
        return lines[(root.messageSeed + Math.max(0, root.attempts - 1))
            % lines.length]
    }

    readonly property string alertTitle: {
        if (root.done) return "Unlocked"
        if (root.state === "failed") return root.funny
        if (root.state === "error")
            return root.headline !== "" ? root.headline : "Authentication error"
        return ""
    }

    readonly property string alertDetail: root.state === "error" ? root.message : ""
    readonly property bool showAlert: root.bad || root.done

    readonly property color accent: {
        if (!root.theme) return "#ffffff"
        if (root.bad) return root.theme.error
        if (root.done) return root.theme.success
        if (root.busy) return root.theme.secondary
        if (input.activeFocus) return root.theme.primary
        return root.theme.fieldLine
    }

    implicitWidth: root.theme ? root.theme.passwordWidth : 580
    implicitHeight: root.rowHeight

    // Mix the character code with the position so even a repeated letter
    // lands on a different shape, and every keystroke feels alive.
    function shapeAt(i) {
        var text = input.text
        if (!text || i < 0 || i >= text.length) return ""
        var n = root.passwordGlyphs.length
        if (n === 0) return ""
        return root.passwordGlyphs[(text.charCodeAt(i) * 7 + i * 5) % n]
    }

    function clear() { input.text = "" }
    function focusInput() { input.forceActiveFocus() }

    function submit() {
        if (root.busy || input.text.length === 0) return
        var pw = input.text
        input.text = ""
        root.submitted(pw)
    }

    onStateChanged: {
        if (root.state === "failed" || root.state === "error")
            shakeAnim.restart()
        if (root.state !== "checking") Qt.callLater(function() {
            if (root) root.focusInput()
        })
    }

    onAttemptsChanged: if (root.bad) shakeAnim.restart()

    Item {
        id: inputRow
        anchors.fill: parent
        transform: Translate { id: shake }

        // The whole rule is a click target; the field keeps its own
        // selection handling above this.
        MouseArea {
            anchors.fill: parent
            enabled: !root.busy
            onClicked: input.forceActiveFocus()
        }

        // NoEcho: the real password stays in the field (selection and submit
        // keep working), while the shapes below do the drawing.
        TextField {
            id: input
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: 40
            padding: 0
            verticalAlignment: TextInput.AlignVCenter
            horizontalAlignment: TextInput.AlignHCenter
            echoMode: TextInput.NoEcho
            placeholderText: ""
            color: "transparent"
            selectionColor: root.theme
                ? root.theme.alpha(root.theme.primary, 0.18) : "#2e2e2e"
            selectedTextColor: root.theme ? root.theme.primary : "#ffffff"
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.fieldSize : 17
            background: null
            selectByMouse: true
            enabled: !root.busy
            onTextChanged: root.lengthChanged(text.length)
            onAccepted: root.submit()

            // The native caret would sit at the end of invisible text. The
            // lit line is the focus cue instead.
            cursorDelegate: Item { width: 0; height: 0 }
        }

        // Custom placeholder so it eases away on the first keystroke instead
        // of vanishing; the field's own placeholder is disabled above.
        Text {
            id: placeholder
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: 40
            text: root.bad ? "Try again" : "Enter password"
            color: root.bad && root.theme
                ? root.theme.alpha(root.theme.error, 0.58)
                : (root.theme ? root.theme.quiet : "#565656")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
            font.pixelSize: root.theme ? root.theme.fieldSize : 17
            visible: opacity > 0
            opacity: input.text.length === 0 && !root.busy ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        // The typed characters, one shape each. The row is measured inside a
        // clipped viewport: centred while it fits, pinned to the right edge
        // once it overflows, so it can never widen the field. Every new shape
        // eases up into place instead of popping.
        Item {
            id: shapeViewport
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: root.rowHeight
            clip: true

            Row {
                id: shapes
                anchors.verticalCenter: parent.verticalCenter
                x: shapes.width <= shapeViewport.width
                    ? (shapeViewport.width - shapes.width) / 2
                    : shapeViewport.width - shapes.width
                spacing: 5
                enabled: false
                opacity: root.busy ? 0.45 : 1.0

                Behavior on x {
                    NumberAnimation { duration: 300; easing.type: Easing.OutQuint }
                }

                Repeater {
                    model: root.shownShapes

                    delegate: Text {
                        id: shape
                        text: root.shapeAt(root.firstVisible + index)
                        color: root.bad
                            ? (root.theme ? root.theme.error : "#ffb4ab")
                            : (root.done
                                ? (root.theme ? root.theme.success : "#c6c6c6")
                                : (root.theme ? root.theme.foreground : "#e2e2e2"))
                        font.family: root.theme ? root.theme.uiFamily : "FiraCode Nerd Font"
                        font.pixelSize: 19
                        font.weight: Font.Medium
                        opacity: 0.0
                        scale: 0.72
                        transform: Translate { id: rise; y: 4 }

                        Behavior on color {
                            ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        ParallelAnimation {
                            running: true
                            NumberAnimation {
                                target: shape
                                property: "opacity"
                                from: 0.0
                                to: 1.0
                                duration: 260
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: shape
                                property: "scale"
                                from: 0.72
                                to: 1.0
                                duration: 340
                                easing.type: Easing.OutCubic
                            }
                            NumberAnimation {
                                target: rise
                                property: "y"
                                from: 4
                                to: 0
                                duration: 340
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        // The line: faint at the ends, stronger under the field, so it
        // reads as one deliberate rule rather than a box edge.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.theme
                        ? root.theme.alpha(root.theme.fieldLine, 0.0)
                        : "transparent"
                }
                GradientStop {
                    position: 0.14
                    color: root.theme ? root.theme.fieldLine : "#4a4a4a"
                }
                GradientStop {
                    position: 0.86
                    color: root.theme ? root.theme.fieldLine : "#4a4a4a"
                }
                GradientStop {
                    position: 1.0
                    color: root.theme
                        ? root.theme.alpha(root.theme.fieldLine, 0.0)
                        : "transparent"
                }
            }
        }

        // The lit centre segment. It carries focus and error colour without
        // turning the field into a filled control; it blooms outward as it
        // lights up instead of appearing at full width.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width * (input.activeFocus || root.bad || root.done
                || root.busy ? 0.46 : 0.32)
            height: 1.5
            color: root.accent
            opacity: input.activeFocus || root.bad || root.done || root.busy
                ? 1.0 : 0.0
            Behavior on width {
                NumberAnimation { duration: 320; easing.type: Easing.OutQuint }
            }
            Behavior on opacity {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on color {
                ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
        }

        // Soft spill under the rule. A wash, not a chip.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            width: parent.width * (input.activeFocus || root.bad || root.done
                ? 0.68 : 0.56)
            height: 8
            radius: 4
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.theme
                        ? root.theme.alpha(root.accent, 0.0) : "transparent"
                }
                GradientStop {
                    position: 0.5
                    color: root.theme
                        ? root.theme.alpha(root.accent, root.bad ? 0.11 : 0.08)
                        : "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: root.theme
                        ? root.theme.alpha(root.accent, 0.0) : "transparent"
                }
            }
            opacity: input.activeFocus || root.bad || root.done ? 1.0 : 0.0
            Behavior on width {
                NumberAnimation { duration: 320; easing.type: Easing.OutQuint }
            }
            Behavior on opacity {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
            }
        }
    }

    // A short, damped wobble — enough to register, never a violent shake.
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shake; property: "x"; to: -4; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: shake; property: "x"; to: 4; duration: 90; easing.type: Easing.InOutSine }
        NumberAnimation { target: shake; property: "x"; to: -2.5; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: shake; property: "x"; to: 2.5; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: Qt.callLater(root.focusInput)
}
