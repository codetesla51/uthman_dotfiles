import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// System - mission-control card: live CPU/RAM meters, pkg-temp, real network
// System - mission-control card: Matugen-accented spec rows, entrance motion.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    title: "System"
    implicitWidth: 500
    implicitHeight: 296
    minimumSize: Qt.size(470, 280)
    maximumSize: Qt.size(560, 340)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "fastfetch"; function toggle(): void { root.open = !root.open } }

    // ---------- verified Nerd Font glyphs (AGENTS section 2) ----------
    readonly property var glyphs: ({
        arch: "󰌃", kernel: "󰒅", cpu: "󰻠", mem: "󰍛",
        gpu: "󰎮", pkg: "󰏖", clock: "󰅐", dl: "󰇚", ul: "󰕒"
    })
    readonly property var accents: [colors.primary, colors.secondary, colors.tertiary]

    Timer { interval: 6000; running: root.open; repeat: true; onTriggered: infoProc.running = true }
    onOpenChanged: if (open) infoProc.running = true

    // ---------- data ----------
    property string host: ""
    property string uptime: ""
    property string kernel: ""
    property string packages: ""
    property string cpuName: ""
    property string gpuName: ""

    Process {
        id: infoProc
        command: ["sh","-c","echo \"$(cat /etc/hostname 2>/dev/null)|$(uptime -p 2>/dev/null | sed 's/up //')|$(uname -r)|$(pacman -Q 2>/dev/null | wc -l | xargs)|$(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | sed 's/Intel(R)//;s/CPU//;s/@.*//;s/  */ /g' | xargs)|$(lspci 2>/dev/null | grep -i 'vga\\|3d' | head -n1 | cut -d: -f3 | xargs)\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var p = text.trim().split("|")
                if (p.length >= 6) {
                    root.host = p[0]; root.uptime = p[1]; root.kernel = p[2]
                    root.packages = p[3]; root.cpuName = p[4]; root.gpuName = p[5]
                }
            }
        }
    }


    // ---------- UI ----------
    Rectangle {
        id: card
        anchors.fill: parent
        radius: 18
        color: colors.alpha(colors.background, 0.92)
        border.width: 1
        border.color: colors.alpha(colors.outline, 0.12)
        scale: root.open ? 1 : 0.96
        opacity: root.open ? 1 : 0
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // -- header: who + uptime chip --
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: root.glyphs.arch + "  uthman@" + (root.host !== "" ? root.host : "arch")
                    color: colors.primary
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 15
                    font.weight: Font.ExtraBold
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    visible: root.uptime !== ""
                    radius: 9
                    height: 22
                    width: upRow.implicitWidth + 16
                    color: colors.alpha(colors.surfaceVariant, 0.30)
                    border.width: 1
                    border.color: colors.alpha(colors.outline, 0.12)
                    Row {
                        id: upRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text { text: root.glyphs.clock; color: colors.tertiary; font.family: "FiraCode Nerd Font"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: root.uptime; color: colors.alpha(colors.foreground, 0.8); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

            // -- body: art | specs+live --
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Item {
                    Layout.preferredWidth: 148
                    Layout.fillHeight: true
                    // soft halo behind the art
                    Rectangle {
                        width: 120; height: 120; radius: 60
                        anchors.centerIn: parent
                        color: colors.alpha(colors.primary, 0.06)
                    }
                    Image {
                        anchors.centerIn: parent
                        source: "file:///home/uthman/fastfetchImages/Hollow_Knight_Game_Team_Cherry_Sticker_PNG-removebg-preview.png"
                        width: 132
                        height: 132
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                    }
                }

                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: colors.alpha(colors.outline, 0.12) }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 7

                    Text {
                        text: "SYSTEM"
                        color: colors.alpha(colors.outline, 0.65)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }

                    Repeater {
                        model: [
                            { i: root.glyphs.arch,   l: "OS",       v: "Arch Linux x86_64" },
                            { i: root.glyphs.kernel, l: "KERNEL",   v: root.kernel },
                            { i: root.glyphs.pkg,    l: "PACKAGES", v: root.packages === "" ? "—" : root.packages + "  ·  pacman" },
                            { i: root.glyphs.cpu,    l: "CPU",      v: root.cpuName === "" ? "—" : root.cpuName },
                            { i: root.glyphs.gpu,    l: "GPU",      v: root.gpuName === "" ? "integrated" : root.gpuName }
                        ]
                        delegate: RowLayout {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Text { text: modelData.i; color: root.accents[index % 3]; font.family: "FiraCode Nerd Font"; font.pixelSize: 12 }
                            Text { text: modelData.l; color: colors.alpha(colors.outline, 0.8); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.2; Layout.preferredWidth: 62 }
                            Text { text: modelData.v; color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }

                }
            }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
