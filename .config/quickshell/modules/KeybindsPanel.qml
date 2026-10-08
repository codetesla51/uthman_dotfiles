import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Keybinds — static, no dynamic loading, just text. Enter executes.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string filter: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open || closeAnim.running
    focusable: true
    // NOTE: no IpcHandler here — Bar.qml owns target "keybinds" and lazy-loads this.

    onOpenChanged: {
        if (open) { filter=""; searchField.text=""; searchField.forceActiveFocus(); list.currentIndex = firstRowIndex(); openAnim.restart() }
        else closeAnim.restart()
    }

    property var binds: [
        {key:"SUPER + Return", desc:"Terminal", cat:"Apps", disp:"exec", arg:"uwsm-app -- kitty"},
        {key:"SUPER + Space", desc:"Launch apps", cat:"Apps", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call launcher toggle"},
        {key:"SUPER Shift + F", desc:"File manager", cat:"Apps", disp:"exec", arg:"uwsm-app -- thunar"},
        {key:"SUPER Shift + B", desc:"Browser", cat:"Apps", disp:"exec", arg:"xdg-open https://google.com"},
        {key:"SUPER Shift + Z", desc:"Zen Browser", cat:"Apps", disp:"exec", arg:"uwsm-app -- zen"},
        {key:"SUPER Shift + N", desc:"Editor (Zed)", cat:"Apps", disp:"exec", arg:"uwsm-app -- zed"},
        {key:"SUPER Shift + M", desc:"Music (Spotify)", cat:"Apps", disp:"exec", arg:"uwsm-app -- spotify"},
        {key:"SUPER Shift + O", desc:"Obsidian", cat:"Apps", disp:"exec", arg:"uwsm-app -- obsidian"},
        {key:"SUPER + H", desc:"WiFi manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call wifi toggle"},
        {key:"SUPER + U", desc:"System monitor", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call sysmon toggle"},
        {key:"SUPER + K", desc:"Show key bindings", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call keybinds toggle"},
        {key:"SUPER + N", desc:"System info", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call fastfetch toggle"},
        {key:"SUPER Alt + C", desc:"Pomodoro timer", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call pomodoro toggle"},
        {key:"SUPER + E", desc:"Theme selector", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call theme toggle"},
        {key:"SUPER Ctrl + V", desc:"Clipboard manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call clipboard toggle"},
        {key:"SUPER Ctrl + E", desc:"Emoji picker", cat:"System", disp:"exec", arg:"uwsm-app -- ~/.config/rofi/emoji.sh"},
        {key:"SUPER Alt + B", desc:"Battery", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call battery toggle"},
        {key:"SUPER + Esc", desc:"Power menu", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call power toggle"},
        {key:"SUPER Shift + Q", desc:"Shut down", cat:"System", disp:"exec", arg:"systemctl poweroff"},
        {key:"SUPER Shift + R", desc:"Reboot", cat:"System", disp:"exec", arg:"systemctl reboot"},
        {key:"SUPER Alt + P", desc:"Control center", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call controlcenter toggle"},
        {key:"SUPER + I", desc:"Package manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call pkgman toggle"},
        {key:"SUPER Ctrl + Space", desc:"Wallpaper store", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call wallshelf toggle"},
        {key:"SUPER Alt + N", desc:"PDF library", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call pdfviewer toggle"},
        {key:"SUPER Shift + Space", desc:"Toggle bar sides", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call bar toggle"},
        {key:"SUPER Alt + Space", desc:"Island style", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call bar toggleIsland"},
        {key:"SUPER Alt + T", desc:"Screen time", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call screentime toggle"},
        {key:"SUPER Alt + K", desc:"Phone link", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call phonebridge toggle"},
        {key:"SUPER Alt + D", desc:"Hardware health", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call drives toggle"},
        {key:"SUPER + ,", desc:"Notification center", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call notifications toggle"},
        {key:"SUPER Shift + ,", desc:"Do not disturb", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call notifications toggleDnd"},
        {key:"SUPER + R", desc:"Screen record toggle", cat:"System", disp:"exec", arg:"uwsm-app -- record"},
        {key:"SUPER Ctrl + T", desc:"System activity (btop)", cat:"System", disp:"exec", arg:"uwsm-app -- kitty -e btop"},
        {key:"SUPER Shift + S", desc:"Screenshot fullscreen", cat:"System", disp:"exec", arg:"shot full"},
        {key:"SUPER Shift + D", desc:"Screenshot (drag area)", cat:"System", disp:"exec", arg:"shot"},
        {key:"SUPER Shift + Print", desc:"Screenshot (drag area)", cat:"System", disp:"exec", arg:"shot"},
        {key:"SUPER Shift Alt + Print", desc:"Screenshot fullscreen", cat:"System", disp:"exec", arg:"shot full"},
        {key:"SUPER Shift Ctrl Alt + Print", desc:"Screen record", cat:"System", disp:"exec", arg:"record"},
        {key:"SUPER Shift Ctrl + Print", desc:"OCR from screenshot", cat:"System", disp:"exec", arg:"shot ocr"},
        {key:"SUPER Alt + O", desc:"Workspace manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call wsview toggle"},
        {key:"SUPER Alt + Y", desc:"WatchCat (data watchdog)", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call watchcat toggle"},
        {key:"SUPER + Home", desc:"Restart shell", cat:"System", disp:"exec", arg:"hyprctl reload >/dev/null 2>&1; pkill -x quickshell; sleep 0.3; setsid quickshell -p ~/.config/quickshell >/dev/null 2>&1 &"},
        {key:"Volume Up", desc:"Volume up", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media volup"},
        {key:"Volume Down", desc:"Volume down", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media voldown"},
        {key:"Mute", desc:"Mute toggle", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media volmute"},
        {key:"Mic Mute", desc:"Mic mute toggle", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media micmute"},
        {key:"Brightness Up", desc:"Brightness up", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media briup"},
        {key:"Brightness Down", desc:"Brightness down", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call media bridown"},
        {key:"SUPER + W", desc:"Close window", cat:"Windows", disp:"killactive", arg:""},
        {key:"SUPER + T", desc:"Float / tile window", cat:"Windows", disp:"togglefloating", arg:""},
        {key:"SUPER + F", desc:"Full screen", cat:"Windows", disp:"fullscreen", arg:"0"},
        {key:"SUPER + Left", desc:"Focus left", cat:"Windows", disp:"movefocus", arg:"l"},
        {key:"SUPER + Right", desc:"Focus right", cat:"Windows", disp:"movefocus", arg:"r"},
        {key:"SUPER + Up", desc:"Focus up", cat:"Windows", disp:"movefocus", arg:"u"},
        {key:"SUPER + Down", desc:"Focus down", cat:"Windows", disp:"movefocus", arg:"d"},
        {key:"SUPER Shift + Left", desc:"Swap window left", cat:"Windows", disp:"swapwindow", arg:"l"},
        {key:"SUPER Shift + Right", desc:"Swap window right", cat:"Windows", disp:"swapwindow", arg:"r"},
        {key:"SUPER Shift + Up", desc:"Swap window up", cat:"Windows", disp:"swapwindow", arg:"u"},
        {key:"SUPER Shift + Down", desc:"Swap window down", cat:"Windows", disp:"swapwindow", arg:"d"},
        {key:"SUPER + L", desc:"Toggle layout", cat:"Windows", disp:"exec", arg:"layout-toggle"},
        {key:"SUPER + 1", desc:"Workspace 1", cat:"Workspaces", disp:"workspace", arg:"1"},
        {key:"SUPER + 2", desc:"Workspace 2", cat:"Workspaces", disp:"workspace", arg:"2"},
        {key:"SUPER + 3", desc:"Workspace 3", cat:"Workspaces", disp:"workspace", arg:"3"},
        {key:"SUPER + 4", desc:"Workspace 4", cat:"Workspaces", disp:"workspace", arg:"4"},
        {key:"SUPER + 5", desc:"Workspace 5", cat:"Workspaces", disp:"workspace", arg:"5"},
        {key:"SUPER + 6", desc:"Workspace 6", cat:"Workspaces", disp:"workspace", arg:"6"},
        {key:"SUPER + 7", desc:"Workspace 7", cat:"Workspaces", disp:"workspace", arg:"7"},
        {key:"SUPER + 8", desc:"Workspace 8", cat:"Workspaces", disp:"workspace", arg:"8"},
        {key:"SUPER + 9", desc:"Workspace 9", cat:"Workspaces", disp:"workspace", arg:"9"},
        {key:"SUPER + 10", desc:"Workspace 10", cat:"Workspaces", disp:"workspace", arg:"10"},
        {key:"SUPER Shift + 1", desc:"Move to workspace 1", cat:"Workspaces", disp:"movetoworkspace", arg:"1"},
        {key:"SUPER Shift + 2", desc:"Move to workspace 2", cat:"Workspaces", disp:"movetoworkspace", arg:"2"},
        {key:"SUPER Shift + 3", desc:"Move to workspace 3", cat:"Workspaces", disp:"movetoworkspace", arg:"3"},
        {key:"SUPER Shift + 4", desc:"Move to workspace 4", cat:"Workspaces", disp:"movetoworkspace", arg:"4"},
        {key:"SUPER Shift + 5", desc:"Move to workspace 5", cat:"Workspaces", disp:"movetoworkspace", arg:"5"},
        {key:"SUPER Shift + 6", desc:"Move to workspace 6", cat:"Workspaces", disp:"movetoworkspace", arg:"6"},
        {key:"SUPER Shift + 7", desc:"Move to workspace 7", cat:"Workspaces", disp:"movetoworkspace", arg:"7"},
        {key:"SUPER Shift + 8", desc:"Move to workspace 8", cat:"Workspaces", disp:"movetoworkspace", arg:"8"},
        {key:"SUPER Shift + 9", desc:"Move to workspace 9", cat:"Workspaces", disp:"movetoworkspace", arg:"9"},
        {key:"SUPER Shift + 10", desc:"Move to workspace 10", cat:"Workspaces", disp:"movetoworkspace", arg:"10"},
        {key:"SUPER + Tab", desc:"Next workspace", cat:"Workspaces", disp:"workspace", arg:"e+1"},
        {key:"SUPER Shift + Tab", desc:"Prev workspace", cat:"Workspaces", disp:"workspace", arg:"e-1"},
        {key:"Ctrl + T / W / R", desc:"New / close / reload tab", cat:"Zen"},
        {key:"Ctrl + L", desc:"Address bar", cat:"Zen"},
        {key:"Ctrl + H / B", desc:"History / bookmarks sidebar", cat:"Zen"},
        {key:"Ctrl + Alt + Left / Right", desc:"Prev / next workspace", cat:"Zen"},
        {key:"Ctrl + Alt + G / V / H", desc:"Split grid / vertical / horizontal", cat:"Zen"},
        {key:"Ctrl + Alt + U", desc:"Unsplit", cat:"Zen"},
        {key:"Ctrl + S", desc:"Compact mode (auto-hide sidebar)", cat:"Zen"},
        {key:"Ctrl + Alt + S", desc:"Peek sidebar in compact mode", cat:"Zen"},
        {key:"Ctrl + O", desc:"Glance (peek link)", cat:"Zen"},
        {key:"Ctrl + Shift + D", desc:"Pin tab (essential)", cat:"Zen"},
        {key:"Ctrl + T / W / R", desc:"New / close / reload tab", cat:"Firefox"},
        {key:"Ctrl + L", desc:"Address bar", cat:"Firefox"},
        {key:"Ctrl + K", desc:"Search", cat:"Firefox"},
        {key:"Ctrl + F", desc:"Find in page", cat:"Firefox"},
        {key:"Ctrl + H / J", desc:"History / downloads", cat:"Firefox"},
        {key:"Ctrl + B", desc:"Bookmarks sidebar", cat:"Firefox"},
        {key:"Ctrl + D", desc:"Bookmark this page", cat:"Firefox"},
        {key:"Ctrl + Shift + T", desc:"Reopen closed tab", cat:"Firefox"},
        {key:"Space Space", desc:"Find files", cat:"Neovim"},
        {key:"Space /", desc:"Grep project", cat:"Neovim"},
        {key:"Space E", desc:"File explorer", cat:"Neovim"},
        {key:"Space B D", desc:"Delete buffer", cat:"Neovim"},
        {key:"Shift + H / L", desc:"Prev / next buffer", cat:"Neovim"},
        {key:"Ctrl + H / J / K / L", desc:"Move between splits", cat:"Neovim"},
        {key:"Space - / |", desc:"Split below / right", cat:"Neovim"},
        {key:"Space W M", desc:"Zoom split", cat:"Neovim"},
        {key:"Space G G", desc:"Lazygit", cat:"Neovim"},
        {key:"Space Q Q", desc:"Quit all", cat:"Neovim"},
        {key:"Ctrl + P", desc:"Command palette", cat:"Obsidian"},
        {key:"Ctrl + O", desc:"Quick switcher (open note)", cat:"Obsidian"},
        {key:"Ctrl + N", desc:"New note", cat:"Obsidian"},
        {key:"Ctrl + Shift + F", desc:"Search vault", cat:"Obsidian"},
        {key:"Ctrl + E", desc:"Toggle edit / preview", cat:"Obsidian"},
        {key:"Ctrl + F", desc:"Find in note", cat:"Obsidian"},
        {key:"Ctrl + P", desc:"File finder", cat:"Zed"},
        {key:"Ctrl + Shift + P", desc:"Command palette", cat:"Zed"},
        {key:"Ctrl + `", desc:"Terminal", cat:"Zed"},
        {key:"Ctrl + Shift + F", desc:"Project search", cat:"Zed"},
        {key:"Ctrl + ,", desc:"Settings", cat:"Zed"},
        {key:"Ctrl + W", desc:"Close tab", cat:"Zed"},
        {key:"Ctrl + Tab", desc:"Next tab", cat:"Zed"},
    ]

    property var filtered: {
        if(filter.trim()==="") return binds
        // token-AND: every word must match somewhere (key, desc, cat, arg).
        // "zen split" finds split rows; "super shift" narrows to chords.
        var toks = filter.trim().toLowerCase().split(/\s+/)
        return binds.filter(function(b){
            var hay = (b.key + " " + b.desc + " " + b.cat + " " + (b.arg || "")).toLowerCase()
            for (var i = 0; i < toks.length; i++) if (!hay.includes(toks[i])) return false
            return true
        })
    }
    // grouped model — category header rows interleaved with binds so the
    // list reads as sections, not a dumb flat dump. Headers carry only
    // {header}, rows carry the bind.
    property var grouped: {
        var out = [], last = ""
        for (var i = 0; i < filtered.length; i++) {
            if (filtered[i].cat !== last) { last = filtered[i].cat; out.push({header: last}) }
            out.push(filtered[i])
        }
        return out
    }
    function firstRowIndex(){ for (var i=0;i<grouped.length;i++) if(grouped[i].header===undefined) return i; return -1 }
    function moveSelection(d){
        var i=list.currentIndex
        while (true) {
            i+=d
            if (i<0) { i=0; break }
            if (i>=grouped.length) { i=grouped.length-1; break }
            if (grouped[i].header===undefined) break
        }
        list.currentIndex=i; list.positionViewAtIndex(i,ListView.Contain)
    }
    function executeSelected(){
        var idx=list.currentIndex
        if(idx<0 || idx>=grouped.length) return
        var b=grouped[idx]
        if(b.header!==undefined) return
        root.open=false
        if(b.disp==="exec" && b.arg) Quickshell.execDetached(["sh","-c", b.arg])
        else if(b.disp) Quickshell.execDetached(["hyprctl", "dispatch", b.disp, b.arg])
    }
    onFilteredChanged: list.currentIndex = firstRowIndex()

    // click-outside catcher (invisible — no dim backdrop, card floats over desktop)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        MouseArea { anchors.fill: parent; onClicked: root.open=false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 640
        height: 520
        radius: 18
        color: colors.alpha(colors.surface, 0.52)
        border.width:1; border.color: colors.alpha(colors.outline, 0.15)
        focus: root.open
        Keys.onEscapePressed: root.open=false
        Keys.onReturnPressed: root.executeSelected()
        Keys.onEnterPressed: root.executeSelected()
        // type-to-search — keystrokes landing on the card (field not focused)
        // route straight into the search field
        Keys.onPressed: function(e){
            if (searchField.activeFocus) return
            if (e.text !== "" && e.text.length === 1 && (e.modifiers === Qt.NoModifier || e.modifiers === Qt.ShiftModifier)
                && e.key !== Qt.Key_Escape && e.key !== Qt.Key_Return && e.key !== Qt.Key_Enter) {
                searchField.text += e.text
                searchField.forceActiveFocus()
                e.accepted = true
            }
        }
        Keys.onDownPressed: root.moveSelection(1)
        Keys.onUpPressed: root.moveSelection(-1)
        transform: Translate { id: slide }
        Component.onCompleted: slide.y=20
        // bezier pair — rise settles with overshoot bounce on open, hurries
        // out plain on close. Card is centered so scale uses the card
        // property (transformOrigin center) instead of an edge Scale.
        ParallelAnimation {
            id: openAnim
            NumberAnimation { target: slide; property: "y"; from: 20; to: 0; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; from: 0.96; to: 1; duration: 280; easing.type: Easing.Bezier; easing.bezierCurve: [0.34, 1.35, 0.64, 1] }
        }
        ParallelAnimation {
            id: closeAnim
            NumberAnimation { target: slide; property: "y"; to: 20; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
            NumberAnimation { target: card; property: "scale"; to: 0.96; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1] }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Keybindings"; color: colors.foreground; font.family: colors.fontSans; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth:true }
                Text { text: filtered.length+" / "+binds.length; color: colors.alpha(colors.outline,0.6); font.family: colors.fontSans; font.pixelSize: 9 }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse?colors.alpha(colors.error,0.12):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.error:colors.alpha(colors.outline,0.7); font.family: colors.fontSans; font.pixelSize: 13 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 36
                leftPadding: 14; rightPadding: 14
                placeholderText: "Search keybindings… (try 'window' or 'super')"
                placeholderTextColor: colors.alpha(colors.outline,0.5)
                color: colors.foreground
                font.family: colors.fontSans; font.pixelSize: 11
                background: Rectangle {
                    radius: 12
                    color: colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: searchField.activeFocus?colors.alpha(colors.primary,0.5):colors.alpha(colors.outline,0.15)
                }
                onTextChanged: root.filter=text
                Keys.onReturnPressed: root.executeSelected()
                Keys.onEnterPressed: root.executeSelected()
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.grouped
                currentIndex: 0
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property bool isHeader: modelData.header !== undefined
                    width: list.width
                    height: isHeader ? 26 : 44

                    // section header — house micro-type
                    Text {
                        visible: isHeader
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
                        text: isHeader ? modelData.header.toUpperCase() : ""
                        color: colors.alpha(colors.outline, 0.6)
                        font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.5
                    }

                    Rectangle {
                        visible: !isHeader
                        anchors.fill: parent
                        radius: 10
                        color: list.currentIndex===index ? colors.alpha(colors.primary,0.10) : ma.containsMouse ? colors.alpha(colors.primary,0.08) : "transparent"
                        border.width: list.currentIndex===index ? 1 : 0
                        border.color: colors.alpha(colors.primary,0.2)
                        // one hover language: tint + slight scale, no lift (same as plugins)
                        scale: (list.currentIndex===index || ma.containsMouse) ? 1.01 : 1
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12; anchors.rightMargin: 12
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: keyText.implicitWidth+16
                                Layout.preferredHeight: 22
                                radius: 7
                                color: colors.alpha(colors.primary,0.12)
                                border.width:1; border.color: colors.alpha(colors.primary,0.25)
                                Text {
                                    id: keyText
                                    anchors.centerIn: parent
                                    text: isHeader ? "" : modelData.key
                                    color: colors.primary
                                    font.family: colors.fontSans; font.pixelSize: 9; font.weight: Font.Bold
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: isHeader ? "" : modelData.desc
                                    color: colors.foreground
                                    font.family: colors.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: isHeader ? "" : modelData.cat
                                    color: colors.alpha(colors.outline,0.6)
                                    font.family: colors.fontSans; font.pixelSize: 8
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: ma; anchors.fill: parent; hoverEnabled:true
                        visible: !isHeader
                        onClicked: list.currentIndex=index
                        onDoubleClicked: root.executeSelected()
                    }
                }
            }

            Text {
                visible: root.filtered.length===0
                text: "No matches"
                color: colors.alpha(colors.outline,0.6)
                font.family: colors.fontSans; font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }

            // footer — kbd hints, same language as plugins
            Row {
                spacing: 12
                Layout.alignment: Qt.AlignHCenter
                Repeater {
                    model: [ { k: "↑↓", a: "move" }, { k: "↵", a: "run" }, { k: "esc", a: "close" } ]
                    delegate: Row {
                        required property var modelData
                        spacing: 4
                        Rectangle {
                            width: Math.max(22, kbdTxt.implicitWidth + 10)
                            height: 16
                            radius: 4
                            color: colors.alpha(colors.surfaceVariant, 0.5)
                            border.width: 1; border.color: colors.alpha(colors.outline, 0.12)
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: kbdTxt
                                anchors.centerIn: parent
                                text: modelData.k
                                color: colors.secondary
                                font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold
                            }
                        }
                        Text {
                            text: modelData.a
                            color: colors.alpha(colors.outline, 0.45)
                            font.family: colors.fontSans; font.pixelSize: 7; font.weight: Font.Bold; font.letterSpacing: 1.3
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
