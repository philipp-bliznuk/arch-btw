pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core
import qs.ui

// Battery (omarchy parity): 10-level glyphs, optional %, threshold "Holding"
// detection, stats, power profiles, auto power-saver on battery.
// Keys: j/k profile · Enter apply · p toggle %.
Segment {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isPresent && dev.isLaptopBattery
    readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool onBattery: UPower.onBattery
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged) : false
    // Charge threshold (e.g. TLP/BIOS 80 % cap): plugged in yet neither charging nor full.
    readonly property bool holding: dev && !onBattery && (dev.state === UPowerDeviceState.PendingCharge || (dev.state === UPowerDeviceState.FullyCharged && pct < 99) || (dev.state === UPowerDeviceState.Charging && (Math.abs(dev.changeRate) <= 0.2 || dev.timeToFull >= 8 * 3600)))
    readonly property string mode: holding ? "Holding" : (onBattery ? "On battery" : (pct >= 99 ? "Fully charged" : "Charging"))
    readonly property string remaining: {
        if (!dev)
            return "";
        const t = onBattery ? fmt(dev.timeToEmpty) : fmt(dev.timeToFull);
        return t ? (onBattery ? t + " left" : t + " to full") : "";
    }
    readonly property bool showPct: Settings.get("batteryPercent")
    property bool profilesAvailable: false
    property int cycles: 0
    property int lastWarned: 100
    readonly property var profiles: profilesAvailable ? [PowerProfile.PowerSaver, PowerProfile.Balanced].concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : []) : []

    visible: present
    icon: Icons.batteryFor(pct, charging && !holding)
    iconColor: charging && !holding ? Color.green : (pct < 10 ? Color.red : (pct < 30 ? Color.yellow : Color.text))
    label: showPct ? pct + "%" : ""
    tooltip: [pct + "% · " + mode.toLowerCase(), remaining, "right-click toggles %"].filter(x => x).join(" · ")
    active: popup.open

    onClicked: m => {
        if (m.button === Qt.RightButton)
            Settings.set("batteryPercent", !showPct);
        else
            popup.toggle();
    }

    // Auto profile: power-saver when unplugged, balanced when plugged in.
    onOnBatteryChanged: {
        if (!Settings.get("powerSaverOnBattery"))
            return;
        PowerProfiles.profile = onBattery ? PowerProfile.PowerSaver : PowerProfile.Balanced;
    }

    Process {
        id: ppdProbe
        command: ["busctl", "--system", "--no-pager", "status", "org.freedesktop.UPower.PowerProfiles"]
        running: popup.open
        onExited: (code, status) => root.profilesAvailable = code === 0 // qmllint disable signal-handler-parameters
    }

    Process {
        id: cyclesProbe
        command: ["sh", "-c", "upower -i $(upower -e | grep -m1 -i bat) | awk '/charge-cycles/{print $2}'"]
        running: popup.open
        stdout: StdioCollector {
            onStreamFinished: root.cycles = parseInt(text) || 0
        }
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

    onPctChanged: {
        if (!onBattery) {
            lastWarned = 100;
            return;
        }
        for (const level of [15, 5]) {
            if (pct <= level && lastWarned > level) {
                lastWarned = level;
                Quickshell.execDetached([Util.bin("qs-notify"), "-u", level <= 5 ? "critical" : "normal", "-i", "battery-caution", "Battery " + pct + "%", remaining ? remaining.replace(" left", " remaining") : ""]);
            }
        }
    }

    component Stat: Column {
        property string title: ""
        property string value: ""
        width: (parent.width - Style.spaceMd) / 2
        spacing: 0
        visible: value !== ""

        Label {
            text: parent.title
            color: Color.muted
            font.pixelSize: Style.fontCaption
        }
        Label {
            text: parent.value
            font.pixelSize: Style.fontSmall
        }
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "battery"
        cardWidth: 300
        count: root.profiles.length
        onAction: a => {
            if (a === "activate" && root.profiles[cursor] !== undefined)
                PowerProfiles.profile = root.profiles[cursor];
            else if (a === "paste")
                Settings.set("batteryPercent", !root.showPct);
        }

        Column {
            width: parent.width
            spacing: Style.spaceMd

            Item {
                width: parent.width
                height: 40

                Glyph {
                    id: heroGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 40
                    text: root.icon
                    glyphColor: root.iconColor
                    size: Style.fontTitle + 8
                }
                Column {
                    anchors.left: heroGlyph.right
                    anchors.leftMargin: Style.spaceMd
                    anchors.right: heroPct.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        text: root.mode
                        font.pixelSize: Style.fontTitle
                    }
                    Label {
                        width: parent.width
                        text: root.remaining || (root.holding ? "charge limit reached" : "")
                        color: Color.muted
                        font.pixelSize: Style.fontCaption
                    }
                }
                Label {
                    id: heroPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pct + "%"
                    font.pixelSize: Style.fontTitle + 6
                    color: root.iconColor
                }
            }

            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Color.surface1

                Rectangle {
                    id: fill
                    width: parent.width * root.pct / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.iconColor

                    SequentialAnimation on opacity {
                        running: root.charging && !root.holding && popup.open
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.45
                            duration: 900
                        }
                        NumberAnimation {
                            to: 1
                            duration: 900
                        }
                        onRunningChanged: if (!running) fill.opacity = 1
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: Style.spaceMd

                Stat {
                    title: "CAPACITY"
                    value: root.dev && root.dev.energyCapacity ? root.dev.energyCapacity.toFixed(1) + " Wh" : ""
                }
                Stat {
                    title: root.onBattery ? "DISCHARGING" : "CHARGING RATE"
                    value: root.dev && root.dev.changeRate ? Math.abs(root.dev.changeRate).toFixed(1) + " W" : ""
                }
                Stat {
                    title: "HEALTH"
                    value: root.dev && root.dev.healthSupported ? Math.round(root.dev.healthPercentage * 100) + "%" : ""
                }
                Stat {
                    title: "CYCLES"
                    value: root.cycles ? String(root.cycles) : ""
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Color.surface1
                visible: root.profilesAvailable
            }

            Label {
                visible: root.profilesAvailable
                text: "POWER PROFILE"
                color: Color.muted
                font.pixelSize: Style.fontCaption
            }

            Row {
                visible: root.profilesAvailable
                width: parent.width
                spacing: Style.spaceXs

                Repeater {
                    model: root.profiles

                    Rectangle {
                        id: prof
                        required property var modelData
                        required property int index
                        readonly property bool current: PowerProfiles.profile === modelData
                        width: (parent.width - Style.spaceXs * (root.profiles.length - 1)) / root.profiles.length
                        height: 48
                        radius: Style.radius
                        color: current ? Color.segmentActive : (popup.cursor === index ? Color.segmentHover : Color.surface0)
                        border.width: popup.cursor === index ? 1 : 0
                        border.color: Color.accent

                        Column {
                            anchors.centerIn: parent
                            spacing: 0

                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.profileGlyph(prof.modelData)
                                glyphColor: prof.current ? Color.accent : Color.subtext0
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.profileName(prof.modelData)
                                color: prof.current ? Color.text : Color.muted
                                font.pixelSize: Style.fontCaption
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) popup.cursor = prof.index
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: PowerProfiles.profile = prof.modelData
                        }
                    }
                }
            }
        }
    }
}
