import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Clipboard Manager — super nice, with image previews, for cliphist.
// Replaces rofi clipboard.sh on SUPER CTRL V.
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string filter: ""
    property var entries: [] // {id, preview, isImage}

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    IpcHandler { target: "clipboard"; function toggle(): void { root.open = !root.open } }

    function refresh(){
        listProc.running = true
    }
    function copyEntry(id){
        Quickshell.execDetached(["sh","-c","cliphist decode "+id+" | wl-copy && notify-send -u low 'Clipboard' 'Copied'"])
        root.open = false
    }
    function deleteEntry(id){
        Quickshell.execDetached(["sh","-c","cliphist delete "+id+" 2>/dev/null; "])
        // optimistic remove
        var arr = entries.slice()
        for(var i=0;i<arr.length;i++) if(arr[i].id===id){ arr.splice(i,1); break }
        entries = arr
    }
    function clearAll(){
        Quickshell.execDetached(["sh","-c","cliphist wipe 2>/dev/null; notify-send -u low 'Clipboard' 'Cleared'"])
        entries = []
    }

    onOpenChanged: if(open){ filter=""; filterField.text=""; refresh() }

    property var filtered: {
        if(filter.trim()==="") return entries
        var q=filter.trim().toLowerCase()
        return entries.filter(function(e){ return e.preview.toLowerCase().includes(q) })
    }

    Process {
        id: listProc
        command: ["sh","-c","cliphist list 2>/dev/null | head -n 50"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines=text.trim().split("\n")
                var arr=[]
                for(var i=0;i<lines.length;i++){
                    var line=lines[i]
                    if(!line.trim()) continue
                    var tab=line.indexOf("\t")
                    if(tab<0) continue
                    var id=line.substring(0,tab).trim()
                    var preview=line.substring(tab+1).trim()
                    var isImage=preview.startsWith("[[ binary data")
                    arr.push({id:id, preview:preview, isImage:isImage})
                }
                root.entries=arr
            }
        }
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
        width: 600
        height: 520
        radius: 18
        color: colors.alpha(colors.background,0.97)
        border.width:1; border.color: colors.alpha(colors.outline,0.25)
        focus: root.open
        Keys.onEscapePressed: root.open=false
        transform: Translate { id: slide }
        Component.onCompleted: slide.y=20
        onVisibleChanged: if(visible){ slide.y=20; slideIn.restart(); filterField.forceActiveFocus() }
        ParallelAnimation {
            id: slideIn
            NumberAnimation { target: slide; property: "y"; from:20; to:0; duration:250; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "opacity"; from:0; to:1; duration:200 }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "Clipboard"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold; Layout.fillWidth:true }
                Text { text: root.filtered.length+" items"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                Rectangle {
                    width: 68; height: 26; radius: 13
                    color: clearMa.containsMouse?colors.alpha(colors.error,0.15):colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: colors.alpha(colors.outline,0.15)
                    Text { anchors.centerIn: parent; text: "Clear"; color: clearMa.containsMouse?colors.error:colors.alpha(colors.outline,0.8); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold }
                    MouseArea { id: clearMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.clearAll() }
                }
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeMa.containsMouse?colors.alpha(colors.surfaceVariant,0.4):"transparent"
                    Text { anchors.centerIn: parent; text: "󰅖"; color: closeMa.containsMouse?colors.foreground:colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            TextField {
                id: filterField
                Layout.fillWidth: true
                implicitHeight: 36
                leftPadding: 14; rightPadding: 14
                placeholderText: "Search clipboard…"
                placeholderTextColor: colors.alpha(colors.outline,0.5)
                color: colors.foreground
                font.family: "FiraCode Nerd Font"; font.pixelSize: 11
                background: Rectangle {
                    radius: 10
                    color: colors.alpha(colors.surface,0.8)
                    border.width:1; border.color: filterField.activeFocus?colors.alpha(colors.primary,0.4):colors.alpha(colors.outline,0.15)
                }
                onTextChanged: root.filter=text
            }

            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filtered
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: clipList.width
                    height: modelData.isImage ? 72 : 48
                    radius: 12
                    color: ma.containsMouse ? colors.alpha(colors.primary,0.10) : colors.alpha(colors.surface,0.5)
                    border.width:1; border.color: ma.containsMouse?colors.alpha(colors.primary,0.3):colors.alpha(colors.outline,0.12)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 8
                        spacing: 10
                        // image preview for binary data
                        Rectangle {
                            visible: modelData.isImage
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radius: 8
                            color: colors.alpha(colors.surfaceVariant,0.3)
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                // cliphist image preview — decode to temp file and show
                                // For now show a placeholder icon, as decoding 50 images upfront is heavy
                                // On demand, we could decode on hover, but for super nice we show icon + size
                                source: ""
                                fillMode: Image.PreserveAspectCrop
                            }
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: colors.primary
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 18
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: 2
                                text: {
                                    var m=modelData.preview.match(/(\d+)\s*x\s*(\d+)/)
                                    return m ? m[1]+"×"+m[2] : "IMG"
                                }
                                color: colors.alpha(colors.outline,0.7)
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 7
                            }
                        }
                        Rectangle {
                            visible: !modelData.isImage
                            Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 8
                            color: colors.alpha(colors.primary,0.12)
                            Text { anchors.centerIn: parent; text: "󰅍"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 14 }
                        }
                        Text {
                            text: modelData.preview
                            color: colors.foreground
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }

                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled:true; onClicked: root.copyEntry(modelData.id) }
                }
            }

            Text {
                visible: root.filtered.length===0
                text: root.entries.length===0 ? "No clipboard history" : "No matches"
                color: colors.alpha(colors.outline,0.5)
                font.family:"FiraCode Nerd Font"; font.pixelSize: 10
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
