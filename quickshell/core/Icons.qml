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
    readonly property string terminal: g(0xF018D)
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
    readonly property string bell: g(0xF009A)
    readonly property string bellOff: g(0xF009B)
    readonly property string chevronLeft: g(0xF0141)
    readonly property string chevronRight: g(0xF0142)
    readonly property string close: g(0xF0156)
    readonly property string trash: g(0xF0A7A)
    readonly property string clipboard: g(0xF0147)
    readonly property string image: g(0xF021F)
    readonly property string sun: g(0xF0599)
    readonly property string moon: g(0xF0594)
    readonly property string nightlight: g(0xF050E)
    readonly property string record: g(0xF044A)
    readonly property string check: g(0xF012C)
    readonly property string alert: g(0xF0026)
    readonly property string info: g(0xF02FC)
    readonly property string brightness: g(0xF00E0)
    readonly property string menu: g(0xF035C)
    readonly property string calendar: g(0xF00ED)
    readonly property string palette: g(0xF03D8)
    readonly property string window: g(0xF05AF)
    readonly property string eyedropper: g(0xF020A)
    readonly property string history: g(0xF02DA)
    readonly property string shield: g(0xF0498)
    readonly property string arch: g(0xF08C7)

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
    readonly property string arrowUp: "\u21e1"
    readonly property string arrowDown: "\u21e3"

    // Audio
    readonly property string volumeMute: g(0xF075F)
    readonly property string volumeLow: g(0xF057F)
    readonly property string volumeMed: g(0xF0580)
    readonly property string volumeHigh: g(0xF057E)
    readonly property string headphones: g(0xF02CB)
    readonly property string speaker: g(0xF04C3)
    readonly property string mic: g(0xF036C)
    readonly property string micOff: g(0xF036D)
    readonly property string music: g(0xF2EB)
    readonly property string play: g(0xF040A)
    readonly property string pause: g(0xF03E4)
    readonly property string skipPrev: g(0xF04AE)
    readonly property string skipNext: g(0xF04AD)
    readonly property string shuffle: g(0xF049D)
    readonly property string shuffleOff: g(0xF049E)
    readonly property string repeat: g(0xF0456)
    readonly property string repeatOff: g(0xF0457)
    readonly property string repeatOnce: g(0xF0458)

    // Battery
    readonly property string batteryFull: g(0xF0079)
    readonly property string battery70: g(0xF0080)
    readonly property string battery50: g(0xF007E)
    readonly property string battery30: g(0xF007C)
    readonly property string batteryAlert: g(0xF0083)
    readonly property string batteryCharging: g(0xF0084)
    readonly property string leaf: g(0xF032A)
    readonly property string scale: g(0xF05D5)
    readonly property string rocket: g(0xF14DE)

    // Weather (nf-md weather-*)
    readonly property string wSunny: g(0xF0599)
    readonly property string wNight: g(0xF0594)
    readonly property string wPartly: g(0xF0595)
    readonly property string wNightPartly: g(0xF0F31)
    readonly property string wCloudy: g(0xF0590)
    readonly property string wFog: g(0xF0591)
    readonly property string wRainy: g(0xF0597)
    readonly property string wPouring: g(0xF0596)
    readonly property string wSnowy: g(0xF0598)
    readonly property string wSnowyRainy: g(0xF067F)
    readonly property string wLightning: g(0xF0593)
    readonly property string thermometer: g(0xF050F)
    readonly property string windy: g(0xF059D)
    readonly property string humidity: g(0xF058E)
    readonly property string mapMarker: g(0xF034E)
    readonly property string refresh: g(0xF0450)

    // Stats (same glyphs as dotfiles-mac sketchybar)
    readonly property string disk: g(0xF16DF)
    readonly property string memory: g(0xE266)
    readonly property string cpu: g(0xF4BC)
    readonly property string gpu: g(0xF08AE)

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
        const step = Math.max(0, Math.min(9, Math.floor(pct / 10)));
        if (charging)
            return pct >= 100 ? g(0xF0085) : g([0xF089F, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B][step]);
        if (pct >= 100)
            return batteryFull;
        return g([0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082][step]);
    }
}
