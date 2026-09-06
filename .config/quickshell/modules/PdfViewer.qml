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
    // ── library: cached pdf list, scanned once, stats per file ──
    property var library: []
    property bool libReady: false
    property bool scanning: false
    property string libQuery: ""
    property bool libFavOnly: false
    property string libSort: "recent" // recent | reads | az
    readonly property string libPath: Quickshell.env("HOME") + "/.local/state/quickshell/pdf-library.json"

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
        function open(path: string): void { root.pdfPath = path; root.open = true; root.recordRead(path); root.loadPdf() }
        function close(): void { root.open = false }
    }

    function libSave(){
        if(!libReady) return
        saveProc.command = ["sh","-c","mkdir -p '"+Quickshell.env("HOME")+"/.local/state/quickshell' && echo '"+Qt.btoa(JSON.stringify({files: root.library}))+"' | base64 -d > '"+root.libPath+"'"]
        saveProc.running = true
    }
    function libEntry(path){
        for(var i=0;i<root.library.length;i++) if(root.library[i].path===path) return root.library[i]
        return null
    }
    function recordRead(path){
        if(!path || !libReady) return
        var e = libEntry(path)
        if(e){ e.reads = (e.reads||0)+1; e.last = Date.now(); root.libraryChanged(); libSave() }
    }
    function toggleFav(path){
        var e = libEntry(path)
        if(e){ e.fav = !e.fav; root.libraryChanged(); libSave() }
    }
    function libRows(){
        var q = root.libQuery.toLowerCase()
        var rows = root.library.filter(function(e){
            if(root.libFavOnly && !e.fav) return false
            if(q && (e.title||"").toLowerCase().indexOf(q)===-1 && (e.path||"").toLowerCase().indexOf(q)===-1) return false
            return true
        })
        var by = root.libSort
        rows.sort(function(a,b){
            if(by==="reads") return (b.reads||0)-(a.reads||0)
            if(by==="az") return (a.title||"").localeCompare(b.title||"")
            return (b.last||0)-(a.last||0)
        })
        return rows
    }
    function libRescan(){ if(!root.scanning){ root.scanning = true; scanProc.running = true } }

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
    Process { id: saveProc }
    FileView {
        id: libView
        path: root.libPath
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if(d && d.files){ root.library = d.files; root.libReady = true; return }
            } catch(e) {}
            root.libRescan() // first open ever (or corrupt cache): scan once
        }
        onLoadFailed: root.libRescan()
    }
    Process {
        id: scanProc
        command: ["sh","-c","find '"+Quickshell.env("HOME")+"' -maxdepth 4 -iname '*.pdf' -not -path '*/.*' 2>/dev/null | head -n 500"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var old = {}
                for(var i=0;i<root.library.length;i++) old[root.library[i].path] = root.library[i]
                var files = []
                var lines = text.split("\n")
                for(var j=0;j<lines.length;j++){
                    var p = lines[j].trim()
                    if(!p) continue
                    if(old[p]){ files.push(old[p]); continue }
                    var parts = p.split("/")
                    files.push({path: p, title: parts[parts.length-1].replace(/\.pdf$/i,""), folder: parts.length>1?parts[parts.length-2]:"~", reads: 0, last: 0, fav: false})
                }
                root.library = files
                root.libReady = true
                root.scanning = false
                root.libSave()
            }
        }
    }

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
                            onAccepted: { root.pdfPath = text.trim(); root.recordRead(root.pdfPath); root.loadPdf() }
                        }
                        Rectangle {
                            width: 46; height: 22; radius: 6
                            color: openMa.containsMouse ? colors.alpha(colors.primary,0.22) : colors.alpha(colors.primary,0.14)
                            Text { anchors.centerIn: parent; text: "Open"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                            MouseArea { id: openMa; anchors.fill: parent; hoverEnabled:true; onClicked: { root.pdfPath = pathField.text.trim(); root.recordRead(root.pdfPath); root.loadPdf() } }
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

                // library — cached list, scan-once, favorites + most-read
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: !pdfPath
                    spacing: 8
                    Text { visible: !!errorMsg; text: errorMsg; color: colors.error; font.family:"FiraCode Nerd Font"; font.pixelSize: 9 }
                    // search + rescan
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Rectangle {
                            Layout.fillWidth: true; height: 34; radius: 9
                            color: colors.alpha(colors.surface, 0.85)
                            border.width: 1; border.color: libSearch.activeFocus ? colors.alpha(colors.primary,0.5) : colors.alpha(colors.outline,0.14)
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                                Text { text: ""; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 11 }
                                TextField { id: libSearch; Layout.fillWidth: true; placeholderText: "Search library…"; placeholderTextColor: colors.alpha(colors.outline,0.45); color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; background: null; selectByMouse: true; onTextChanged: root.libQuery = text }
                            }
                        }
                        Rectangle { width: 70; height: 34; radius: 9; color: rescanMa.containsMouse?colors.alpha(colors.primary,0.22):colors.alpha(colors.primary,0.12); border.width:1; border.color: colors.alpha(colors.primary,0.3)
                            Text { anchors.centerIn: parent; text: root.scanning ? "…" : "⟳"; color: colors.primary; font.family:"FiraCode Nerd Font"; font.pixelSize: 11; font.weight: Font.Bold }
                            MouseArea { id: rescanMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.libRescan() } }
                    }
                    // chips: ★ filter + sorts
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Repeater { model: [{k:"all",t:"All"},{k:"fav",t:"★"},{k:"recent",t:"Recent"},{k:"reads",t:"Most read"},{k:"az",t:"A–Z"}]
                            property bool chipActive: modelData.k==="fav" ? root.libFavOnly : (modelData.k==="all" ? (!root.libFavOnly && root.libSort==="recent") : root.libSort===modelData.k)
                            Rectangle { width: 72; height: 26; radius: 13
                                color: chipActive ? colors.alpha(colors.primary,0.25) : (chipMa.containsMouse?colors.alpha(colors.surfaceVariant,0.5):colors.alpha(colors.surface,0.5))
                                border.width: 1; border.color: colors.alpha(colors.outline,0.12)
                                Text { anchors.centerIn: parent; text: modelData.t; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 8; font.weight: Font.Bold }
                                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; onClicked: { if(modelData.k==="fav") root.libFavOnly=!root.libFavOnly; else if(modelData.k!=="all") root.libSort=modelData.k; else { root.libFavOnly=false; root.libSort="recent" } } }
                            }
                        }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignRight; text: root.scanning ? "Scanning…" : (root.library.length+" pdfs"); color: colors.alpha(colors.outline,0.55); font.family:"FiraCode Nerd Font"; font.pixelSize: 8 }
                    }
                    // rows
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 4
                        model: root.libRows()
                        delegate: Rectangle {
                            width: ListView.view.width; height: 44; radius: 9
                            color: rowMa.containsMouse ? colors.alpha(colors.primary,0.12) : colors.alpha(colors.surface,0.45)
                            border.width: 1; border.color: colors.alpha(colors.outline,0.10)
                            RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 8
                                Text { text: modelData.fav ? "★" : "☆"; color: modelData.fav ? colors.primary : colors.alpha(colors.outline,0.5); font.family:"FiraCode Nerd Font"; font.pixelSize: 13
                                    MouseArea { anchors.fill: parent; onClicked: root.toggleFav(modelData.path) } }
                                ColumnLayout { Layout.fillWidth: true; spacing: 1
                                    Text { text: modelData.title; color: colors.foreground; font.family:"FiraCode Nerd Font"; font.pixelSize: 10; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: (modelData.folder||"") + ((modelData.reads||0)>0 ? "  •  "+modelData.reads+"× read" : ""); color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 8; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Text { text: "⧉"; color: colors.alpha(colors.outline,0.6); font.family:"FiraCode Nerd Font"; font.pixelSize: 12
                                    MouseArea { anchors.fill: parent; onClicked: Quickshell.execDetached(["zathura", modelData.path]) } }
                            }
                            MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.pdfPath = modelData.path; root.recordRead(modelData.path); root.loadPdf() } }
                        }
                    }
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
