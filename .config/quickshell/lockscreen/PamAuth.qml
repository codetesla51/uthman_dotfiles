import Quickshell
import Quickshell.Services.Pam
import QtQuick

// PamAuth — the only place that talks to PAM. PasswordField stays presentational
// and PamTest/LockScreen share this exact state machine.
QtObject {
    id: root

    property var config

    property string state: "idle"      // idle | checking | failed | error | success
    property int attempts: 0
    property string message: ""        // PAM's own text, shown verbatim

    signal succeeded()
    signal failed()

    property string _pendingPassword: ""
    property string _lastMessage: ""
    property bool _lastMessageIsError: false
    property string _lastPamError: ""
    readonly property bool _lastMessageIsPrompt: {
        var m = root._lastMessage.trim()
        if (m === "") return true
        return /^(password|passcode|login|username|verification code)\b[^:]*:?$/i.test(m)
    }

    function authenticate(password) {
        if (root.state === "checking" || !root.config) return
        console.log("[pamauth] authenticate called, length", password.length)
        if (root.pam.active) root.pam.abort()
        root._pendingPassword = password
        root._lastMessage = ""
        root._lastMessageIsError = false
        root._lastPamError = ""
        root.message = ""
        root.state = "checking"
        if (!root.pam.start()) {
            root.state = "error"
            root.message = "PAM could not start — check the config path"
        }
    }

    function reset() {
        if (root.pam.active) root.pam.abort()
        root.state = "idle"
        root.attempts = 0
        root.message = ""
        root._pendingPassword = ""
        root._lastMessage = ""
        root._lastMessageIsError = false
        root._lastPamError = ""
    }

    property PamContext pam: PamContext {
        config: root.config ? root.config.pamService : "quickshell-lock"
        configDirectory: root.config ? root.config.pamDirectory : ""

        // PAM asks for the password here. The user has already typed and
        // submitted it; hand it over exactly once.
        onResponseRequiredChanged: {
            if (pam.responseRequired) {
                var pw = root._pendingPassword
                root._pendingPassword = ""
                pam.respond(pw)
            }
        }

        // Capture every message now: onCompleted() aborts the conversation and
        // clears pam.message before Quickshell emits completed(), so reading
        // pam.message inside onCompleted would always be empty.
        onPamMessage: {
            if (pam.message !== "") {
                root._lastMessage = pam.message
                root._lastMessageIsError = pam.messageIsError
                if (pam.messageIsError) root.message = pam.message
            }
        }

        onError: function(err) {
            root._lastPamError = PamError.toString(err)
        }

        onCompleted: function(result) {
            if (result === PamResult.Success) {
                root.state = "success"
                root.attempts = 0
                root.message = ""
                root.succeeded()
                return
            }

            if (result === PamResult.Failed || result === PamResult.MaxTries) {
                root.attempts += 1
                root.state = "failed"
                if (root._lastMessage !== "" && !root._lastMessageIsPrompt) {
                    root.message = root._lastMessage
                } else if (result === PamResult.MaxTries) {
                    root.message = "Maximum number of tries exceeded"
                } else {
                    // PAM's own strerror(PAM_AUTH_ERR) text. pam_unix does not
                    // always emit a conversation message for a bad password.
                    root.message = "Authentication failure"
                }
                console.log("[pamauth] failed; pam message:", JSON.stringify(root._lastMessage),
                    "isError:", root._lastMessageIsError, "shown:", JSON.stringify(root.message))
                root.failed()
                return
            }

            root.state = "error"
            var text = root._lastPamError !== ""
                ? root._lastPamError : PamResult.toString(result)
            if (root._lastMessage !== "" && !root._lastMessageIsPrompt)
                text += " — " + root._lastMessage
            root.message = text
            root.failed()
        }
    }
}