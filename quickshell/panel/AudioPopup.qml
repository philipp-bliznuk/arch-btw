pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// Audio popup (omarchy parity): hero with mood + out/mic mute buttons, OUTPUT
// slider + devices (type glyph), INPUT slider + sources, per-app SOURCES (up to 150 %).
// Keys: j/k row · h/l ±5 % · m mute row (hero row = mute all) · Enter pick/mute.
PopupCard {
    id: root
    popupId: "audio"
    cardWidth: 340

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio && n.type === PwNodeType.AudioSource)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio && !(n.properties && n.properties["application.name"] === "quickshell"))
    readonly property bool allMuted: (!sink || !sink.audio || sink.audio.muted) && (!source || !source.audio || source.audio.muted)
    // key-navigation order: hero, out slider, sinks…, in slider, sources…, streams…
    readonly property var items: [{ kind: "hero" }, { kind: "volume", node: sink }]
        .concat(sinks.map(d => ({ kind: "device", node: d })))
        .concat([{ kind: "volume", node: source }])
        .concat(sources.map(d => ({ kind: "source", node: d })))
        .concat(streams.map(s => ({ kind: "volume", node: s, max: 1.5 })))
    count: items.length

    PwObjectTracker {
        objects: root.open ? root.sinks.concat(root.sources).concat(root.streams) : []
    }

    function mood(vol, muted) {
        if (muted) return "Muted";
        if (vol <= 0) return "Silenced";
        if (vol < 0.2) return "Whisper";
        if (vol < 0.4) return "Murmur";
        if (vol < 0.6) return "Easy listening";
        if (vol < 0.8) return "Steady groove";
        if (vol < 1) return "Cranked up";
        if (vol <= 1.01) return "Party mode";
        return "Concert hall";
    }

    function deviceGlyph(n) {
        const id = ((n.name || "") + " " + (n.description || "")).toLowerCase();
        if (id.includes("bluez") || id.includes("bluetooth")) return Icons.bluetooth;
        if (id.includes("hdmi") || id.includes("displayport")) return Icons.monitor;
        if (id.includes("headphone") || id.includes("headset")) return Icons.headphones;
        if (n.type === PwNodeType.AudioSource) return Icons.mic;
        return Icons.speaker;
    }

    function streamName(n) {
        const p = n.properties || {};
        return p["application.name"] || p["media.name"] || n.nickname || n.name;
    }

    function nudge(node, delta, max) {
        if (node && node.audio)
            node.audio.volume = Util.clamp(node.audio.volume + delta, 0, max || 1);
    }

    function muteAll(on) {
        for (const n of [sink, source])
            if (n && n.audio)
                n.audio.muted = on;
    }

    function slotOf(kind, node) {
        return items.findIndex(it => it.kind === kind && it.node === node);
    }

    onAction: a => {
        const it = items[cursor];
        if (!it) return;
        if (it.kind === "hero") {
            if (a === "mute" || a === "activate") muteAll(!allMuted);
            return;
        }
        if (!it.node) return;
        switch (a) {
        case "left": nudge(it.node, -0.05, it.max); break;
        case "right": nudge(it.node, 0.05, it.max); break;
        case "mute": if (it.node.audio) it.node.audio.muted = !it.node.audio.muted; break;
        case "activate":
            if (it.kind === "device") Pipewire.preferredDefaultAudioSink = it.node;
            else if (it.kind === "source") Pipewire.preferredDefaultAudioSource = it.node;
            else if (it.node.audio) it.node.audio.muted = !it.node.audio.muted;
            break;
        }
    }

    component Header: Label {
        color: Color.muted
        font.pixelSize: Style.fontCaption
    }

    component VolumeRow: Rectangle {
        id: vr
        property var node
        property real max: 1
        property string fallbackIcon: Icons.volumeHigh
        property string title: ""
        readonly property int slot: root.slotOf("volume", node)
        readonly property bool has: node && node.audio
        readonly property string iconPath: node && node.properties && node.properties["application.icon-name"] ? Quickshell.iconPath(node.properties["application.icon-name"], true) : ""
        width: parent.width
        height: 38
        radius: Style.radius
        color: root.cursor === slot ? Color.rowSelected : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: Style.spaceSm
            anchors.rightMargin: Style.spaceSm
            spacing: Style.spaceMd

            Item {
                width: 24
                height: parent.height

                IconImage {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    visible: vr.iconPath !== ""
                    source: vr.iconPath
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: vr.iconPath === ""
                    text: vr.fallbackIcon
                    glyphColor: vr.has && vr.node.audio.muted ? Color.muted : Color.text
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: if (vr.has) vr.node.audio.muted = !vr.node.audio.muted
                }
            }

            Column {
                width: parent.width - 24 - 40 - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    width: parent.width
                    text: vr.title
                    color: Color.subtext0
                    font.pixelSize: Style.fontCaption
                }
                Slider {
                    width: parent.width
                    value: vr.has ? vr.node.audio.volume / vr.max : 0
                    muted: vr.has && vr.node.audio.muted
                    onMoved: v => { if (vr.has) vr.node.audio.volume = v * vr.max; }
                }
            }

            Label {
                width: 40
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: vr.has ? Math.round(vr.node.audio.volume * 100) + "%" : ""
                font.pixelSize: Style.fontSmall
            }
        }

        HoverHandler {
            onHoveredChanged: if (hovered) root.cursor = vr.slot
        }
        MouseArea {
            z: -1
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: if (vr.has) vr.node.audio.muted = !vr.node.audio.muted
        }
    }

    component DeviceRow: ListRow {
        id: dr
        required property var modelData
        property string kind: "device"
        readonly property bool current: kind === "device" ? modelData === root.sink : modelData === root.source
        readonly property int slot: root.slotOf(kind, modelData)
        glyph: root.deviceGlyph(modelData)
        glyphColor: current ? Color.accent : Color.subtext0
        title: modelData.description || modelData.name
        trailing: current ? "default" : ""
        trailingColor: Color.accent
        selected: root.cursor === slot
        onHoveredChanged: if (hovered) root.cursor = slot
        onClicked: {
            if (kind === "device") Pipewire.preferredDefaultAudioSink = modelData;
            else Pipewire.preferredDefaultAudioSource = modelData;
        }
    }

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
                text: root.sink && root.sink.audio ? Icons.volumeFor(root.sink.audio.volume, root.sink.audio.muted) : Icons.volumeMute
                glyphColor: root.allMuted ? Color.muted : Color.accent
                size: Style.fontTitle + 8
            }
            Column {
                anchors.left: heroGlyph.right
                anchors.leftMargin: Style.spaceMd
                anchors.right: master.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Label {
                    text: "Audio"
                    font.pixelSize: Style.fontTitle
                }
                Label {
                    text: root.sink && root.sink.audio ? root.mood(root.sink.audio.volume, root.sink.audio.muted) : "No output"
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                }
            }
            Row {
                id: master
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spaceXs

                Segment {
                    readonly property bool muted: !root.sink || !root.sink.audio || root.sink.audio.muted
                    icon: muted ? Icons.volumeMute : Icons.volumeHigh
                    iconColor: muted ? Color.red : Color.text
                    label: "out"
                    labelSize: Style.fontCaption
                    active: root.cursor === 0
                    onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                }
                Segment {
                    readonly property bool muted: !root.source || !root.source.audio || root.source.audio.muted
                    icon: muted ? Icons.micOff : Icons.mic
                    iconColor: muted ? Color.red : Color.text
                    label: "mic"
                    labelSize: Style.fontCaption
                    active: root.cursor === 0
                    onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                }
            }
            HoverHandler {
                onHoveredChanged: if (hovered) root.cursor = 0
            }
        }

        Header { text: "OUTPUT" }

        VolumeRow {
            node: root.sink
            fallbackIcon: root.sink && root.sink.audio ? Icons.volumeFor(root.sink.audio.volume, root.sink.audio.muted) : Icons.volumeMute
            title: root.sink ? (root.sink.description || root.sink.name) : "No output"
        }

        Repeater {
            model: root.sinks.length > 1 ? root.sinks : []
            DeviceRow {}
        }

        Header { text: "INPUT" }

        VolumeRow {
            node: root.source
            fallbackIcon: root.source && root.source.audio && root.source.audio.muted ? Icons.micOff : Icons.mic
            title: root.source ? (root.source.description || root.source.name) : "No input"
        }

        Repeater {
            model: root.sources.length > 1 ? root.sources : []
            DeviceRow { kind: "source" }
        }

        Header {
            visible: root.streams.length > 0
            text: "SOURCES"
        }

        Repeater {
            model: root.streams

            VolumeRow {
                required property var modelData
                node: modelData
                max: 1.5
                fallbackIcon: Icons.music
                title: root.streamName(modelData)
            }
        }
    }
}
