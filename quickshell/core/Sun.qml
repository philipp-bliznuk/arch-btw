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
    readonly property bool auto: Settings.get("nightLightAuto") === true

    // One binding computes everything from a single `now` snapshot. Separate
    // bindings re-evaluated in arbitrary order and briefly compared the new
    // date against yesterday's sunset after a resume, flipping isNight.
    readonly property var day: compute(now, Weather.daily)
    readonly property bool known: day.known
    readonly property date sunrise: day.sunrise
    readonly property date sunset: day.sunset
    readonly property bool isNight: day.isNight

    function compute(at, daily) {
        const none = {
            known: false,
            sunrise: new Date(0),
            sunset: new Date(0),
            isNight: false
        };
        if (!daily.time || !daily.sunrise || !daily.sunset)
            return none;
        const i = daily.time.indexOf(Qt.formatDate(at, "yyyy-MM-dd"));
        if (i < 0)
            return none;
        const sunrise = new Date(daily.sunrise[i]);
        const sunset = new Date(daily.sunset[i]);
        return {
            known: true,
            sunrise,
            sunset,
            isNight: at < sunrise || at >= sunset
        };
    }

    function apply() {
        if (!auto)
            return;
        if (Toggles.has("nightlight") !== isNight)
            Toggles.set("nightlight", isNight);
    }

    // Every input change only re-arms `settle`; apply() runs once the state
    // has been stable for 2 s (startup flag scan and weather load in flight,
    // weather file rewritten, clock jump on resume).
    onIsNightChanged: settle.restart()
    onAutoChanged: settle.restart()
    onKnownChanged: {
        Qt.callLater(() => root.now = new Date());
        settle.restart();
    }

    Timer {
        id: settle
        interval: 2000
        running: true
        onTriggered: root.apply()
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
