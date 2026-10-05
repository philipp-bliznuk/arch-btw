pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Battery state shared by every panel copy: plugged/charging from sysfs
// (AC/online, BAT*/status) re-read on udev power_supply events, UPower for %,
// time estimates and presence, power profiles, charge limit (bin/qs-battery),
// low-battery toasts and the automatic power-saver profile. One udev listener
// and one toast regardless of how many outputs show a battery segment.
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isPresent && dev.isLaptopBattery
    readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
    property bool acOnline: !UPower.onBattery
    // Kernel status: Charging / Discharging / Not charging / Full / Unknown ("" until read).
    property string kstate: ""
    readonly property string batName: {
        const b = UPower.devices.values.find(d => d.isLaptopBattery);
        return b && b.nativePath ? b.nativePath.split("/").pop() : "BAT0";
    }
    readonly property bool onBattery: !acOnline
    readonly property bool charging: kstate !== "" ? (kstate === "Charging" || kstate === "Full") : (dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged) : false)
    // Charge limit reached: plugged in yet neither charging nor full.
    readonly property bool holding: !onBattery && (kstate !== "" ? (kstate === "Not charging" || (kstate === "Full" && pct < 99)) : (dev && (dev.state === UPowerDeviceState.PendingCharge || (dev.state === UPowerDeviceState.FullyCharged && pct < 99))))
    readonly property string mode: holding ? "Holding" : (onBattery ? "On battery" : (pct >= 99 ? "Fully charged" : "Charging"))
    readonly property string remaining: {
        if (!dev)
            return "";
        const t = onBattery ? fmt(dev.timeToEmpty) : fmt(dev.timeToFull);
        return t ? (onBattery ? t + " left" : t + " to full") : "";
    }
    property bool profilesAvailable: false
    readonly property var profiles: profilesAvailable ? [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : []) : []
    // Charge limit as reported by qs-battery status: {supported, enabled, start, end}.
    property var limit: ({ supported: false })
    property int lastWarned: 100

    function fmt(seconds) {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    function profileName(p) {
        switch (p) {
        case PowerProfile.PowerSaver:
            return "Power saver";
        case PowerProfile.Performance:
            return "Performance";
        default:
            return "Balanced";
        }
    }

    function profileGlyph(p) {
        switch (p) {
        case PowerProfile.PowerSaver:
            return Icons.leaf;
        case PowerProfile.Performance:
            return Icons.rocket;
        default:
            return Icons.scale;
        }
    }

    function poll() {
        ac.reload();
        bat.reload();
    }

    function refreshLimit() {
        limitProbe.running = true;
    }

    function toggleLimit() {
        limitFlip.running = true;
    }

    function readLimit(text) {
        try {
            limit = JSON.parse(text);
        } catch (e) {
            limit = { supported: false };
        }
    }

    FileView {
        id: ac
        path: "/sys/class/power_supply/AC/online"
        printErrors: false
        onLoaded: root.acOnline = text().trim() === "1"
        onLoadFailed: root.acOnline = !UPower.onBattery // qmllint disable signal-handler-parameters
    }

    FileView {
        id: bat
        path: "/sys/class/power_supply/" + root.batName + "/status"
        printErrors: false
        onLoaded: root.kstate = text().trim()
        onLoadFailed: root.kstate = "" // qmllint disable signal-handler-parameters
    }

    Process {
        id: psEvents
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=power_supply"]
        stdout: SplitParser {
            onRead: {
                root.poll();
                settle.restart();
            }
        }
        onExited: psRetry.start() // qmllint disable signal-handler-parameters
    }

    Timer {
        id: psRetry
        interval: 2000
        onTriggered: psEvents.running = true
    }

    // One re-read after a udev burst: the EC reports "Not charging" for ~1 s
    // after a threshold write and resumes without another event.
    Timer {
        id: settle
        interval: 2000
        onTriggered: root.poll()
    }

    // UPower is debounced but event-driven; use it as a second trigger.
    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.poll();
        }
    }

    Connections {
        target: root.dev
        ignoreUnknownSignals: true
        function onStateChanged() {
            root.poll();
        }
    }

    // Auto profile: power-saver when unplugged, balanced when plugged in.
    onOnBatteryChanged: {
        if (!Settings.get("powerSaverOnBattery"))
            return;
        PowerProfiles.profile = onBattery ? PowerProfile.PowerSaver : PowerProfile.Balanced;
    }

    Process {
        id: ppdProbe
        running: true
        command: ["busctl", "--system", "--no-pager", "status", "org.freedesktop.UPower.PowerProfiles"]
        onExited: (code, status) => root.profilesAvailable = code === 0 // qmllint disable signal-handler-parameters
    }

    // Read once at startup so the first popup open does not grow a frame later;
    // re-read on each open since the BIOS knob can change outside the shell.
    Process {
        id: limitProbe
        running: true
        command: [Util.bin("qs-battery"), "status"]
        stdout: StdioCollector {
            onStreamFinished: root.readLimit(text)
        }
    }

    Process {
        id: limitFlip
        command: [Util.bin("qs-battery"), "limit"]
        stdout: StdioCollector {
            onStreamFinished: root.readLimit(text)
        }
    }

    onPctChanged: {
        if (!onBattery) {
            lastWarned = 100;
            return;
        }
        // UPower emits transient ~0-1 % readings at startup/resume; never warn on those.
        if (!present || dev.state !== UPowerDeviceState.Discharging || pct <= 1)
            return;
        for (const level of [5, 15]) {
            if (pct <= level && lastWarned > level) {
                lastWarned = level;
                Commands.run({ argv: [Util.bin("qs-notify"), "-u", level <= 5 ? "critical" : "normal", "-i", "battery-caution", "Battery " + pct + "%", remaining ? remaining.replace(" left", " remaining") : ""] });
                return;
            }
        }
    }
}
