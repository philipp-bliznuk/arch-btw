pragma Singleton
import QtQuick
import Quickshell

// Day/night from the open-meteo sunrise/sunset that bin/qs-weather stores in
// weather.json. Drives the automatic night light: on at sunset, off at
// sunrise (Settings.nightLightAuto). A manual toggle holds until the next
// transition. Without a forecast for today (stale file after a long sleep,
// no network) the day is unknown and the night light is off.
Singleton {
    id: root

    property date now: new Date()
    readonly property var today: pick(Weather.daily)
    readonly property bool known: today !== null
    readonly property date sunrise: known ? new Date(today.sunrise) : new Date(0)
    readonly property date sunset: known ? new Date(today.sunset) : new Date(0)
    readonly property bool isNight: known && (now < sunrise || now >= sunset)
    readonly property bool auto: Settings.get("nightLightAuto") === true

    function pick(daily) {
        if (!daily.time || !daily.sunrise || !daily.sunset)
            return null;
        const i = daily.time.indexOf(Qt.formatDate(now, "yyyy-MM-dd"));
        if (i < 0)
            return null;
        return {
            sunrise: daily.sunrise[i],
            sunset: daily.sunset[i]
        };
    }

    function apply() {
        if (!auto)
            return;
        if (Toggles.has("nightlight") !== isNight)
            Toggles.set("nightlight", isNight);
    }

    // Applied once 2 s after startup (Toggles flag scan and the weather file
    // load are in flight) and 2 s after every change of `known`; isNight
    // transitions apply at once after that.
    property bool settled: false

    onIsNightChanged: if (settled) apply()
    onAutoChanged: apply()
    onKnownChanged: {
        Qt.callLater(() => root.now = new Date());
        settle.restart();
    }

    Timer {
        id: settle
        interval: 2000
        running: true
        onTriggered: {
            root.settled = true;
            root.apply();
        }
    }

    // Wake only at the next sunrise, sunset or midnight (day rollover).
    readonly property int wait: {
        const t = now.getTime();
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime();
        const marks = [sunrise.getTime(), sunset.getTime(), midnight].filter(m => m > t);
        return Math.min.apply(null, marks) - t + 1000;
    }

    Timer {
        id: tick
        interval: root.wait
        running: true
        onTriggered: root.wake()
    }

    // Re-read the clock; a changed `wait` re-arms the timer.
    function wake() {
        now = new Date();
        tick.restart();
    }
}
