import Quickshell
import Quickshell.Io
import QtQuick

// WeatherSource — Open-Meteo current conditions. Coordinates and the human
// label come from lockscreen.json; nothing here is location-specific.
// On any failure the last cached response stays visible, otherwise the
// component shows its empty state. Network failures are silent.
QtObject {
    id: root

    property var config

    property string place: root.config ? root.config.weatherPlace : ""
    property real temperature: NaN
    property real apparent: NaN
    property real humidity: NaN
    property real wind: NaN
    property real high: NaN
    property real low: NaN
    property int code: -1
    property bool isDay: true
    property bool ready: false
    property bool stale: false
    property bool loading: false

    readonly property bool configured: root.config ? root.config.weatherConfigured : false
    readonly property string condition: root.describe(root.code)

    function describe(c) {
        if (c === 0) return "Clear"
        if (c === 1) return "Mostly clear"
        if (c === 2) return "Partly cloudy"
        if (c === 3) return "Overcast"
        if (c === 45 || c === 48) return "Fog"
        if (c >= 51 && c <= 57) return "Drizzle"
        if (c >= 61 && c <= 67) return "Rain"
        if (c >= 71 && c <= 77) return "Snow"
        if (c >= 80 && c <= 82) return "Showers"
        if (c >= 85 && c <= 86) return "Snow showers"
        if (c >= 95) return "Thunderstorm"
        return ""
    }

    function consume(raw, fromCache) {
        var d = null
        try {
            d = JSON.parse(raw)
        } catch (e) {
            return false
        }
        if (!d || !d.current) return false
        var cur = d.current
        root.temperature = Number(cur.temperature_2m)
        root.apparent = Number(cur.apparent_temperature)
        root.humidity = Number(cur.relative_humidity_2m)
        root.wind = Number(cur.wind_speed_10m)
        root.code = Number(cur.weather_code)
        root.isDay = Number(cur.is_day) === 1
        if (d.daily) {
            root.high = Number(d.daily.temperature_2m_max[0])
            root.low = Number(d.daily.temperature_2m_min[0])
        }
        root.ready = true
        root.stale = !!fromCache
        return true
    }

    function fetchNow() {
        if (!root.configured || root.loading) return
        root.loading = true
        var url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root.config.weatherLatitude
            + "&longitude=" + root.config.weatherLongitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&timezone=auto&forecast_days=1"
        fetchProc.command = ["curl", "-sL", "--max-time", "10", url]
        fetchProc.running = true
    }

    property Process fetchProc: Process {
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var raw = text
                if (root.consume(raw, false)) {
                    if (root.cacheView.path !== "")
                        root.cacheView.setText(raw)
                }
            }
        }
        onExited: root.loading = false
    }

    property FileView cacheView: FileView {
        path: root.config ? root.config.weatherCachePath : ""
        printErrors: false
        onLoaded: {
            if (!root.ready)
                root.consume(text(), true)
        }
    }

    property Process mkdirProc: Process {
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"", "sh", root.config ? root.config.weatherCachePath : ""]
        running: false
    }

    Component.onCompleted: {
        root.mkdirProc.running = true
        root.fetchNow()
    }
    onConfiguredChanged: if (root.configured && !root.ready) root.fetchNow()
}