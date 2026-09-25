pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Networking
import qs.core
import qs.ui

Pill {
    id: root

    readonly property var wifiDevice: {
        for (const d of Networking.devices.values)
            if (d.type === DeviceType.Wifi)
                return d;
        return null;
    }
    readonly property var device: {
        const ds = Networking.devices.values;
        let wired = null;
        for (const d of ds) {
            if (d.type === DeviceType.Wifi && d.connected)
                return d;
            if (d.type === DeviceType.Wired && d.connected)
                wired = d;
        }
        return wired;
    }
    readonly property bool wifi: device ? device.type === DeviceType.Wifi : false
    readonly property var network: {
        if (!device || !wifi)
            return null;
        for (const n of device.networks.values)
            if (n.connected)
                return n;
        return null;
    }
    readonly property real strength: network ? network.signalStrength : 0
    readonly property var networks: {
        if (!wifiDevice)
            return [];
        const seen = {};
        const out = [];
        for (const n of wifiDevice.networks.values) {
            if (!n.name || seen[n.name])
                continue;
            seen[n.name] = true;
            out.push(n);
        }
        return out.sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength));
    }
    property var pending: null

    icon: !device ? Icons.wifiOff : (wifi ? Icons.wifiFor(strength) : Icons.ethernet)
    iconColor: device ? Color.text : Color.muted
    label: wifi && network ? Util.truncate(network.name, 16) : ""
    labelSize: Style.fontSmall
    highlighted: popup.open

    onClicked: m => {
        if (m.button === Qt.RightButton) {
            Commands.run({ argv: Commands.term(["nmtui"]) });
            return;
        }
        Popups.toggle("network");
    }

    function secure(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    function stateText(n) {
        if (n.stateChanging)
            return "connecting…";
        if (n.connectionFailed)
            return "failed";
        if (n.connected)
            return "connected";
        return [n.known ? "saved" : "", root.secure(n) ? "secured" : "open"].filter(x => x).join(" · ");
    }

    function pick(n) {
        if (n.connected) {
            n.disconnect();
            return;
        }
        if (n.known || !secure(n)) {
            n.connect();
            return;
        }
        pending = n;
        psk.text = "";
        psk.input.forceActiveFocus();
    }

    function submitPsk() {
        if (!pending)
            return;
        pending.connectWithPsk(psk.text);
        psk.text = "";
        pending = null;
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "network"
        cardWidth: 320
        onOpenChanged: {
            if (root.wifiDevice)
                root.wifiDevice.scannerEnabled = open;
            if (!open)
                root.pending = null;
        }

        Column {
            width: parent.width
            spacing: 6

            MenuRow {
                glyph: root.icon
                glyphColor: root.iconColor
                title: root.device ? (root.wifi ? (root.network ? root.network.name : "Wi-Fi") : "Ethernet") : "Disconnected"
                subtitle: root.device ? (root.device.address || "") : ""
                trailing: root.wifiDevice ? (Networking.wifiEnabled ? "wifi off" : "wifi on") : ""
                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
            }

            Rectangle { width: parent.width; height: 1; color: Color.surface1 }

            Column {
                width: parent.width
                visible: root.pending !== null
                spacing: 4

                Text {
                    text: "Password for " + (root.pending ? root.pending.name : "")
                    color: Color.subtext0
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                }
                Field {
                    id: psk
                    width: parent.width
                    placeholder: "Passphrase"
                    echoMode: TextInput.Password
                    onAccepted: root.submitPsk()
                    onEscaped: root.pending = null
                }
            }

            Repeater {
                model: root.networks.slice(0, 10)

                MenuRow {
                    required property var modelData
                    glyph: Icons.wifiFor(modelData.signalStrength)
                    glyphColor: modelData.connected ? Color.accent : Color.text
                    title: modelData.name
                    subtitle: root.stateText(modelData)
                    trailing: modelData.connected ? "disconnect" : (modelData.known ? "connect · R forget" : "connect")
                    selected: modelData.connected
                    onClicked: m => {
                        if (m.button === Qt.RightButton && modelData.known)
                            modelData.forget();
                        else
                            root.pick(modelData);
                    }
                }
            }

            Text {
                visible: root.wifiDevice && Networking.wifiEnabled && root.networks.length === 0
                text: "Scanning…"
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
            }

            Rectangle { width: parent.width; height: 1; color: Color.surface1 }

            MenuRow {
                glyph: Icons.terminal
                title: "Advanced"
                subtitle: "nmtui"
                onClicked: {
                    Popups.close();
                    Commands.run({ argv: Commands.term(["nmtui"]) });
                }
            }
        }
    }
}
