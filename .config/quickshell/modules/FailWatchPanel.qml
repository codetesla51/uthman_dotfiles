import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// FailWatch panel — silent failures the resource watcher can't see.
// Reads ~/.local/share/failwatch/live.json written by failwatch.service.
// Every row carries its log id: failed units show `journalctl -u <name>`,
// journal rows show `#<id>` + copyable `--after-cursor` command for full logs.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    property var failed: []
    property int failedCount: 0
    property var errors: []
    property int errors24h: 0
    property string daemonState: "loading"
    property string daemonErr: ""
    property string pkgMsg: ""
    property bool pkgBusy: false
    property bool liveBusy: false
    // which row is opening a terminal — per-row key so only the clicked
    // log button shows loading, the rest stay usable
    property string openingKey: ""
    Timer { id: openingClear; interval: 2500; onTriggered: root.openingKey = "" }
    property var liveLines: []
    property bool tailBusy: false
    function fixHint(name) {
        var n = String(name || "")
        if (n.indexOf("portal-gtk") !== -1)
            return { why: "The GNOME portal has nothing to do on Hyprland, so it exits.", fix: "systemctl --user mask xdg-desktop-portal-gtk.service" }
        if (n.indexOf("blueman") !== -1)
            return { why: "Bluetooth tray applet crashed at login.", fix: "systemctl --user disable app-blueman@autostart.service" }
        return { why: "", fix: "" }
    }
    function pollTail() {
        if (root.tailBusy) return
        root.tailBusy = true
        tailProc.command = ["journalctl", "-n", "12", "-p", "warning", "--output=short", "--no-pager"]
        tailProc.running = true
    }

    title: "FailWatch"
    implicitWidth: 660
    implicitHeight: 620
    minimumSize: Qt.size(560, 480)
    maximumSize: Qt.size(760, 680)
    color: "transparent"
    visible: root.open || closeAnim.running

    // NOTE: no IpcHandler here — Bar.qml owns target "failwatch" and lazy-loads this.

    onOpenChanged: { if (open) openAnim.restart(); else closeAnim.restart() }

    function pollLive() {
        if (root.liveBusy) return
        root.liveBusy = true
        var home = Quickshell.env("HOME")
        liveProc.command = ["cat", home + "/.local/share/failwatch/live.json"]
        liveProc.running = true
    }
    Process {
        id: liveProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.liveBusy = false
                if (text.indexOf("{") === 0) {
                    try {
                        var d = JSON.parse(text)
                        root.failed = d.failed || []
                        root.failedCount = d.failed_count || 0
                        root.errors = d.errors || []
                        root.errors24h = d.errors_24h || 0
                        root.daemonState = "on"
                        root.daemonErr = ""
                    } catch (e) {
                        root.daemonState = "error"
                        root.daemonErr = "live.json parse failed"
                    }
                } else {
                    root.daemonState = "error"
                    root.daemonErr = "daemon not running — systemctl --user start failwatch"
                }
            }
        }
    }
    Timer {
        interval: 5000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollLive()
    }
    Process {
        id: clearProc
        onExited: function (code) {
            if (code === 0) { root.pkgMsg = ""; root.pollLive() }
            else root.pkgMsg = "Clear failed"
        }
    }
    Process {
        id: tailProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.tailBusy = false
                var lines = String(text).split("\n")
                var keep = []
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i].trim()
                    if (ln !== "") keep.push(ln)
                }
                root.liveLines = keep.slice(-30)
            }
        }
    }
    Timer {
        interval: 5000
        running: root.open
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollTail()
    }

    function shQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function copyCmd(cmd) {
        Quickshell.execDetached(["sh", "-c", "printf %s " + root.shQuote(cmd) + " | (wl-copy 2>/dev/null || xclip -selection clipboard 2>/dev/null) && notify-send -u low -a 'FailWatch' 'Copied' " + root.shQuote(cmd)])
    }
    function openLog(key, cmd) {
        if (root.openingKey !== "") return
        root.openingKey = key
        openingClear.restart()
        Quickshell.execDetached(["sh", "-c", "uwsm-app -- kitty -e sh -c " + root.shQuote(cmd + "; echo '--- press any key ---'; read -n1") + " &"])
    }
    function unitLogCmd(name) { return "journalctl -u " + name + " -b --no-pager | tail -n 100" }
    function cursorCmd(cursor) { return "journalctl --after-cursor=" + root.shQuote(cursor) + " --no-pager" }

    function clearOld() {
        var db = Quickshell.env("HOME") + "/.local/share/failwatch/events.db"
        clearProc.command = ["python3", "-c", "import sqlite3,datetime,sys;db=sqlite3.connect(sys.argv[1]);cut=(datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(hours=24)).isoformat();db.execute('DELETE FROM events WHERE ts<?',(cut,));db.commit()", db]
        clearProc.running = true
    }
    function kindColor(kind) {
        if (kind === "oom" || kind === "oops" || kind === "failed-unit" || kind === "unit-fail") return colors.error
        if (kind === "segfault") return colors.primary
        return colors.secondary
    }

    function runPkgCheck() {
        if (root.pkgBusy) return
        root.pkgBusy = true
        root.pkgMsg = "verifying… (pacman -Qkk is slow)"
        pkgProc.command = ["sh", "-c", "pacman -Qkk 2>&1 | grep -v '0 altered' | head -n 30; echo \"EXIT:$?\""]
        pkgProc.running = true
    }
    Process {
        id: pkgProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.pkgBusy = false
                var t = text.trim()
                if (t === "" || t.indexOf("EXIT:") === 0) root.pkgMsg = "all files intact"
                else root.pkgMsg = t.split("\n").slice(0, 3).join(" · ").slice(0, 160)
            }
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.surface, 0.52)
        border.width: 1
        border.color: root.failedCount > 0 ? colors.alpha(colors.error, 0.35) : colors.alpha(colors.outline, 0.15)
        // bezier pair — open pops with overshoot bounce, close hurries out
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.94; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }
        focus: root.open
        Keys.onEscapePressed: root.open = false

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 13
                    color: colors.alpha(colors.error, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.error, 0.35)
                    Text { anchors.centerIn: parent; text: "!"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.ExtraBold }
                    Layout.alignment: Qt.AlignVCenter
                }
                Text { text: "FAILWATCH"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 12; font.weight: Font.ExtraBold; font.letterSpacing: 1.3; Layout.alignment: Qt.AlignVCenter }
                Rectangle {
                    visible: root.failedCount > 0
                    Layout.preferredWidth: failTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.error, 0.14)
                    border.width: 1; border.color: colors.alpha(colors.error, 0.4)
                    Text { id: failTxt; anchors.centerIn: parent; text: root.failedCount + " failed"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                    Layout.alignment: Qt.AlignVCenter
                }
                Rectangle {
                    visible: root.errors24h > 0
                    Layout.preferredWidth: errTxt.implicitWidth + 16; Layout.preferredHeight: 20; radius: 10
                    color: colors.alpha(colors.primary, 0.12)
                    border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                    Text { id: errTxt; anchors.centerIn: parent; text: root.errors24h + " errors/24h"; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold }
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
            }

            // daemon status — no dot: state lives in the border tint + text,
            // a separate colored dot duplicated the pill and added noise
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 10
                color: colors.alpha(colors.surface, 0.45)
                border.width: 1
                border.color: root.daemonState === "error" || root.failedCount > 0 ? colors.alpha(colors.error, 0.3) : colors.alpha(colors.outline, 0.12)
                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: Text.AlignVCenter
                    text: root.daemonState === "error" ? root.daemonErr : root.failedCount === 0 && root.errors24h === 0 ? "watching — units ok, no journal errors in 24h" : "watching — systemctl --failed + journalctl -p warning"
                    color: root.daemonState === "error" || root.failedCount > 0 ? colors.error : colors.alpha(colors.outline, 0.65)
                    font.family: colors.fontSans; font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }

            // HEIGHT BUDGET 620: margins 28 + header 30 + daemon 30 + failedcap 14
            //   + failedlist (0 when clean) + jcap 14 + errlist (fill, min 80)
            //   + console 104 + pkg 26 + 7x8 gaps. FOCAL: diagnosis cards.
            // failed units — diagnosis cards: what, why, fix
            Text { visible: root.failed.length > 0; text: "NEEDS YOU (" + root.failedCount + ")"; color: colors.error; font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.5 }
            ListView {
                id: failList
                visible: root.failed.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(2 * 124, Math.max(120, root.failed.length * 124))
                clip: true
                model: root.failed
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: failList.width
                    height: 116
                    radius: 12
                    color: colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.error, 0.3)
                    Rectangle { width: 3; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 12; anchors.bottomMargin: 12; radius: 1.5; color: colors.error }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 10
                        anchors.topMargin: 8; anchors.bottomMargin: 8
                        spacing: 3
                        Text { text: root.fixHint(modelData.name).why !== '' ? modelData.name.split('.')[0] + ' keeps failing' : modelData.name; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 13; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: root.fixHint(modelData.name).why !== '' ? root.fixHint(modelData.name).why : (modelData.scope || '') + ' ' + (modelData.active || '') + '/' + (modelData.sub || ''); color: colors.alpha(colors.outline, 0.7); font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: root.fixHint(modelData.name).fix !== '' ? root.fixHint(modelData.name).fix : root.unitLogCmd(modelData.name); color: colors.primary; font.family: colors.fontSans; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                            Rectangle {
                                width: 56; height: 24; radius: 8
                                color: colors.primary
                                Text { anchors.centerIn: parent; text: 'copy'; color: colors.background; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: { var h = root.fixHint(modelData.name); root.copyCmd(h.fix !== '' ? h.fix : root.unitLogCmd(modelData.name)) } }
                            }
                            Rectangle {
                                width: 52; height: 24; radius: 8
                                color: logMa.containsMouse ? colors.alpha(colors.primary, 0.25) : colors.alpha(colors.primary, 0.1)
                                border.width: 1; border.color: colors.alpha(colors.primary, 0.35)
                                Text { anchors.centerIn: parent; text: root.openingKey === 'u:' + modelData.name ? '…' : 'logs'; color: colors.primary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                                MouseArea { id: logMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.openLog('u:' + modelData.name, root.unitLogCmd(modelData.name)) }
                            }
                        }
                    }
                }
            }

            // all clear — one calm line when both lists are empty
            Text {
                visible: root.failed.length === 0 && root.errors.length === 0 && root.daemonState === 'on'
                text: "Healthy — 0 failed units, journal quiet. Console below is the proof."
                color: colors.alpha(colors.primary, 0.85); font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold
            }
            // journal errors
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "JOURNAL ERRORS — OOM · SEGFAULT · OOPS (" + root.errors.length + " kept)"; color: colors.alpha(colors.outline, 0.6); font.family: colors.fontSans; font.pixelSize: 8; font.weight: Font.Bold; font.letterSpacing: 1.5; Layout.fillWidth: true }
                Rectangle {
                    visible: root.errors.length > 0
                    width: 76; height: 24; radius: 9
                    color: clrMa.containsMouse ? colors.alpha(colors.secondary, 0.25) : colors.alpha(colors.surface, 0.4)
                    border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                    Text { anchors.centerIn: parent; text: "clear old"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.clearOld() }
                }
            }
            ListView {
                id: errList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.errors
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: errList.width
                    height: 66
                    radius: 12
                    color: ema.containsMouse ? colors.alpha(colors.primary, 0.07) : index % 2 === 0 ? colors.alpha(colors.surface, 0.35) : "transparent"
                    border.width: 1
                    border.color: ema.containsMouse ? colors.alpha(root.kindColor(modelData.kind), 0.4) : colors.alpha(root.kindColor(modelData.kind), 0.14)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14; anchors.rightMargin: 10
                        anchors.topMargin: 9; anchors.bottomMargin: 9
                        spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                Layout.preferredWidth: kindLbl.implicitWidth + 18; Layout.preferredHeight: 22; radius: 11
                                color: colors.alpha(root.kindColor(modelData.kind), 0.12)
                                border.width: 1; border.color: colors.alpha(root.kindColor(modelData.kind), 0.4)
                                Text { id: kindLbl; anchors.centerIn: parent; text: "#" + modelData.id + " " + modelData.kind; color: root.kindColor(modelData.kind); font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                            }
                            Text { text: (modelData.unit || "kernel").slice(0, 40); color: colors.alpha(colors.outline, 0.65); font.family: colors.fontSans; font.pixelSize: 8; elide: Text.ElideRight; Layout.maximumWidth: 200 }
                            Item { Layout.fillWidth: true }
                            Text { text: String(modelData.ts).slice(5, 19).replace("T", " "); color: colors.alpha(colors.outline, 0.45); font.family: colors.fontSans; font.pixelSize: 8 }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: modelData.summary; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                            Rectangle {
                                width: 88; height: 28; radius: 9
                                color: ecMa.containsMouse ? colors.alpha(colors.secondary, 0.25) : colors.alpha(colors.surface, 0.4)
                                border.width: 1; border.color: colors.alpha(colors.secondary, 0.35)
                                Text { anchors.centerIn: parent; text: root.openingKey === "c:" + modelData.id ? "opening…" : "full log"; color: colors.secondary; font.family: colors.fontSans; font.pixelSize: 10; font.weight: Font.Bold }
                                MouseArea {
                                    id: ecMa; anchors.fill: parent; hoverEnabled: true
                                    onClicked: {
                                        var key = "c:" + modelData.id
                                        if (modelData.cursor && modelData.cursor !== "") root.openLog(key, root.cursorCmd(modelData.cursor))
                                        else if (modelData.unit && modelData.unit !== "") root.openLog(key, root.unitLogCmd(modelData.unit))
                                    }
                                }
                            }
                        }
                    }
                    MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
            Text {
                visible: root.errors.length === 0 && root.daemonState === "on"
                text: "No oops / segfaults / OOM kills recorded in the last 7 days."
                color: colors.alpha(colors.outline, 0.5); font.family: colors.fontSans; font.pixelSize: 9
            }

            // live console — journal warnings tail, proof under the lists
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                radius: 10
                color: colors.alpha(colors.surface, 0.45)
                border.width: 1
                border.color: colors.alpha(colors.primary, 0.25)
                clip: true
                ListView {
                    id: tailList
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true
                    spacing: 1
                    model: root.liveLines
                    boundsBehavior: Flickable.StopAtBounds
                    onCountChanged: if (count > 0) positionViewAtEnd()
                    delegate: Text {
                        required property var modelData
                        width: tailList.width
                        text: modelData
                        color: colors.alpha(colors.foreground, 0.75)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: root.liveLines.length === 0
                        anchors.centerIn: parent
                        text: "tail starting…"
                        color: colors.alpha(colors.outline, 0.5)
                        font.family: colors.fontSans
                        font.pixelSize: 9
                    }
                }
            }

            // footer — package integrity (on-demand, slow)
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    width: 118; height: 26; radius: 13
                    color: pkgMa.containsMouse ? colors.alpha(colors.tertiary, 0.2) : colors.alpha(colors.tertiary, 0.08)
                    border.width: 1; border.color: colors.alpha(colors.tertiary, 0.3)
                    Text { anchors.centerIn: parent; text: root.pkgBusy ? "verifying…" : "verify packages"; color: colors.tertiary; font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold }
                    MouseArea { id: pkgMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.runPkgCheck() }
                }
                Text { text: root.pkgMsg !== "" ? root.pkgMsg : "pacman -Qkk on demand (slow, security-paranoia tier)"; color: colors.alpha(colors.outline, 0.55); font.family: colors.fontSans; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }
}
