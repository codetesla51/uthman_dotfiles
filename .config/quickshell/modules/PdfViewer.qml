import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// PDF Viewer — layershell popup, glass, pdftoppm backend
// Skeleton: layout + theming, file open via path, page nav, pdftoppm one-page
PanelWindow {
    id: root
    property var colors
    property bool open: false
    property string pdfPath: ""
    property int currentPage: 1
    property int totalPages: 0
    property real zoom: 1.0
    property string pageImage: "" // file:///tmp/pdf_viewer/page-1.png
    property bool loading: false
    property string errorMsg: ""

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open
    focusable: true
    WlrLayershell.namespace: "qs-pdfviewer"
    WlrLayershell.layer: WlrLayer.Overlay

    IpcHandler {
        target: "pdfviewer"
        function toggle(): void { root.open = !root.open }
        function open(path: string): void { root.pdfPath = path; root.open = true; root.loadPdf() }
        function close(): void { root.open = false }
    }

    onOpenChanged: if(open) Qt.callLater(function(){ card.forceActiveFocus() })

    function loadPdf(){
        if(!pdfPath) return
        errorMsg = ""
        totalPages = 0
        currentPage = 1
        // get total pages via pdfinfo
        infoProc.running = true
    }
    function renderPage(page){
        if(!pdfPath || !totalPages) return
        page = Math.max(1, Math.min(page, totalPages))
        currentPage = page
        loading = true
        // render one page at 150 DPI to /tmp/pdf_viewer
        var dpi = Math.round(150 * zoom)
        renderProc.command = ["sh","-c","mkdir -p /tmp/pdf_viewer && pdftoppm -png -r "+dpi+" -f "+page+" -l "+page+" -singlefile '"+pdfPath.replace(/'/g,"'\\''")+"' /tmp/pdf_viewer/page 2>&1 && echo RENDER_OK || echo RENDER_FAIL"]
        renderProc.running = true
        // pre-render next page in background if not last
        if(page < totalPages){
            var next = page + 1
            preRenderProc.command = ["sh","-c","pdftoppm -png -r "+dpi+" -f "+next+" -l "+next+" -singlefile '"+pdfPath.replace(/'/g,"'\\''")+"' /tmp/pdf_viewer/page_next 2>&1 & disown"]
            // delay a bit so main render isn't contended
            preRenderTimer.nextPage = next
            preRenderTimer.restart()
        }
    }
    function nextPage(){ if(currentPage < totalPages) renderPage(currentPage+1) }
    function prevPage(){ if(currentPage > 1) renderPage(currentPage-1) }
    function zoomIn(){ zoom = Math.min(2.0, zoom + 0.15); renderPage(currentPage) }
    function zoomOut(){ zoom = Math.max(0.6, zoom - 0.15); renderPage(currentPage) }

    Timer { id: preRenderTimer; interval: 400; property int nextPage: 2; onTriggered: preRenderProc.running = true }

    Process {
        id: infoProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var m = text.match(/Pages:\s+(\d+)/)
                if(m){ root.totalPages = parseInt(m[1]); root.renderPage(1) }
                else { root.errorMsg = "Could not read PDF info"; }
            }
        }
        onRunningChanged: if(!running && !totalPages) {} // handled in onStreamFinished
    }
    Process {
        id: renderProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if(text.indexOf("RENDER_OK") !== -1){
                    // bust cache by toggling source: set empty then real, no ?t= query (file:// doesn't handle it)
                    root.pageImage = ""
                    Qt.callLater(function(){ root.pageImage = "file:///tmp/pdf_viewer/page.png" })
                    root.loading = false
                    root.errorMsg = ""
                } else {
                    root.loading = false
                    root.errorMsg = "Render failed: " + text.slice(0,200)
                }
            }
        }
        onRunningChanged: if(!running && loading && pageImage==="") {}
    }
    Process { id: preRenderProc }

    // adapt infoProc command dynamically
    onPdfPathChanged: {
        if(pdfPath) infoProc.command = ["sh","-c","pdfinfo '"+pdfPath.replace(/'/g,"'\\''")+"' 2>&1"]
    }

    // dim backdrop — click outside does NOT close (only Esc/button), but dim for focus
    Rectangle {
        anchors.fill: parent
        color: colors.alpha(colors.background, root.open?0.42:0)
        Behavior on color { ColorAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: {} } // consume, don't close
    }

    // centered glass card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width*0.92, 900)
        height: Math.min(parent.height*0.88, 700)
        radius: 18
        color: colors.alpha(colors.surface, 0.72)
        border.width: 1
        border.color: colors.alpha(colors.primary, 0.14)
        focus: true
        Keys.onEscapePressed: root.open = false
        Keys.onPressed: function(e){
            if(e.key===Qt.Key_Right || e.key===Qt.Key_Down || e.key===Qt.Key_PageDown) { root.nextPage(); e.accepted=true }
            else if(e.key===Qt.Key_Left || e.key===Qt.Key_Up || e.key===Qt.Key_PageUp) { root.prevPage(); e.accepted=true }
            else if(e.key===Qt.Key_Plus || e.key===Qt.Key_Equal) { root.zoomIn(); e.accepted=true }
            else if(e.key===Qt.Key_Minus) { root.zoomOut(); e.accepted=true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            // header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: "󰈦  PDF VIEWER"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                Text {
                    text: pdfPath ? pdfPath.split("/").pop() : "No file"
                    color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; elide: Text.ElideMiddle; Layout.fillWidth: true
                }
                // open field + button (simplest file picker — type path)
                Rectangle {
                    Layout.preferredWidth: 260; height: 32; radius: 8
                    color: colors.alpha(colors.surface, 0.85)
                    border.width:1; border.color: pathField.activeFocus ? colors.alpha(colors.primary,0.5) : colors.alpha(colors.outline,0.14)
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 6; spacing: 6
                        TextField {
                            id: pathField
                            Layout.fillWidth: true
                            placeholderText: "/path/to/file.pdf"
                            placeholderTextColor: colors.alpha(colors.outline,0.45)
                            text: root.pdfPath
                            color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9
                            background: null
                            selectByMouse: true
                            onAccepted: { root.pdfPath = text.trim(); root.loadPdf() }
                        }
                        Rectangle {
                            width: 46; height: 22; radius: 6
                            color: openMa.containsMouse ? colors.alpha(colors.primary,0.22) : colors.alpha(colors.primary,0.14)
                            Text { anchors.centerIn: parent; text: "Open"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                            MouseArea { id: openMa; anchors.fill: parent; hoverEnabled:true; onClicked: { root.pdfPath = pathField.text.trim(); root.loadPdf() } }
                        }
                    }
                }
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: closeMa.containsMouse ? colors.alpha(colors.surfaceVariant,0.6) : colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: colors.alpha(colors.outline,0.15)
                    Text { anchors.centerIn: parent; text: "󰅖"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.open=false }
                }
            }

            Rectangle { Layout.fillWidth: true; height:1; color: colors.alpha(colors.outline,0.12) }

            // page view — Image, glass inner panel
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                radius: 12
                color: colors.alpha(colors.background, 0.55)
                border.width:1; border.color: colors.alpha(colors.outline,0.10)
                clip: true

                // placeholder when no pdf
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !pdfPath || errorMsg
                    spacing: 8
                    Text { text: errorMsg || "Enter a PDF path above or:  quickshell -p ~/.config/quickshell ipc call pdfviewer open /path.pdf"; color: errorMsg ? colors.error : colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 10; wrapMode: Text.Wrap; Layout.maximumWidth: 520; horizontalAlignment: Text.AlignHCenter }
                    Text { visible: !errorMsg; text: "Try:  " + Quickshell.env("HOME") + "/projects/Portfolio/src/assets/OLADELE USMAN.pdf"; color: colors.alpha(colors.outline,0.45); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: pageImage && !errorMsg
                    clip: true
                    Image {
                        id: pageImg
                        anchors.fill: parent
                        source: root.pageImage
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        asynchronous: true
                        // debug
                        onStatusChanged: if(status===Image.Error) console.log("[PdfViewer] Image error:", source, "status", status)
                        onSourceChanged: console.log("[PdfViewer] source ->", source)
                    }
                }

                // loading spinner
                Rectangle {
                    anchors.centerIn: parent
                    width: 80; height: 28; radius: 14
                    visible: root.loading
                    color: colors.alpha(colors.surface, 0.85)
                    border.width:1; border.color: colors.alpha(colors.primary,0.2)
                    RowLayout { anchors.centerIn: parent; spacing: 6; Text { text: ""; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; RotationAnimation on rotation { running: root.loading; loops: Animation.Infinite; from:0; to:360; duration:700 } } Text { text: "Rendering…"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 9 } }
                }
            }

            // footer — nav + page indicator + zoom
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Rectangle {
                    width: 36; height: 32; radius: 8
                    color: (currentPage>1 && !loading) ? (prevMa.containsMouse?colors.alpha(colors.primary,0.22):colors.alpha(colors.surface,0.6)) : colors.alpha(colors.surfaceVariant,0.3)
                    border.width:1; border.color: colors.alpha(colors.outline,0.12)
                    enabled: currentPage>1 && !loading
                    Text { anchors.centerIn: parent; text: "󰒮"; color: (currentPage>1)?colors.foreground:colors.alpha(colors.outline,0.4); font.family:"FiraCode Nerd Font"; font.pixelSize: 14 }
                    MouseArea { id: prevMa; anchors.fill: parent; hoverEnabled:true; enabled: currentPage>1 && !loading; onClicked: root.prevPage() }
                }
                Rectangle {
                    Layout.preferredWidth: 110; height: 32; radius: 8
                    color: colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: colors.alpha(colors.outline,0.12)
                    Text { anchors.centerIn: parent; text: totalPages ? currentPage+" / "+totalPages : "— / —"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold }
                }
                Rectangle {
                    width: 36; height: 32; radius: 8
                    color: (currentPage<totalPages && !loading) ? (nextMa.containsMouse?colors.alpha(colors.primary,0.22):colors.alpha(colors.surface,0.6)) : colors.alpha(colors.surfaceVariant,0.3)
                    border.width:1; border.color: colors.alpha(colors.outline,0.12)
                    enabled: currentPage<totalPages && !loading
                    Text { anchors.centerIn: parent; text: "󰒭"; color: (currentPage<totalPages)?colors.foreground:colors.alpha(colors.outline,0.4); font.family:"FiraCode Nerd Font"; font.pixelSize: 14 }
                    MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled:true; enabled: currentPage<totalPages && !loading; onClicked: root.nextPage() }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: zoomMa.containsMouse?colors.alpha(colors.surfaceVariant,0.5):colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: colors.alpha(colors.outline,0.12)
                    Text { anchors.centerIn: parent; text: "󰍉"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: zoomMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.zoomOut() }
                }
                Text { text: Math.round(zoom*100)+"%"; color: colors.alpha(colors.outline,0.7); font.family:"FiraCode Nerd Font"; font.pixelSize: 9; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignHCenter }
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: zoomPMa.containsMouse?colors.alpha(colors.surfaceVariant,0.5):colors.alpha(colors.surface,0.6)
                    border.width:1; border.color: colors.alpha(colors.outline,0.12)
                    Text { anchors.centerIn: parent; text: "󰍈"; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 12 }
                    MouseArea { id: zoomPMa; anchors.fill: parent; hoverEnabled:true; onClicked: root.zoomIn() }
                }
                Text { text: "←→ navigate • +/- zoom • Esc close"; color: colors.alpha(colors.outline,0.45); font.family:"FiraCode Nerd Font"; font.pixelSize: 7 }
            }
        }
    }
}
