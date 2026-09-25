pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core
import qs.ui

Pill {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isPresent && dev.isLaptopBattery
    readonly property int pct: dev ? Math.round(dev.percentage) : 0
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged) : false
    property bool profilesAvailable: false
    property int lastWarned: 100

    visible: present
    icon: Icons.batteryFor(pct, charging)
    iconColor: charging ? Color.green : (pct < 10 ? Color.red : (pct < 30 ? Color.yellow : Color.text))
    label: pct + "%"
    labelSize: Style.fontSmall
    highlighted: popup.open

    onClicked: Popups.toggle("battery")

    // power-profiles-daemon optional: probe the bus name once per popup open
    Process {
        id: ppdProbe
        command: ["busctl", "--system", "--no-pager", "status", "org.freedesktop.UPower.PowerProfiles"]
        running: popup.open
        onExited: (code, status) => root.profilesAvailable = code === 0 // qmllint disable signal-handler-parameters
    }

    function fmt(seconds) {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    function profileName(p) {
        switch (p) {
        case PowerProfile.PowerSaver: return "Power saver";
        case PowerProfile.Performance: return "Performance";
        default: return "Balanced";
        }
    }

    onPctChanged: {
        if (charging) {
            lastWarned = 100;
            return;
        }
        for (const level of [15, 5]) {
            if (pct <= level && lastWarned > level) {
                lastWarned = level;
                Quickshell.execDetached([Util.bin("qs-notify"), "-u", level <= 5 ? "critical" : "normal", "-i", "battery-caution", "Battery " + pct + "%", fmt(dev.timeToEmpty) ? fmt(dev.timeToEmpty) + " remaining" : ""]);
            }
        }
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "battery"
        cardWidth: 280

        Column {
            width: parent.width
            spacing: 6

            MenuRow {
                glyph: root.icon
                glyphColor: root.iconColor
                title: root.pct + "%" + (root.charging ? " · charging" : "")
                subtitle: {
                    if (!root.dev) return "";
                    const t = root.charging ? root.fmt(root.dev.timeToFull) : root.fmt(root.dev.timeToEmpty);
                    const rate = root.dev.changeRate ? Math.abs(root.dev.changeRate).toFixed(1) + " W" : "";
                    return [t ? (root.charging ? t + " to full" : t + " left") : "", rate].filter(x => x).join(" · ");
                }
                trailing: root.dev && root.dev.healthSupported ? "health " + Math.round(root.dev.healthPercentage) + "%" : ""
            }

            Rectangle { width: parent.width; height: 1; color: Color.surface1; visible: root.profilesAvailable }

            Text {
                visible: root.profilesAvailable
                text: "POWER PROFILE"
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontCaption
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.profilesAvailable ? [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : []) : []

                MenuRow {
                    required property var modelData
                    glyph: PowerProfiles.profile === modelData ? Icons.check : ""
                    glyphColor: Color.green
                    title: root.profileName(modelData)
                    selected: PowerProfiles.profile === modelData
                    onClicked: PowerProfiles.profile = modelData
                }
            }
        }
    }
}
