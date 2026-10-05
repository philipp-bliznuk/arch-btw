pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather state: bin/qs-weather writes ~/.local/state/qs/weather.json
// (open-meteo, location from weather-location.json or IP). This watches the
// file, refreshes on a timer and maps WMO codes to Nerd Font glyphs.
Singleton {
    id: root

    property var data: ({})
    readonly property bool ready: data.current !== undefined
    readonly property string name: data.name || ""
    readonly property var current: data.current || ({})
    readonly property var daily: data.daily || ({})
    readonly property bool imperial: Settings.get("weatherUnit") === "imperial"
    readonly property string unit: imperial ? "°F" : "°C"
    property bool busy: false

    function temp(c) {
        if (c === undefined || c === null)
            return "-";
        return Math.round(imperial ? c * 9 / 5 + 32 : c) + "°";
    }

    function wind(kmh) {
        if (kmh === undefined || kmh === null)
            return "-";
        return imperial ? Math.round(kmh / 1.609) + " mph" : Math.round(kmh) + " km/h";
    }

    function glyph(code, isDay) {
        const day = isDay === undefined ? true : !!isDay;
        if (code === 0)
            return day ? Icons.wSunny : Icons.wNight;
        if (code <= 2)
            return day ? Icons.wPartly : Icons.wNightPartly;
        if (code === 3)
            return Icons.wCloudy;
        if (code <= 48)
            return Icons.wFog;
        if (code <= 57 || (code >= 80 && code <= 82))
            return Icons.wRainy;
        if (code <= 65)
            return code >= 63 ? Icons.wPouring : Icons.wRainy;
        if (code <= 67)
            return Icons.wSnowyRainy;
        if (code <= 77 || code === 85 || code === 86)
            return Icons.wSnowy;
        if (code >= 95)
            return Icons.wLightning;
        return Icons.wCloudy;
    }

    function describe(code) {
        if (code === 0)
            return "Clear";
        if (code <= 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code <= 48)
            return "Fog";
        if (code <= 57)
            return "Drizzle";
        if (code <= 67)
            return "Rain";
        if (code <= 77)
            return "Snow";
        if (code <= 82)
            return "Showers";
        if (code <= 86)
            return "Snow showers";
        return "Thunderstorm";
    }

    function refresh() {
        run(["refresh"]);
    }

    function setLocation(name) {
        run(["set", name]);
    }

    function clearLocation() {
        run(["clear"]);
    }

    function run(args) {
        busy = true;
        proc.command = [Util.bin("qs-weather")].concat(args);
        proc.running = true;
    }

    Process {
        id: proc
        onExited: root.busy = false // qmllint disable signal-handler-parameters
    }

    FileView {
        path: Util.stateDir + "/weather.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text());
            } catch (e) {
                root.data = {};
            }
        }
    }

    Timer {
        interval: Math.max(1, Settings.get("weatherRefreshMinutes")) * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
