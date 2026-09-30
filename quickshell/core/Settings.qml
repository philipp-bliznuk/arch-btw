pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Small persisted prefs (~/.local/state/qs/settings.json). Flat key → value;
// defaults live here, `set()` writes atomically. Not for secrets.
Singleton {
    id: root

    readonly property var defaults: ({
            weekStartMonday: true,
            batteryPercent: true,
            powerSaverOnBattery: true,
            weatherUnit: "metric",
            weatherRefreshMinutes: 15
        })
    property var data: ({})

    function get(key) {
        return data[key] !== undefined ? data[key] : defaults[key];
    }

    function set(key, value) {
        const next = Object.assign({}, data);
        next[key] = value;
        data = next;
        file.setText(JSON.stringify(next, null, 2));
    }

    FileView {
        id: file
        path: Util.stateDir + "/settings.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object")
                    root.data = parsed;
            } catch (e) {
                console.warn("settings: bad settings.json, using defaults");
            }
        }
    }
}
