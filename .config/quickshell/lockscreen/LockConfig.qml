import Quickshell
import Quickshell.Io
import QtQuick

// LockConfig — every non-visual path and user option. Paths are derived from
// XDG variables; the only on-disk config is lockscreen.json next to this file.
QtObject {
    id: root

    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
        || ((Quickshell.env("HOME") || "") + "/.config")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || ((Quickshell.env("HOME") || "") + "/.cache")

    readonly property string configPath: root.configHome + "/quickshell/lockscreen/lockscreen.json"

    // ── defaults (all XDG-derived) ────────────────────────────────────────
    property string quotePath: root.configHome + "/hypr/scripts/quotes.txt"
    property string wallpaperPath: root.configHome + "/theme/current/background"
    property string backgroundSource: "wallpaper"   // wallpaper | screenshot
    property string screenshotPath: ""
    property string weatherPlace: ""
    property real weatherLatitude: NaN
    property real weatherLongitude: NaN
    property string pamDirectory: root.configHome + "/quickshell/lockscreen/pam"
    property string pamService: "quickshell-lock"

    readonly property string lyricsCacheDir: root.cacheHome + "/quickshell/lockscreen/lyrics"
    readonly property string weatherCachePath: root.cacheHome + "/quickshell/lockscreen/weather.json"

    readonly property bool weatherConfigured: !isNaN(root.weatherLatitude)
        && !isNaN(root.weatherLongitude) && root.weatherPlace !== ""

    property bool loaded: false

    function apply(raw) {
        try {
            var d = JSON.parse(raw)
            if (!d || typeof d !== "object") return
            if (d.quotes) root.quotePath = String(d.quotes)
            if (d.wallpaper) root.wallpaperPath = String(d.wallpaper)
            if (d.background) root.backgroundSource = String(d.background)
            if (d.screenshot) root.screenshotPath = String(d.screenshot)
            if (d.weather && typeof d.weather === "object") {
                if (d.weather.latitude !== undefined) root.weatherLatitude = Number(d.weather.latitude)
                if (d.weather.longitude !== undefined) root.weatherLongitude = Number(d.weather.longitude)
                if (d.weather.place !== undefined) root.weatherPlace = String(d.weather.place)
            }
            if (d.pam && typeof d.pam === "object") {
                if (d.pam.directory) root.pamDirectory = String(d.pam.directory)
                if (d.pam.service) root.pamService = String(d.pam.service)
            }
        } catch (e) {
            console.log("lockscreen: bad lockscreen.json:", e)
        }
    }

    property FileView configView: FileView {
        path: root.configPath
        printErrors: false
        onLoaded: {
            root.apply(text())
            root.loaded = true
        }
        onLoadFailed: root.loaded = true
    }
}