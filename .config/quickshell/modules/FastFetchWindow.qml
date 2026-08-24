import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// System - mission-control card: live CPU/RAM meters, pkg-temp, real network
// rates (shared NetRate sampler), Matugen-accented spec rows, entrance motion.
FloatingWindow {
    id: root
    property var colors
    property bool open: false

    title: "System"
    implicitWidth: 500
    implicitHeight: 352
    minimumSize: Qt.size(470, 320)
    maximumSize: Qt.size(560, 400)
    color: "transparent"
    visible: root.open

    IpcHandler { target: "fastfetch"; function toggle(): void { root.open = !root.open } }

    // ---------- verified Nerd Font glyphs (AGENTS section 2) ----------
    readonly property var glyphs: ({
        arch: "󰌃", kernel: "󰒅", cpu: "󰻠", mem: "󰍛",
        gpu: "󰎮", pkg: "󰏖", clock: "󰅐", dl: "󰇚", ul: "󰕒"
    })
    readonly property var accents: [colors.primary, colors.secondary, colors.tertiary]

    // ---------- data ----------
    property string host: ""
    property string uptime: ""
    property string kernel: ""
    property string packages: ""
    property string cpuName: ""
    property string gpuName: ""
    property int tempC: 0
    property int cpuPct: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real _prevBusy: -1
    property real _prevIdle: -1
    readonly property real ramPct: memTotalGb > 0 ? Math.max(0, Math.min(100, Math.round(memUsedGb / memTotalGb * 100))) : 0
    readonly property color cpuColor: (cpuPct > 85 || tempC >= 75) ? colors.error : colors.primary

    NetRate { id: netRate }

    Process {
        id: infoProc
        command: ["sh","-c","echo \"$(cat /etc/hostname 2>/dev/null)|$(uptime -p 2>/dev/null | sed 's/up //')|$(uname -r)|$(pacman -Q 2>/dev/null | wc -l | xargs)|$(lscpu 2>/dev/null | grep 'Model name' | cut -d: -f2 | sed 's/Intel(R)//;s/CPU//;s/@.*//;s/  */ /g' | xargs)|$(lspci 2>/dev/null | grep -i 'vga\\|3d' | head -n1 | cut -d: -f3 | xargs)|$(for z in /sys/class/thermal/thermal_zone*; do [ \"$(cat $z/type 2>/dev/null)\" = \"x86_pkg_temp\" ] && cat $z/temp && break; done)\""]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var p = text.trim().split("|")
                if (p.length >= 7) {
                    root.host = p[0]; root.uptime = p[1]; root.kernel = p[2]
                    root.packages = p[3]; root.cpuName = p[4]; root.gpuName = p[5]
                    root.tempC = Math.round((parseInt(p[6]) || 0) / 1000)
                }
            }
        }
    }

    function sampleCpu() {
        var line = statFile.text().split("\n")[0]
        var f = line.split(/\s+/)
        if (f.length < 8) return
        var busy = parseInt(f[1]) + parseInt(f[2]) + parseInt(f[3]) + parseInt(f[6]) + parseInt(f[7]) + parseInt(f[8])
        var idle = parseInt(f[4]) + parseInt(f[5])
        if (_prevBusy >= 0) {
            var bd = busy - _prevBusy, id = idle - _prevIdle
            if (bd + id > 0) cpuPct = Math.round(bd * 100 / (bd + id))
        }
        _prevBusy = busy; _prevIdle = idle
    }
    function sampleMem() {
        var t = 0, a = 0
        var ls = memFile.text().split("\n")
        for (var i = 0; i < ls.length; i++) {
            if (ls[i].indexOf("MemTotal:") === 0) t = parseInt(ls[i].replace(/\D/g, ""))
            else if (ls[i].indexOf("MemAvailable:") === 0) a = parseInt(ls[i].replace(/\D/g, ""))
        }
        if (t > 0) { memTotalGb = t / 1048576; memUsedGb = (t - a) / 1048576 }
    }

    // matugen-replace-safe polling (reset path first — AGENTS section 5)
    Timer { interval: 6000; running: root.open; repeat: true; onTriggered: infoProc.running = true }
    Timer {
        interval: 2000; running: root.open; repeat: true
        onTriggered: {
            statFile.path = ""; statFile.path = "/proc/stat"; sampleCpu()
            memFile.path = ""; memFile.path = "/proc/meminfo"; sampleMem()
        }
    }
    onOpenChanged: {
        if (!open) return
        infoProc.running = true
        statFile.path = ""; statFile.path = "/proc/stat"; sampleCpu()
        memFile.path = ""; memFile.path = "/proc/meminfo"; sampleMem()
    }

    FileView { id: statFile; path: "/proc/stat"; printErrors: false }
    FileView { id: memFile; path: "/proc/meminfo"; printErrors: false }

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
                        source: "file:///home/uthman/fastfetchImages/95771929570969777-removebg-preview.png"
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: colors.alpha(colors.outline, 0.12) }

                    Text {
                        text: "LIVE"
                        color: colors.alpha(colors.outline, 0.65)
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }

                    // -- CPU meter --
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "CPU"; color: colors.alpha(colors.foreground, 0.7); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1 }
                            Text {
                                visible: root.tempC > 0
                                text: root.tempC + "°C"
                                color: root.tempC >= 70 ? colors.error : colors.tertiary
                                font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold
                            }
                            Item { Layout.fillWidth: true }
                            Text { text: root.cpuPct + "%"; color: root.cpuColor; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold }
                        }
                        Rectangle {
                            id: cpuTrack
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.surfaceVariant, 0.35)
                            Rectangle {
                                width: cpuTrack.width * root.cpuPct / 100
                                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                radius: 2
                                color: root.cpuColor
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 400 } }
                            }
                        }
                    }

                    // -- RAM meter --
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "MEMORY"; color: colors.alpha(colors.foreground, 0.7); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1 }
                            Item { Layout.fillWidth: true }
                            Text { text: root.memUsedGb.toFixed(2) + " / " + root.memTotalGb.toFixed(1) + " GB"; color: colors.alpha(colors.foreground, 0.6); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Medium }
                            Text { text: root.ramPct + "%"; color: colors.secondary; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.ExtraBold }
                        }
                        Rectangle {
                            id: ramTrack
                            Layout.fillWidth: true
                            height: 4
                            radius: 2
                            color: colors.alpha(colors.surfaceVariant, 0.35)
                            Rectangle {
                                width: ramTrack.width * root.ramPct / 100
                                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                radius: 2
                                color: colors.secondary
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // -- NET row --
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: root.glyphs.dl; color: colors.tertiary; font.family: "FiraCode Nerd Font"; font.pixelSize: 11 }
                        Text { text: netRate.fmt(netRate.rxKbs); color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 74 }
                        Text { text: root.glyphs.ul; color: colors.secondary; font.family: "FiraCode Nerd Font"; font.pixelSize: 11 }
                        Text { text: netRate.fmt(netRate.txKbs); color: colors.foreground; font.family: "FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold; Layout.preferredWidth: 74 }
                        Item { Layout.fillWidth: true }
                        Text { text: netRate.fmtTotal(netRate.totalRxMb) + " total"; color: colors.alpha(colors.outline, 0.5); font.family: "FiraCode Nerd Font"; font.pixelSize: 9; font.weight: Font.Medium }
                    }
                }
            }
        }

        Keys.onEscapePressed: root.open = false
        focus: root.open
    }
}
