pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Networking
import qs.core
import qs.ui

// Network segment + popup: hero with SSID / Ethernet speed,
// captive-portal & limited-connectivity notice, live details grid, Wi-Fi
// switch, KNOWN / OTHER networks, inline PSK + WPA-EAP identity, failures.
// Keys: j/k row · Enter connect/disconnect · w Wi-Fi on/off · r rescan.
Segment {
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
    readonly property var all: {
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
    readonly property var known: all.filter(n => n.known)
    readonly property var other: all.filter(n => !n.known).slice(0, 8)
    readonly property var rows: known.concat(other)
    readonly property bool portal: Networking.connectivity === NetworkConnectivity.Portal
    readonly property bool limited: Networking.connectivity === NetworkConnectivity.Limited
    property var stats: ({})
    property real prevRx: -1
    property real prevTx: -1
    property real prevTime: 0
    property string down: "-"
    property string up: "-"
    property var pending: null
    property bool eap: false
    property string failure: ""
    // SSID the user picked on purpose; once connected its profile becomes the
    // autoconnect favourite (qs-wifi-prefer). Disconnects never set it.
    property string chosen: ""

    icon: !device ? Icons.wifiOff : (wifi ? Icons.wifiFor(strength) : Icons.ethernet)
    iconColor: !device ? Color.muted : (portal || limited ? Color.yellow : Color.text)
    active: popup.open

    onClicked: popup.toggle()

    onNetworkChanged: {
        if (!network || network.name !== chosen)
            return;
        prefer.command = [Util.bin("qs-wifi-prefer"), chosen];
        prefer.running = true;
        chosen = "";
    }

    function secure(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    function enterprise(n) {
        return n.security === WifiSecurityType.WpaEap || n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.Wpa3SuiteB192;
    }

    function stateText(n) {
        if (n.stateChanging)
            return "connecting…";
        if (n.connected)
            return portal ? "sign-in required" : "connected";
        return [n.known ? "saved" : "", secure(n) ? "secured" : "open"].filter(x => x).join(" · ");
    }

    function speedText() {
        const s = stats.speed;
        if (!s)
            return "";
        return s >= 1000 ? (s / 1000) + " gbit" : s + " mbit";
    }

    function pick(n) {
        failure = "";
        if (n.connected) {
            n.disconnect();
            return;
        }
        chosen = n.name;
        if (n.known || !secure(n)) {
            n.connect();
            return;
        }
        pending = n;
        eap = enterprise(n);
        psk.text = "";
        identity.text = "";
        (eap ? identity : psk).input.forceActiveFocus();
    }

    function submit() {
        if (!pending)
            return;
        const n = pending;
        if (eap)
            eapAdd.run(n.name, identity.text, psk.text);
        else
            n.connectWithPsk(psk.text);
        psk.text = "";
        pending = null;
        popup.focusKeys();
    }

    function activate() {
        const n = rows[popup.cursor];
        if (portal) openPortal();
        else if (n) pick(n);
    }

    function openPortal() {
        Popups.close();
        Commands.run({ argv: ["librewolf", "http://ping.archlinux.org/nm-check.txt"] });
    }

    function refresh() {
        if (wifiDevice) {
            wifiDevice.scannerEnabled = false;
            wifiDevice.scannerEnabled = true;
        }
        statusProbe.running = true;
    }

    Process {
        id: statusProbe
        command: [Util.bin("qs-network-status")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    const now = Date.now() / 1000;
                    if (root.prevRx >= 0 && now > root.prevTime) {
                        const dt = now - root.prevTime;
                        root.down = Util.humanBytes((s.rx - root.prevRx) / dt);
                        root.up = Util.humanBytes((s.tx - root.prevTx) / dt);
                    }
                    root.prevRx = s.rx;
                    root.prevTx = s.tx;
                    root.prevTime = now;
                    root.stats = s;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 1500
        running: popup.open
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProbe.running = true
    }

    Process {
        id: prefer
    }

    // NM re-checks connectivity every 60 s (connectivity.conf); while the link
    // reports limited/portal, poke it faster so a router coming back is noticed.
    Process {
        id: recheck
        command: ["nmcli", "networking", "connectivity", "check"]
    }

    Timer {
        interval: 15000
        running: root.limited || root.portal
        repeat: true
        onTriggered: recheck.running = true
    }

    // WPA-EAP (PEAP/MSCHAPv2) profile via nmcli; password over stdin.
    Process {
        id: eapAdd
        property string ssid: ""
        function run(name, user, pass) {
            ssid = name;
            command = ["sh", "-c", 'nmcli connection add type wifi con-name "$1" ifname "$2" ssid "$1" wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity "$3" 802-1x.password "$(cat)" >/dev/null && nmcli connection up "$1"', "sh", name, root.wifiDevice ? root.wifiDevice.name : "", user];
            stdinEnabled = true;
            running = true;
            write(pass + "\n");
            stdinEnabled = false;
        }
        onExited: code => { if (code !== 0) root.failure = "Could not join " + ssid; } // qmllint disable signal-handler-parameters
    }

    component Stat: Column {
        id: stat
        property string title: ""
        property string value: ""
        width: (parent.width - Style.spaceMd) / 2
        spacing: 0

        Label {
            text: stat.title
            color: Color.muted
            font.pixelSize: Style.fontCaption
        }
        Label {
            width: parent.width
            text: stat.value || "-"
            font.pixelSize: Style.fontSmall
        }
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "network"
        cardWidth: 340
        count: root.rows.length
        onOpenChanged: {
            if (root.wifiDevice)
                root.wifiDevice.scannerEnabled = open;
            if (!open) {
                root.pending = null;
                root.failure = "";
                root.prevRx = -1;
            }
        }
        keymap: [
            { key: "j k", run: k => cursor = Util.clamp(cursor + (k === "j" ? 1 : -1), 0, count - 1) },
            { key: "Enter", run: () => root.activate() },
            { key: "w", run: () => Networking.wifiEnabled = !Networking.wifiEnabled },
            { key: "r", run: () => root.refresh() }
        ]

        Column {
            width: parent.width
            spacing: Style.spaceSm

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
                    anchors.right: wifiSwitch.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        text: root.device ? (root.wifi ? (root.network ? root.network.name : "Wi-Fi") : "Ethernet" + (root.speedText() ? " · " + root.speedText() : "")) : "Disconnected"
                        font.pixelSize: Style.fontTitle
                    }
                    Label {
                        width: parent.width
                        text: root.portal ? "SIGN-IN REQUIRED" : (root.limited ? "LIMITED INTERNET ACCESS" : (root.device ? (root.wifi ? Math.round(root.strength * 100) + "% signal" : root.stats.iface || "") : "NOT CONNECTED"))
                        color: root.portal || root.limited ? Color.yellow : Color.muted
                        font.pixelSize: Style.fontCaption
                    }
                }
                Segment {
                    id: wifiSwitch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.wifiDevice !== null
                    icon: Networking.wifiEnabled ? Icons.wifi4 : Icons.wifiOff
                    iconColor: Networking.wifiEnabled ? Color.accent : Color.muted
                    label: Networking.wifiEnabled ? "on" : "off"
                    labelSize: Style.fontCaption
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }

            ListRow {
                visible: root.portal
                glyph: Icons.web
                glyphColor: Color.yellow
                title: "Open captive portal"
                onClicked: root.openPortal()
            }

            Flow {
                width: parent.width
                spacing: Style.spaceMd
                visible: root.device !== null

                Stat { title: "PING"; value: root.stats.ping !== null && root.stats.ping !== undefined ? root.stats.ping + " ms" : "" }
                Stat { title: "GATEWAY"; value: root.stats.gateway || "" }
                Stat { title: "IP ADDRESS"; value: root.stats.ip || "" }
                Stat { title: "TRAFFIC ↓ / ↑"; value: root.down + " · " + root.up }
                Stat { title: "DOWNLOADED"; value: Util.humanSize(root.stats.rx) }
                Stat { title: "UPLOADED"; value: Util.humanSize(root.stats.tx) }
            }

            Label {
                visible: root.failure !== ""
                width: parent.width
                text: root.failure
                color: Color.red
                font.pixelSize: Style.fontCaption
            }

            Column {
                width: parent.width
                visible: root.pending !== null
                spacing: Style.spaceXs

                Label {
                    text: (root.eap ? "Credentials for " : "Passphrase for ") + (root.pending ? root.pending.name : "")
                    color: Color.subtext0
                    font.pixelSize: Style.fontCaption
                }
                Field {
                    id: identity
                    visible: root.eap
                    width: parent.width
                    placeholder: "Identity (username)"
                    onAccepted: psk.input.forceActiveFocus()
                    onEscaped: {
                        root.pending = null;
                        popup.focusKeys();
                    }
                }
                Field {
                    id: psk
                    width: parent.width
                    placeholder: "Passphrase - Enter to connect, Esc to cancel"
                    echoMode: TextInput.Password
                    onAccepted: root.submit()
                    onEscaped: {
                        root.pending = null;
                        popup.focusKeys();
                    }
                }
            }

            Label {
                visible: root.known.length > 0
                text: "KNOWN NETWORKS"
                color: Color.muted
                font.pixelSize: Style.fontCaption
            }

            Repeater {
                model: root.known

                ListRow {
                    id: knownRow
                    required property var modelData
                    required property int index
                    glyph: Icons.wifiFor(modelData.signalStrength)
                    glyphColor: modelData.connected ? Color.accent : Color.text
                    title: modelData.name
                    subtext: root.stateText(modelData)
                    trailing: (root.secure(modelData) ? Icons.lock + " " : "") + (modelData.connected ? "disconnect" : "connect")
                    selected: popup.cursor === index
                    onHoveredChanged: if (hovered) popup.cursor = index
                    onClicked: root.pick(modelData)

                    Connections {
                        target: knownRow.modelData
                        function onConnectionFailed() {
                            root.failure = "Wrong password for " + knownRow.modelData.name + "?";
                        }
                    }
                }
            }

            Label {
                visible: root.other.length > 0
                text: "OTHER NETWORKS"
                color: Color.muted
                font.pixelSize: Style.fontCaption
            }

            Repeater {
                model: root.other

                ListRow {
                    required property var modelData
                    required property int index
                    glyph: Icons.wifiFor(modelData.signalStrength)
                    title: modelData.name
                    subtext: root.stateText(modelData)
                    trailing: root.secure(modelData) ? Icons.lock : "open"
                    dim: true
                    selected: popup.cursor === root.known.length + index
                    onHoveredChanged: if (hovered) popup.cursor = root.known.length + index
                    onClicked: root.pick(modelData)
                }
            }

            Label {
                visible: root.wifiDevice && Networking.wifiEnabled && root.rows.length === 0
                text: "Scanning…"
                color: Color.muted
                font.pixelSize: Style.fontSmall
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Color.surface1
            }

            ListRow {
                glyph: Icons.terminal
                title: "Advanced"
                subtext: "nmtui"
                onClicked: {
                    Popups.close();
                    Commands.run({ argv: Commands.term(["nmtui"]) });
                }
            }
        }
    }
}
