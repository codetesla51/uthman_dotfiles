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

    // ---- lazy heavies: Loader + IPC proxy, zero RAM until first used ----
    // Each loader stays compiled after its first open (warm flag) so the
    // second press is instant. A press mid-load never cancels: open wins,
    // close is swallowed until onLoaded fires. Esc/click-outside inside
    // each panel sets its own open=false; Connections propagates back out.

    // PkgManager (1467 lines, 11 Process) — pkgman + packages targets, tab shortcuts
    property bool pkgOpen: false
    property int pkgTab: 0
    IpcHandler {
        target: "pkgman"
        function toggle(): void { if (pkgOpen && pkgLoader.status === Loader.Loading) return; pkgOpen = !pkgOpen }
        function showSearch(): void { pkgShow(0) }
        function showQueue(): void { pkgShow(1) }
        function showInstalled(): void { pkgShow(2) }
        function showUpdates(): void { pkgShow(3) }
    }
    IpcHandler { target: "packages"; function toggle(): void { if (pkgOpen && pkgLoader.status === Loader.Loading) return; pkgOpen = !pkgOpen } }
    function pkgShow(t: int): void {
        pkgTab = t
        if (pkgLoader.item) { pkgLoader.item.tab = t; pkgLoader.item.open = true }
        else pkgOpen = true
    }
    Loader {
        id: pkgLoader
        active: pkgOpen || pkgWarm
        asynchronous: true
        source: "modules/PkgManager.qml"
        onLoaded: { pkgWarm = true; item.colors = barPalette; item.tab = pkgTab; item.open = true }
    }
    property bool pkgWarm: false
    onPkgOpenChanged: { if (pkgLoader.item) pkgLoader.item.open = pkgOpen }
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
    IpcHandler { target: "monitors"; function toggle(): void { if (monOpen && monLoader.status === Loader.Loading) return; monOpen = !monOpen } }
    Loader {
        id: monLoader
        active: monOpen || monWarm
        asynchronous: true
        source: "modules/MonitorSettings.qml"
        onLoaded: { monWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool monWarm: false
    onMonOpenChanged: { if (monLoader.item) monLoader.item.open = monOpen }
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
        function close(): void { if (pomOpen && pomLoader.status === Loader.Loading) return; pomOpen = false }
    }
    Loader {
        id: pomLoader
        active: pomOpen || pomWarm
        asynchronous: true
        source: "modules/Pomodoro.qml"
        onLoaded: { pomWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool pomWarm: false
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
        active: ebOpen || ebWarm
        asynchronous: true
        source: "modules/Earbuds.qml"
        onLoaded: { ebWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool ebWarm: false
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
        active: btOpen || btWarm
        asynchronous: true
        source: "modules/Bluetooth.qml"
        onLoaded: { btWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool btWarm: false
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
        function toggle(): void { if (ghOpen && ghLoader.status === Loader.Loading) return; ghOpen = !ghOpen }
        function close(): void { if (ghOpen && ghLoader.status === Loader.Loading) return; ghOpen = false }
    }
    Loader {
        id: ghLoader
        active: ghOpen || ghWarm
        asynchronous: true
        source: "modules/GitHubDash.qml"
        onLoaded: { ghWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool ghWarm: false
    onGhOpenChanged: { if (ghLoader.item) ghLoader.item.open = ghOpen }
    Connections {
        target: ghLoader.item
        function onOpenChanged() { if (ghLoader.item && !ghLoader.item.open) ghOpen = false }
    }

    // Dictionary — toggle + lookup(word)
    property bool dictOpen: false
    property string dictWord: ""
    IpcHandler {
        target: "dict"
        function toggle(): void { if (dictOpen && dictLoader.status === Loader.Loading) return; dictOpen = !dictOpen }
        function lookup(word: string): void {
            if (dictLoader.item) dictLoader.item.lookup(word)
            else { dictWord = word; dictOpen = true }
        }
    }
    Loader {
        id: dictLoader
        active: dictOpen || dictWarm
        asynchronous: true
        source: "modules/Dictionary.qml"
        onLoaded: { dictWarm = true; item.colors = barPalette; if (dictWord !== "") { var w = dictWord; dictWord = ""; item.lookup(w) } else item.open = true }
    }
    property bool dictWarm: false
    onDictOpenChanged: { if (dictLoader.item) dictLoader.item.open = dictOpen }
    Connections {
        target: dictLoader.item
        function onOpenChanged() { if (dictLoader.item && !dictLoader.item.open) dictOpen = false }
    }

    // PdfViewer — toggle + open(path) + close
    property bool pdfOpen: false
    property string pdfPath: ""
    IpcHandler {
        target: "pdfviewer"
        function toggle(): void { if (pdfOpen && pdfLoader.status === Loader.Loading) return; pdfOpen = !pdfOpen }
        function open(path: string): void {
            if (pdfLoader.item) { if (path) pdfLoader.item.openWith(path); else pdfLoader.item.open = true }
            else { if (path) pdfPath = path; pdfOpen = true }
        }
        function close(): void { if (pdfOpen && pdfLoader.status === Loader.Loading) return; pdfOpen = false }
    }
    Loader {
        id: pdfLoader
        active: pdfOpen || pdfWarm
        asynchronous: true
        source: "modules/PdfViewer.qml"
        onLoaded: { pdfWarm = true; item.colors = barPalette; if (pdfPath !== "") { var p = pdfPath; pdfPath = ""; item.openWith(p) } else item.open = true }
    }
    property bool pdfWarm: false
    onPdfOpenChanged: { if (pdfLoader.item) pdfLoader.item.open = pdfOpen }
    Connections {
        target: pdfLoader.item
        function onOpenChanged() { if (pdfLoader.item && !pdfLoader.item.open) pdfOpen = false }
    }

    // Wallshelf (300-thumb scan) — toggle only
    property bool shelfOpen: false
    IpcHandler { target: "wallshelf"; function toggle(): void { if (shelfOpen && shelfLoader.status === Loader.Loading) return; shelfOpen = !shelfOpen } }
    Loader {
        id: shelfLoader
        active: shelfOpen || shelfWarm
        asynchronous: true
        source: "modules/Wallshelf.qml"
        onLoaded: { shelfWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool shelfWarm: false
    onShelfOpenChanged: { if (shelfLoader.item) shelfLoader.item.open = shelfOpen }
    Connections {
        target: shelfLoader.item
        function onOpenChanged() { if (shelfLoader.item && !shelfLoader.item.open) shelfOpen = false }
    }

    // WorkspaceViewer — toggle only
    property bool wsvOpen: false
    IpcHandler { target: "wsview"; function toggle(): void { if (wsvOpen && wsvLoader.status === Loader.Loading) return; wsvOpen = !wsvOpen } }
    Loader {
        id: wsvLoader
        active: wsvOpen || wsvWarm
        asynchronous: true
        source: "modules/WorkspaceViewer.qml"
        onLoaded: { wsvWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool wsvWarm: false
    onWsvOpenChanged: { if (wsvLoader.item) wsvLoader.item.open = wsvOpen }
    Connections {
        target: wsvLoader.item
        function onOpenChanged() { if (wsvLoader.item && !wsvLoader.item.open) wsvOpen = false }
    }

    // Grap — toggle + close + search(q)
    property bool grapOpen: false
    property string grapQ: ""
    IpcHandler {
        target: "grap"
        function toggle(): void { if (grapOpen && grapLoader.status === Loader.Loading) return; grapOpen = !grapOpen }
        function close(): void { if (grapOpen && grapLoader.status === Loader.Loading) return; grapOpen = false }
        function search(q: string): void {
            if (grapLoader.item) grapLoader.item.search(q)
            else { grapQ = q; grapOpen = true }
        }
    }
    Loader {
        id: grapLoader
        active: grapOpen || grapWarm
        asynchronous: true
        source: "modules/Grap.qml"
        onLoaded: { grapWarm = true; item.colors = barPalette; if (grapQ !== "") { var q = grapQ; grapQ = ""; item.search(q) } else item.open = true }
    }
    property bool grapWarm: false
    onGrapOpenChanged: { if (grapLoader.item) grapLoader.item.open = grapOpen }
    Connections {
        target: grapLoader.item
        function onOpenChanged() { if (grapLoader.item && !grapLoader.item.open) grapOpen = false }
    }

    // QuickNotes — scratch idea capture (launcher qs-notes). Same orphan
    // story as Pomodoro: module owned its own target but nothing
    // instantiated it, so the launcher entry hit "Target not found".
    property bool notesOpen: false
    IpcHandler {
        target: "notes"
        function toggle(): void {
            if (notesOpen && notesLoader.status === Loader.Loading) return
            notesOpen = !notesOpen
        }
        function close(): void { if (notesOpen && notesLoader.status === Loader.Loading) return; notesOpen = false }
    }
    Loader {
        id: notesLoader
        active: notesOpen || notesWarm
        asynchronous: true
        source: "modules/QuickNotes.qml"
        onLoaded: { notesWarm = true; item.colors = barPalette; item.open = true }
    }
    property bool notesWarm: false
    onNotesOpenChanged: { if (notesLoader.item) notesLoader.item.open = notesOpen }
    Connections {
        target: notesLoader.item
        function onOpenChanged() { if (notesLoader.item && !notesLoader.item.open) notesOpen = false }
    }

    Colors { id: barPalette }
}
