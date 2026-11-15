import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// PamTest — a normal window, never a session lock. This is the "PAM on its own"
// step: it uses the exact same PamAuth + PasswordField as the real lock, but
// cannot lock the session. Test a wrong password first, then the real one.
FloatingWindow {
    id: win
    visible: true
    implicitWidth: 520
    implicitHeight: 360
    minimumSize: Qt.size(520, 360)
    maximumSize: Qt.size(520, 360)
    title: "PAM test (no session lock)"
    color: theme.background

    LockTheme { id: theme }
    LockConfig { id: config }

    PamAuth {
        id: auth
        config: config
        onSucceeded: resultText.text = "PAM success. The auth path works."
        onFailed: resultText.text = auth.state === "error"
            ? "PAM error — see the message above."
            : "PAM rejected that password. No lockout tally was touched."
    }

    IpcHandler {
        target: "pamtest"
        function testWrong(): void { auth.authenticate("quickshell-wrong-password") }
        function status(): string {
            return auth.state + "|attempts=" + auth.attempts + "|" + auth.message
        }
    }

    Rectangle {
        anchors.fill: parent
        color: theme.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 12

        Text {
            text: "PAM-only test"
            color: theme.foreground
            font.family: theme.uiFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }
        Text {
            text: "No session lock. Type a wrong password first, then your real one."
            color: theme.muted
            font.family: theme.uiFamily
            font.pixelSize: theme.smallSize
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: info.implicitHeight + 16
            radius: 8
            color: theme.surfaceRaised
            border.width: 1
            border.color: theme.outline
            ColumnLayout {
                id: info
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2
                Text {
                    text: "service: " + config.pamService
                    color: theme.secondary
                    font.family: theme.uiFamily
                    font.pixelSize: theme.smallSize
                }
                Text {
                    text: "dir: " + config.pamDirectory
                    color: theme.muted
                    font.family: theme.uiFamily
                    font.pixelSize: theme.smallSize
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }
            }
        }

        PasswordField {
            id: field
            Layout.fillWidth: true
            theme: theme
            state: auth.state === "checking" ? "checking"
                : auth.state === "failed" ? "failed"
                : auth.state === "error" ? "error"
                : auth.state === "success" ? "success" : "idle"
            attempts: auth.attempts
            message: auth.message
            onSubmitted: function(pw) { auth.authenticate(pw) }
        }

        Text {
            id: resultText
            Layout.fillWidth: true
            text: "Waiting for a password."
            color: auth.state === "success" ? theme.success
                : auth.state === "failed" || auth.state === "error" ? theme.error
                : theme.muted
            font.family: theme.uiFamily
            font.pixelSize: theme.smallSize
            wrapMode: Text.Wrap
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: 84
                implicitHeight: 30
                radius: 8
                color: closeMouse.containsMouse ? theme.surfaceRaised : theme.surface
                border.width: 1
                border.color: closeMouse.containsMouse ? theme.primary : theme.outline
                Text {
                    anchors.centerIn: parent
                    text: "Close"
                    color: theme.foreground
                    font.family: theme.uiFamily
                    font.pixelSize: theme.smallSize
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Qt.quit()
                }
            }
        }
    }
}