pragma Singleton
import QtQuick

// Nerd Font Material Design glyphs (nf-md-*).
QtObject {
    function g(cp) {
        return String.fromCodePoint(cp);
    }

    // Launcher sections
    readonly property string apps: g(0xF003B)
    readonly property string power: g(0xF0425)
    readonly property string keyboard: g(0xF030C)
    readonly property string console: g(0xF018D)
    readonly property string camera: g(0xF0100)
    readonly property string toggle: g(0xF0521)
    readonly property string cog: g(0xF0493)
    readonly property string update: g(0xF06B0)
    readonly property string book: g(0xF00BA)
    readonly property string calc: g(0xF00EC)
    readonly property string pencil: g(0xF03EB)
    readonly property string web: g(0xF059F)
    readonly property string crop: g(0xF019E)
    readonly property string monitor: g(0xF0379)
    readonly property string bluetooth: g(0xF00AF)
    readonly property string eye: g(0xF0208)
    readonly property string bellOff: g(0xF009B)
    readonly property string chevronRight: g(0xF0142)

    // System actions
    readonly property string lock: g(0xF033E)
    readonly property string sleep: g(0xF0904)
    readonly property string restart: g(0xF0709)
    readonly property string logout: g(0xF0343)

    // Network
    readonly property string wifi4: g(0xF0928)
    readonly property string wifi3: g(0xF0925)
    readonly property string wifi2: g(0xF0922)
    readonly property string wifi1: g(0xF091F)
    readonly property string wifi0: g(0xF092F)
    readonly property string wifiOff: g(0xF092E)
    readonly property string ethernet: g(0xF0200)
    readonly property string arrowUp: g(0xF005D)
    readonly property string arrowDown: g(0xF0045)

    // Audio
    readonly property string volumeMute: g(0xF075F)
    readonly property string volumeLow: g(0xF057F)
    readonly property string volumeMed: g(0xF0580)
    readonly property string volumeHigh: g(0xF057E)
    readonly property string mic: g(0xF036C)
    readonly property string micOff: g(0xF036D)
    readonly property string music: g(0xF0759)
    readonly property string play: g(0xF040A)
    readonly property string pause: g(0xF03E4)

    // Battery
    readonly property string batteryFull: g(0xF0079)
    readonly property string battery70: g(0xF0080)
    readonly property string battery50: g(0xF007E)
    readonly property string battery30: g(0xF007C)
    readonly property string batteryAlert: g(0xF0083)
    readonly property string batteryCharging: g(0xF0084)

    // Stats
    readonly property string disk: g(0xF02CA)
    readonly property string memory: g(0xF035B)
    readonly property string cpu: g(0xF0EE0)

    function wifiFor(strength) {
        if (strength >= 0.8)
            return wifi4;
        if (strength >= 0.6)
            return wifi3;
        if (strength >= 0.4)
            return wifi2;
        if (strength >= 0.2)
            return wifi1;
        return wifi0;
    }

    function volumeFor(vol, muted) {
        if (muted || vol <= 0)
            return volumeMute;
        if (vol < 0.34)
            return volumeLow;
        if (vol < 0.67)
            return volumeMed;
        return volumeHigh;
    }

    function batteryFor(pct, charging) {
        if (charging)
            return batteryCharging;
        if (pct >= 90)
            return batteryFull;
        if (pct >= 60)
            return battery70;
        if (pct >= 30)
            return battery50;
        if (pct >= 10)
            return battery30;
        return batteryAlert;
    }
}
