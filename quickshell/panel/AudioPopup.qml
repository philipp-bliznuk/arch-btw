pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// Audio popup: hero with mood + out/mic mute buttons, OUTPUT slider + devices
// (only when there is a choice), INPUT slider + sources, one playback row per
// app (streams grouped by name, up to 150 %).
// Keys: j/k row · h/l ±5 % · m mute row · Enter pick device / mute.
PopupCard {
    id: root
    popupId: "audio"
    cardWidth: 340

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio && n.type === PwNodeType.AudioSource)
    // Output streams carry the Sink flag too (AudioOutStream = Audio|Stream|Sink).
    readonly property var streams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream && n.audio && !(n.properties && n.properties["application.name"] === "quickshell"))
    readonly property bool allMuted: (!sink || !sink.audio || sink.audio.muted) && (!source || !source.audio || source.audio.muted)
    // One row per application: browsers open a stream per tab, so streams
    // sharing a name collapse into one row and are set together.
    readonly property var apps: {
        const groups = [];
        for (const n of streams) {
            const name = streamName(n);
            const g = groups.find(a => a.name === name);
            if (g)
                g.nodes.push(n);
            else
                groups.push({ name: name, nodes: [n] });
        }
        return groups;
    }
    // Key-navigation order mirrors what is drawn: out mute, mic mute, out
    // slider, sinks (only when >1), in slider, sources (only when >1), apps.
    readonly property var items: [{ kind: "mute", node: sink }, { kind: "mute", node: source }, { kind: "volume", node: sink }]
        .concat(sinks.length > 1 ? sinks.map(d => ({ kind: "device", node: d })) : [])
        .concat([{ kind: "volume", node: source }])
        .concat(sources.length > 1 ? sources.map(d => ({ kind: "source", node: d })) : [])
        .concat(apps.map(a => ({ kind: "volume", node: a.nodes[0], nodes: a.nodes, max: 1.5 })))
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

    function setVolume(nodes, v, max) {
        for (const n of nodes)
            if (n && n.audio)
                n.audio.volume = Util.clamp(v, 0, max || 1);
    }

    function setMuted(nodes, muted) {
        for (const n of nodes)
            if (n && n.audio)
                n.audio.muted = muted;
    }

    function nodesOf(it) {
        return it.nodes || [it.node];
    }

    function slotOf(kind, node) {
        return items.findIndex(it => it.kind === kind && it.node === node);
    }

    keymap: [
        { key: "j k", run: k => cursor = Util.clamp(cursor + (k === "j" ? 1 : -1), 0, count - 1) },
        { key: "h l", run: k => adjust(k === "h" ? -0.05 : 0.05) },
        { key: "m", run: () => toggleMute() },
        { key: "Enter", run: () => pick() }
    ]

    function adjust(delta) {
        const it = items[cursor];
        if (it && it.node && it.node.audio)
            setVolume(nodesOf(it), it.node.audio.volume + delta, it.max);
    }

    function toggleMute() {
        const it = items[cursor];
        if (it && it.node && it.node.audio)
            setMuted(nodesOf(it), !it.node.audio.muted);
    }

    function pick() {
        const it = items[cursor];
        if (!it) return;
        if (it.kind === "device") Pipewire.preferredDefaultAudioSink = it.node;
        else if (it.kind === "source") Pipewire.preferredDefaultAudioSource = it.node;
        else toggleMute();
    }

    component Header: Label {
        color: Theme.muted
        font.pixelSize: Style.fontCaption
    }

    component VolumeRow: Rectangle {
        id: vr
        property var node
        // Every stream this row drives (several tabs of one browser); node is the first.
        property var nodes: node ? [node] : []
        property real max: 1
        property string fallbackIcon: Icons.volumeHigh
        property string title: ""
        readonly property int slot: root.slotOf("volume", node)
        readonly property bool has: node && node.audio
        readonly property string iconPath: node && node.properties && node.properties["application.icon-name"] ? Quickshell.iconPath(node.properties["application.icon-name"], true) : ""
        width: parent.width
        height: 38
        radius: Style.radius
        color: root.cursor === slot ? Theme.rowSelected : "transparent"

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
                    glyphColor: vr.has && vr.node.audio.muted ? Theme.muted : Theme.text
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: if (vr.has) root.setMuted(vr.nodes, !vr.node.audio.muted)
                }
            }

            Column {
                width: parent.width - 24 - 40 - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    width: parent.width
                    text: vr.title
                    color: Theme.subtext0
                    font.pixelSize: Style.fontCaption
                }
                Slider {
                    width: parent.width
                    value: vr.has ? vr.node.audio.volume / vr.max : 0
                    muted: vr.has && vr.node.audio.muted
                    onMoved: v => { if (vr.has) root.setVolume(vr.nodes, v * vr.max, vr.max); }
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
            onClicked: if (vr.has) root.setMuted(vr.nodes, !vr.node.audio.muted)
        }
    }

    component DeviceRow: ListRow {
        id: dr
        required property var modelData
        property string kind: "device"
        readonly property bool current: kind === "device" ? modelData === root.sink : modelData === root.source
        readonly property int slot: root.slotOf(kind, modelData)
        glyph: root.deviceGlyph(modelData)
        glyphColor: current ? Theme.accent : Theme.subtext0
        title: modelData.description || modelData.name
        trailing: current ? "default" : ""
        trailingColor: Theme.accent
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
                glyphColor: root.allMuted ? Theme.muted : Theme.accent
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
                    color: Theme.muted
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
                    iconColor: muted ? Theme.red : Theme.text
                    label: "out"
                    labelSize: Style.fontCaption
                    active: root.cursor === 0
                    onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                    onHoveredChanged: if (hovered) root.cursor = 0
                }
                Segment {
                    readonly property bool muted: !root.source || !root.source.audio || root.source.audio.muted
                    icon: muted ? Icons.micOff : Icons.mic
                    iconColor: muted ? Theme.red : Theme.text
                    label: "mic"
                    labelSize: Style.fontCaption
                    active: root.cursor === 1
                    onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
                    onHoveredChanged: if (hovered) root.cursor = 1
                }
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
            visible: root.apps.length > 0
            text: "PLAYBACK"
        }

        Repeater {
            model: root.apps

            VolumeRow {
                required property var modelData
                node: modelData.nodes[0]
                nodes: modelData.nodes
                max: 1.5
                fallbackIcon: Icons.music
                title: modelData.name
            }
        }
    }
}
