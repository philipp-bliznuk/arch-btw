import QtQuick
import Quickshell.Networking
import qs.Commons
import qs.Ui

Pill {
    id: root

    readonly property var device: {
        const ds = Networking.devices.values
        let wired = null
        for (const d of ds) {
            if (d.type === DeviceType.Wifi && d.connected)
                return d
            if (d.type === DeviceType.Wired && d.connected)
                wired = d
        }
        return wired
    }
    readonly property bool wifi: device ? device.type === DeviceType.Wifi : false
    readonly property var network: {
        if (!device || !wifi)
            return null
        for (const n of device.networks.values)
            if (n.connected)
                return n
        return null
    }
    readonly property real strength: network ? network.signalStrength : 0

    icon: !device ? Icons.wifiOff : (wifi ? Icons.wifiFor(strength) : Icons.ethernet)
    iconColor: device ? Color.text : Color.muted
    label: wifi && network ? Util.truncate(network.name, 16) : ""
    labelSize: Style.fontSmall

    onClicked: Util.execDetached("ghostty -e nmtui")
}
