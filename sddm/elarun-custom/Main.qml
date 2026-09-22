import QtQuick 2.0

// elarun-custom — password-only, logo top.
// Colors from Palette.qml (matugen). Display font: Iceland.
// Icons: FiraCode Nerd Font (Iceland has no icon glyphs).
Rectangle {
    id: root
    anchors.fill: parent
    color: pal.background

    Palette { id: pal }

    property int sessionIndex: sessionModel.lastIndex
    property string failMsg: ""
    property bool loggingIn: false
    property string loginUser: userModel.lastUser !== "" ? userModel.lastUser : "uthman"
    property color field: Qt.lighter(pal.background, 1.35)
    property color edge: Qt.lighter(pal.background, 2.1)
    property color dim: Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.55)
    property color faint: Qt.rgba(pal.text.r, pal.text.g, pal.text.b, 0.35)

    function doLogin() {
        if (root.loggingIn)
            return
        if (pwField.text === "") {
            failMsg = "Enter your password"
            pwField.focus = true
            return
        }
        // sessionModel loads async — clamp to a valid index at click time
        // so a correct password can't hang on a stale index.
        if (sessionIndex < 0 || sessionIndex >= sessionModel.count)
            sessionIndex = sessionModel.lastIndex
        failMsg = ""
        loggingIn = true
        sddm.login(root.loginUser, pwField.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            loggingIn = false
            failMsg = "Wrong password, try again"
            pwField.text = ""
            pwField.focus = true
        }
        function onLoginSucceeded() {
            // keep PLEASE WAIT + spinner until the greeter quits
            loggingIn = true
        }
    }

    // ── login form ───────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        spacing: 14

        // logo
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/logo-white.png"
            width: 260
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // welcome
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Welcome, " + root.loginUser
            color: pal.text
            font.family: "Iceland"
            font.pixelSize: 34
        }

        // password
        Rectangle {
            id: pwBox
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 56
            radius: 14
            color: root.field
            border.width: 1
            border.color: root.failMsg !== "" ? pal.error : (pwField.activeFocus ? pal.primary : root.edge)

            Text {
                id: lockIcon
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: pwField.activeFocus ? pal.primary : root.dim
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 17
            }
            TextInput {
                id: pwField
                anchors.left: lockIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                color: pal.text
                selectionColor: pal.primary
                selectedTextColor: pal.background
                // NOTE: bullets render in FiraCode, not Iceland — Iceland has
                // no bullet glyph, so Qt fell back to another font whose dots
                // looked oversized next to the rest of the theme.
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 18
                echoMode: TextInput.Password
                passwordCharacter: "•"
                readOnly: root.loggingIn
                focus: true
                Keys.onPressed: {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.doLogin()
                        event.accepted = true
                    }
                }
            }
            Text {
                anchors.left: pwField.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Password"
                color: root.faint
                font.family: "Iceland"
                font.pixelSize: 20
                visible: pwField.text === ""
            }
        }

        // login button
        Rectangle {
            id: loginBtn
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 56
            radius: 28
            color: loginMouse.containsMouse ? Qt.lighter(pal.primary, 1.08) : pal.primary
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: root.loggingIn ? "PLEASE WAIT" : "LOG IN"
                color: root.loggingIn ? root.dim : pal.background
                font.family: "Iceland"
                font.pixelSize: 20
                font.weight: Font.Bold
                font.letterSpacing: 4
            }
            MouseArea {
                id: loginMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !root.loggingIn
                onClicked: root.doLogin()
            }
        }

        // status line (reserved space so nothing jumps): error or logging-in
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 28
            Text {
                anchors.centerIn: parent
                text: root.failMsg
                color: pal.error
                font.family: "Iceland"
                font.pixelSize: 16
                visible: root.failMsg !== "" && !root.loggingIn
            }
            Row {
                anchors.centerIn: parent
                spacing: 8
                visible: root.loggingIn
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: pal.primary
                        opacity: 0.3
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: root.loggingIn
                            PauseAnimation { duration: index * 180 }
                            NumberAnimation { to: 1; duration: 300 }
                            NumberAnimation { to: 0.3; duration: 300 }
                            PauseAnimation { duration: (2 - index) * 180 }
                        }
                    }
                }
            }
        }
    }

    // ── bottom bar: sessions left, power right ───────────────
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 76
        color: "transparent"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "SESSION"
                color: root.faint
                font.family: "Iceland"
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 2
            }
            Repeater {
                model: sessionModel
                delegate: Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: sessLabel.implicitWidth + 28
                    height: 34
                    radius: 17
                    color: index === root.sessionIndex ? Qt.rgba(pal.primary.r, pal.primary.g, pal.primary.b, 0.2) : "transparent"
                    border.width: 1
                    border.color: index === root.sessionIndex ? pal.primary : root.edge
                    Text {
                        id: sessLabel
                        anchors.centerIn: parent
                        text: model.name
                        color: index === root.sessionIndex ? pal.primary : root.dim
                        font.family: "Iceland"
                        font.pixelSize: 16
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.sessionIndex = index
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 28
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: suspMouse.containsMouse ? root.field : "transparent"
                visible: sddm.canSuspend
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: root.dim
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 18
                }
                MouseArea {
                    id: suspMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sddm.suspend()
                }
            }
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: rebMouse.containsMouse ? root.field : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: root.dim
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 18
                }
                MouseArea {
                    id: rebMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sddm.reboot()
                }
            }
            Rectangle {
                width: 40
                height: 40
                radius: 20
                color: powMouse.containsMouse ? root.field : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: root.dim
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 18
                }
                MouseArea {
                    id: powMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sddm.powerOff()
                }
            }
        }
    }
}
