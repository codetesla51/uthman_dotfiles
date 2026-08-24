import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// System — simple, clean, fast
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    title: "System"
    implicitWidth: 560
    implicitHeight: 340
    minimumSize: Qt.size(520, 300)
    maximumSize: Qt.size(600, 360)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "fastfetch"; function toggle(): void { root.open = !root.open } }

    property string host: ""
    property string uptime: ""
    property string kernel: ""
    property string packages: ""
    property string cpuName: ""
    property string gpuName: ""
    property string mem: ""

    Process {
        id: infoProc
        command: ["sh","-c","echo \"$(cat /etc/hostname 2>/dev/null | tr -d '\\n')|$(uptime -p 2>/dev/null | sed 's/up //')|$(uname -r 2>/dev/null)|$(pacman -Q 2>/dev/null | wc -l | xargs)|$(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | sed 's/Intel(R)//;s/CPU//;s/@.*//;s/  */ /g' | xargs)|$(lspci 2>/dev/null | grep -i 'vga\\|3d' | head -n1 | cut -d: -f3 | xargs)|$(free -h 2>/dev/null | awk '/Mem:/{print $3\" / \"$2}')\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var p=text.trim().split("|")
                if(p.length>=7){
                    root.host=p[0]; root.uptime=p[1]; root.kernel=p[2]; root.packages=p[3]; root.cpuName=p[4]; root.gpuName=p[5]; root.mem=p[6]
                }
            }
        }
    }
    Timer { interval: 6000; running: root.open; repeat: true; triggeredOnStart: true; onTriggered: infoProc.running=true }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: colors.alpha(colors.background, 0.90)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16
            Item {
                Layout.preferredWidth: 160
                Layout.fillHeight: true
                clip: true
                Image {
                    anchors.fill: parent
                    source: "file:///home/uthman/fastfetchImages/95771929570969777-removebg-preview.png"
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "uthman@" + root.host; color: colors.primary; font.family: "FiraCode Nerd Font"; font.pixelSize: 14; font.weight: Font.ExtraBold }
                GridLayout {
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 6
                    Layout.fillWidth: true
                    Text { text: "OS"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: "Arch Linux"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true }
                    Text { text: "Kernel"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.kernel; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: "Uptime"; color: colors.secondary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.uptime; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true }
                    Text { text: "Packages"; color: colors.tertiary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.packages; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true }
                    Text { text: "CPU"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.cpuName; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: "GPU"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.gpuName || "—"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: "MEM"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 50 }
                    Text { text: root.mem; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; Layout.fillWidth: true }
                }
            }
        }
        Keys.onEscapePressed: root.open=false
        focus: root.open
    }
}
