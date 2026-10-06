import Quickshell
import Quickshell.Io
import QtQuick
import "components"
import "modules"

ShellRoot {
    Bar { id: mainBar }

    NowPlayingCard { colors: barPalette; hovered: mainBar.musicHover }

    // Always resident: fast-open surfaces (launcher/power), hover card,
    // PassPrompt (stateful ask/st/result IPC polled by PkgManager — never lazy-load),
    // and GitHubPoller (tiny: 2 procs + timer; keeps notify-send + cache warm
    // while GitHubDash itself stays lazy-unloaded).
    PowerMenu { colors: barPalette }
    PassPrompt { colors: barPalette }
    GitHubPoller {}
    // LockScreen PARKED (2026-10-03): quickshell WlSessionLock stranded the
    // session on first test (missing PAM respond + focus). hyprlock owns
    // locking again; revisit only with a timed auto-rescue test harness.
    // LockScreen {}

    // ---- lazy heavies: Loader + IPC proxy, zero RAM while closed ----
    // Esc/click-outside inside each panel sets its own open=false; the
    // Connections block below propagates that back out so the Loader unloads.

    // PkgManager (1467 lines, 11 Process) — pkgman + packages targets, tab shortcuts
    property bool pkgOpen: false
    property int pkgTab: 0
    IpcHandler {
        target: "pkgman"
        function toggle(): void { pkgOpen = !pkgOpen }
        function showSearch(): void { pkgShow(0) }
        function showQueue(): void { pkgShow(1) }
        function showInstalled(): void { pkgShow(2) }
        function showUpdates(): void { pkgShow(3) }
    }
    IpcHandler { target: "packages"; function toggle(): void { pkgOpen = !pkgOpen } }
    function pkgShow(t: int): void {
        pkgTab = t
        if (pkgLoader.item) { pkgLoader.item.tab = t; pkgLoader.item.open = true }
        else pkgOpen = true
    }
    Loader {
        id: pkgLoader
        active: pkgOpen
        asynchronous: true
        source: "modules/PkgManager.qml"
        onLoaded: { item.colors = barPalette; item.tab = pkgTab; item.open = true }
    }
    Connections {
        target: pkgLoader.item
        function onOpenChanged() { if (pkgLoader.item && !pkgLoader.item.open) pkgOpen = false }
    }

    // ControlCenter (974 lines) — toggle only
    property bool ccOpen: false
    IpcHandler {
        target: "controlcenter"
        // the Loader compiles async (~4s cold). A second press mid-load used
        // to flip ccOpen back off and CANCEL the load, so mashing the key
        // restarted the 4s wait every time — that was the "3 presses" bug.
        // Swallow the cancel while the first load is still in flight.
        function toggle(): void {
            if (ccOpen && ccLoader.status === Loader.Loading) return
            ccOpen = !ccOpen
        }
    }
    Loader {
        id: ccLoader
        active: true // prewarmed (~10MB): compile once at login so the first
                     // SUPER ALT P only flips `open` instead of waiting ~4s
        asynchronous: true
        source: "modules/ControlCenter.qml"
        onLoaded: { item.colors = barPalette; item.open = ccOpen }
    }
    // shell -> item: open/close without unloading (stays warm)
    onCcOpenChanged: { if (ccLoader.item) ccLoader.item.open = ccOpen }
    // item -> shell: Esc / click-outside closes propagate back out
    Connections {
        target: ccLoader.item
        function onOpenChanged() { if (ccLoader.item && !ccLoader.item.open) ccOpen = false }
    }

    // Monitors — small live monitor panel (scale/DPI, rotate, status)
    property bool monOpen: false
    IpcHandler { target: "monitors"; function toggle(): void { monOpen = !monOpen } }
    Loader {
        id: monLoader
        active: monOpen
        asynchronous: true
        source: "modules/MonitorSettings.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    Connections {
        target: monLoader.item
        function onOpenChanged() { if (monLoader.item && !monLoader.item.open) monOpen = false }
    }

    // Pomodoro — focus timer plugin (app menu qs-pomodoro). The module was
    // never instantiated so its own toggle target never registered.
    property bool pomOpen: false
    IpcHandler {
        target: "pomodoro"
        function toggle(): void {
            if (pomOpen && pomLoader.status === Loader.Loading) return
            pomOpen = !pomOpen
        }
        function close(): void { pomOpen = false }
    }
    Loader {
        id: pomLoader
        active: pomOpen
        asynchronous: true
        source: "modules/Pomodoro.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    onPomOpenChanged: { if (pomLoader.item) pomLoader.item.open = pomOpen }
    Connections {
        target: pomLoader.item
        function onOpenChanged() { if (pomLoader.item && !pomLoader.item.open) pomOpen = false }
    }

    // Earbuds — bluetooth headset batteries (SUPER ALT E)
    property bool ebOpen: false
    IpcHandler {
        target: "earbuds"
        // same async-load race as ControlCenter: swallow the cancel while the
        // first compile is still in flight so mashing never eats the open
        function toggle(): void {
            if (ebOpen && ebLoader.status === Loader.Loading) return
            ebOpen = !ebOpen
        }
    }
    Loader {
        id: ebLoader
        active: ebOpen
        asynchronous: true
        source: "modules/Earbuds.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    onEbOpenChanged: { if (ebLoader.item) ebLoader.item.open = ebOpen }
    Connections {
        target: ebLoader.item
        function onOpenChanged() { if (ebLoader.item && !ebLoader.item.open) ebOpen = false }
    }

    // Bluetooth manager — adapter power, scan, pair/connect/disconnect
    property bool btOpen: false
    IpcHandler {
        target: "bluetooth"
        function toggle(): void {
            if (btOpen && btLoader.status === Loader.Loading) return
            btOpen = !btOpen
        }
    }
    Loader {
        id: btLoader
        active: btOpen
        asynchronous: true
        source: "modules/Bluetooth.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    onBtOpenChanged: { if (btLoader.item) btLoader.item.open = btOpen }
    Connections {
        target: btLoader.item
        function onOpenChanged() { if (btLoader.item && !btLoader.item.open) btOpen = false }
    }

    // GitHubDash — toggle + close. Background notify + cache warming live in
    // resident GitHubPoller, so this Loader is display-only.
    property bool ghOpen: false
    IpcHandler {
        target: "github"
        function toggle(): void { ghOpen = !ghOpen }
        function close(): void { ghOpen = false }
    }
    Loader {
        id: ghLoader
        active: ghOpen
        asynchronous: true
        source: "modules/GitHubDash.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    Connections {
        target: ghLoader.item
        function onOpenChanged() { if (ghLoader.item && !ghLoader.item.open) ghOpen = false }
    }

    // Dictionary — toggle + lookup(word)
    property bool dictOpen: false
    property string dictWord: ""
    IpcHandler {
        target: "dict"
        function toggle(): void { dictOpen = !dictOpen }
        function lookup(word: string): void {
            if (dictLoader.item) dictLoader.item.lookup(word)
            else { dictWord = word; dictOpen = true }
        }
    }
    Loader {
        id: dictLoader
        active: dictOpen
        asynchronous: true
        source: "modules/Dictionary.qml"
        onLoaded: { item.colors = barPalette; if (dictWord !== "") { var w = dictWord; dictWord = ""; item.lookup(w) } else item.open = true }
    }
    Connections {
        target: dictLoader.item
        function onOpenChanged() { if (dictLoader.item && !dictLoader.item.open) dictOpen = false }
    }

    // PdfViewer — toggle + open(path) + close
    property bool pdfOpen: false
    property string pdfPath: ""
    IpcHandler {
        target: "pdfviewer"
        function toggle(): void { pdfOpen = !pdfOpen }
        function open(path: string): void {
            if (pdfLoader.item) { if (path) pdfLoader.item.openWith(path); else pdfLoader.item.open = true }
            else { if (path) pdfPath = path; pdfOpen = true }
        }
        function close(): void { pdfOpen = false }
    }
    Loader {
        id: pdfLoader
        active: pdfOpen
        asynchronous: true
        source: "modules/PdfViewer.qml"
        onLoaded: { item.colors = barPalette; if (pdfPath !== "") { var p = pdfPath; pdfPath = ""; item.openWith(p) } else item.open = true }
    }
    Connections {
        target: pdfLoader.item
        function onOpenChanged() { if (pdfLoader.item && !pdfLoader.item.open) pdfOpen = false }
    }

    // Wallshelf (300-thumb scan) — toggle only
    property bool shelfOpen: false
    IpcHandler { target: "wallshelf"; function toggle(): void { shelfOpen = !shelfOpen } }
    Loader {
        id: shelfLoader
        active: shelfOpen
        asynchronous: true
        source: "modules/Wallshelf.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    Connections {
        target: shelfLoader.item
        function onOpenChanged() { if (shelfLoader.item && !shelfLoader.item.open) shelfOpen = false }
    }

    // WorkspaceViewer — toggle only
    property bool wsvOpen: false
    IpcHandler { target: "wsview"; function toggle(): void { wsvOpen = !wsvOpen } }
    Loader {
        id: wsvLoader
        active: wsvOpen
        asynchronous: true
        source: "modules/WorkspaceViewer.qml"
        onLoaded: { item.colors = barPalette; item.open = true }
    }
    Connections {
        target: wsvLoader.item
        function onOpenChanged() { if (wsvLoader.item && !wsvLoader.item.open) wsvOpen = false }
    }

    // Grap — toggle + close + search(q)
    property bool grapOpen: false
    property string grapQ: ""
    IpcHandler {
        target: "grap"
        function toggle(): void { grapOpen = !grapOpen }
        function close(): void { grapOpen = false }
        function search(q: string): void {
            if (grapLoader.item) grapLoader.item.search(q)
            else { grapQ = q; grapOpen = true }
        }
    }
    Loader {
        id: grapLoader
        active: grapOpen
        asynchronous: true
        source: "modules/Grap.qml"
        onLoaded: { item.colors = barPalette; if (grapQ !== "") { var q = grapQ; grapQ = ""; item.search(q) } else item.open = true }
    }
    Connections {
        target: grapLoader.item
        function onOpenChanged() { if (grapLoader.item && !grapLoader.item.open) grapOpen = false }
    }

    Colors { id: barPalette }
}
