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
    visible: root.open
    focusable: true
    IpcHandler { target: "keybinds"; function toggle(): void { root.open = !root.open } }

    onOpenChanged: if(open){ slide.y = 20; slideIn.restart(); filter=""; searchField.text=""; searchField.forceActiveFocus() }

    property var binds: [
        {key:"SUPER + Return", desc:"Terminal", cat:"Apps", disp:"exec", arg:"uwsm-app -- ghostty"},
        {key:"SUPER + Space", desc:"Launch apps", cat:"Apps", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call launcher toggle"},
        {key:"SUPER Shift + F", desc:"File manager", cat:"Apps", disp:"exec", arg:"uwsm-app -- filemanager --gui"},
        {key:"SUPER Shift + B", desc:"Browser", cat:"Apps", disp:"exec", arg:"xdg-open https://google.com"},
        {key:"SUPER Shift + N", desc:"Editor (Zed)", cat:"Apps", disp:"exec", arg:"uwsm-app -- zed"},
        {key:"SUPER Shift + M", desc:"Music (Spotify)", cat:"Apps", disp:"exec", arg:"uwsm-app -- spotify"},
        {key:"SUPER Shift + G", desc:"Signal", cat:"Apps", disp:"exec", arg:"uwsm-app -- signal-desktop"},
        {key:"SUPER Shift + O", desc:"Obsidian", cat:"Apps", disp:"exec", arg:"uwsm-app -- obsidian"},
        {key:"SUPER Shift + W", desc:"Typora", cat:"Apps", disp:"exec", arg:"uwsm-app -- typora"},
        {key:"SUPER Shift + /", desc:"Passwords", cat:"Apps", disp:"exec", arg:"uwsm-app -- 1password"},
        {key:"SUPER Shift + D", desc:"Docker (lazydocker)", cat:"Apps", disp:"exec", arg:"uwsm-app -- ghostty -e lazydocker"},
        {key:"SUPER + H", desc:"WiFi manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call wifi toggle"},
        {key:"SUPER + U", desc:"System monitor", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call sysmon toggle"},
        {key:"SUPER Alt + C", desc:"Calendar", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call calendar toggle"},
        {key:"SUPER + K", desc:"Show key bindings", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call keybinds toggle"},
        {key:"SUPER + N", desc:"System info", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call fastfetch toggle"},
        {key:"SUPER + E", desc:"Theme selector", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call theme toggle"},
        {key:"SUPER Ctrl + V", desc:"Clipboard manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call clipboard toggle"},
        {key:"SUPER Ctrl + E", desc:"Emoji picker", cat:"System", disp:"exec", arg:"uwsm-app -- ~/.config/rofi/emoji.sh"},
        {key:"SUPER Alt + B", desc:"Battery", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call battery toggle"},
        {key:"SUPER + Esc", desc:"Power menu", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call power toggle"},
        {key:"SUPER Shift + Q", desc:"Shut down", cat:"System", disp:"exec", arg:"systemctl poweroff"},
        {key:"SUPER Shift + R", desc:"Reboot", cat:"System", disp:"exec", arg:"systemctl reboot"},
        {key:"SUPER Alt + P", desc:"Control center", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call controlcenter toggle"},
        {key:"SUPER + I", desc:"Package manager", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call pkgman toggle"},
        {key:"SUPER Alt + W", desc:"Wallpaper store", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call wallshelf toggle"},
        {key:"SUPER Alt + N", desc:"PDF library", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call pdfviewer toggle"},
        {key:"SUPER Shift + Space", desc:"Toggle bar sides", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call bar toggle"},
        {key:"SUPER Alt + Space", desc:"Island style", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call bar toggleIsland"},
        {key:"SUPER Alt + T", desc:"Screen time", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call screentime toggle"},
        {key:"SUPER Alt + K", desc:"Phone link", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call phonelink toggle"},
        {key:"SUPER Alt + D", desc:"Drive health", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call drives toggle"},
        {key:"SUPER Alt + V", desc:"Audio visualizer", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call visualizer toggle"},
        {key:"SUPER Alt + ,", desc:"Notification center", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call notifications toggle"},
        {key:"SUPER + ,", desc:"Notification center", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call notifications toggle"},
        {key:"SUPER Shift + ,", desc:"Do not disturb", cat:"System", disp:"exec", arg:"quickshell -p ~/.config/quickshell ipc call notifications toggleDnd"},
        {key:"SUPER + R", desc:"Screen record toggle", cat:"System", disp:"exec", arg:"uwsm-app -- record"},
        {key:"SUPER Ctrl + T", desc:"System activity (btop)", cat:"System", disp:"exec", arg:"uwsm-app -- ghostty -e btop"},
        {key:"Print", desc:"Screenshot (drag area)", cat:"System", disp:"exec", arg:"shot"},
        {key:"Shift + Print", desc:"Screenshot fullscreen", cat:"System", disp:"exec", arg:"shot full"},
        {key:"Alt + Print", desc:"Screen record (alt)", cat:"System", disp:"exec", arg:"record"},
        {key:"SUPER + Print", desc:"Color picker", cat:"System", disp:"exec", arg:"pkill hyprpicker || hyprpicker -a"},
        {key:"SUPER Ctrl + Print", desc:"OCR from screenshot", cat:"System", disp:"exec", arg:"shot ocr"},
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
    ]

    property var filtered: {
        if(filter.trim()==="") return binds
        var q=filter.trim().toLowerCase()
        return binds.filter(function(b){ return b.key.toLowerCase().includes(q) || b.desc.toLowerCase().includes(q) || b.cat.toLowerCase().includes(q) })
    }
    function executeSelected(){
        var idx=list.currentIndex
        if(idx<0 || idx>=filtered.length) return
        var b=filtered[idx]
        root.open=false
        if(b.disp==="exec" && b.arg) Quickshell.execDetached(["sh","-c", b.arg])
        else if(b.disp) Quickshell.execDetached(["hyprctl", "dispatch", b.disp, b.arg])
    }

    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open?0.35:0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: root.open=false }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 640
        height: 520
        radius: 18
        color: colors.alpha(colors.background,0.97)
        border.width:1; border.color: colors.alpha(colors.outline,0.25)
        focus: root.open
        Keys.onEscapePressed: root.open=false
        Keys.onReturnPressed: root.executeSelected()
        Keys.onEnterPressed: root.executeSelected()
        Keys.onDownPressed: { list.currentIndex = Math.min(list.currentIndex+1, filtered.length-1); list.positionViewAtIndex(list.currentIndex, ListView.Contain) }
        Keys.onUpPressed: { list.currentIndex = Math.max(list.currentIndex-1, 0); list.positionViewAtIndex(list.currentIndex, ListView.Contain) }
        transform: Translate { id: slide }
        Component.onCompleted: slide.y=20
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "y"; from:20; to:0; duration:260; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from:0; to:1; duration:200 }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Keybindings"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth:true }
                Text { text: filtered.length+" / "+binds.length; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse?colors.alpha(colors.error,0.12):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.error:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 13 }
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
                font.family:"FiraCode Nerd Font"; font.pixelSize: 11
                background: Rectangle {
                    radius: 10
                    color: colors.alpha(colors.surface,0.8)
                    border.width:1; border.color: searchField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
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
                model: root.filtered
                currentIndex: 0
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 44
                    radius: 10
                    color: list.currentIndex===index ? colors.alpha(colors.primary,0.10) : ma.containsMouse ? colors.alpha(colors.primary,0.08) : "transparent"
                    border.width: list.currentIndex===index ? 1 : 0
                    border.color: colors.alpha(colors.primary,0.2)
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
                                text: modelData.key
                                color: colors.primary
                                font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.desc
                                color: colors.foreground
                                font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.cat
                                color: colors.alpha(colors.outline,0.6)
                                font.family:"FiraCode Nerd Font"; font.pixelSize: 8
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                    MouseArea {
                        id: ma; anchors.fill: parent; hoverEnabled:true
                        onClicked: list.currentIndex=index
                        onDoubleClicked: root.executeSelected()
                    }
                }
            }

            Text {
                visible: root.filtered.length===0
                text: "No matches"
                color: colors.alpha(colors.outline,0.6)
                font.family:"FiraCode Nerd Font"; font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
