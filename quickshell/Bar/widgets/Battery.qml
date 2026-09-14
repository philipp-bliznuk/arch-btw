import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

Pill {
    id: root
    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isPresent && dev.isLaptopBattery
    readonly property int pct: dev ? Math.round(dev.percentage) : 0
    readonly property bool charging: dev ? (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged) : false

    visible: present
    icon: Icons.batteryFor(pct, charging)
    iconColor: charging ? Color.green : (pct < 10 ? Color.red : (pct < 30 ? Color.yellow : Color.text))
    label: pct + "%"
    labelSize: Style.fontSmall
}
