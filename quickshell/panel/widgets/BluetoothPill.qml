pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Bluetooth
import qs.core
import qs.ui

Pill {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var connected: devices.filter(d => d.connected)
    readonly property var known: devices.filter(d => d.paired || d.trusted || d.connected)
    readonly property var discovered: devices.filter(d => !d.paired && !d.trusted && !d.connected && d.name)

    visible: adapter !== null
    icon: Icons.bluetooth
    iconColor: !adapter || !adapter.enabled ? Color.muted : (connected.length ? Color.accent : Color.text)
    label: connected.length ? (connected.length === 1 ? Util.truncate(connected[0].name, 14) : connected.length + "") : ""
    labelSize: Style.fontSmall
    highlighted: popup.open

    onClicked: m => {
        if (m.button === Qt.RightButton && adapter) {
            adapter.enabled = !adapter.enabled;
            return;
        }
        Popups.toggle("bluetooth");
    }

    function stateText(d) {
        if (d.pairing)
            return "pairing…";
        if (d.state === BluetoothDeviceState.Connecting)
            return "connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting…";
        if (d.connected)
            return d.batteryAvailable ? "connected · " + Math.round(d.battery * 100) + "%" : "connected";
        return d.paired ? "paired" : "";
    }

    function act(d) {
        if (d.connected)
            d.disconnect();
        else if (d.paired || d.trusted)
            d.connect();
        else
            d.pair();
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "bluetooth"
        cardWidth: 300
        onOpenChanged: if (root.adapter) root.adapter.discovering = open && root.adapter.enabled

        Column {
            width: parent.width
            spacing: 6

            MenuRow {
                glyph: Icons.bluetooth
                glyphColor: root.adapter && root.adapter.enabled ? Color.accent : Color.muted
                title: root.adapter ? root.adapter.name : "Bluetooth"
                subtitle: root.adapter && root.adapter.enabled ? (root.adapter.discovering ? "on · scanning…" : "on") : "off"
                trailing: root.adapter && root.adapter.enabled ? "turn off" : "turn on"
                onClicked: root.adapter.enabled = !root.adapter.enabled
            }

            Rectangle { width: parent.width; height: 1; color: Color.surface1 }

            Text {
                visible: root.known.length > 0
                text: "DEVICES"
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontCaption
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.known

                MenuRow {
                    required property var modelData
                    glyph: modelData.connected ? Icons.check : ""
                    glyphColor: Color.green
                    title: modelData.name
                    subtitle: root.stateText(modelData)
                    trailing: modelData.connected ? "disconnect" : "connect"
                    onClicked: m => {
                        if (m.button === Qt.RightButton)
                            modelData.forget();
                        else
                            root.act(modelData);
                    }
                }
            }

            Text {
                visible: root.discovered.length > 0
                text: "AVAILABLE"
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontCaption
                font.weight: Font.DemiBold
            }

            Repeater {
                model: root.discovered.slice(0, 8)

                MenuRow {
                    required property var modelData
                    title: modelData.name
                    subtitle: root.stateText(modelData)
                    trailing: "pair"
                    dim: true
                    onClicked: root.act(modelData)
                }
            }

            Text {
                visible: root.adapter && root.adapter.enabled && root.known.length === 0 && root.discovered.length === 0
                text: "Scanning for devices…"
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
            }
        }
    }
}
