pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// Audio popup: output volume + device picker, mic, per-app streams.
PopupCard {
    id: root
    popupId: "audio"
    cardWidth: 340

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio)

    PwObjectTracker {
        objects: root.open ? root.sinks.concat(root.streams).concat([root.source].filter(n => n)) : []
    }

    component Header: Text {
        color: Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.fontCaption
        font.weight: Font.DemiBold
    }

    component VolumeRow: Row {
        id: vr
        property var node
        property string fallbackIcon: Icons.volumeHigh
        property string title: ""
        readonly property bool has: node && node.audio
        width: parent.width
        height: 34
        spacing: 8

        Item {
            width: 20
            height: parent.height
            readonly property string iconPath: vr.node && vr.node.properties && vr.node.properties["application.icon-name"] ? Quickshell.iconPath(vr.node.properties["application.icon-name"], true) : ""

            IconImage {
                anchors.centerIn: parent
                width: 16
                height: 16
                visible: parent.iconPath !== ""
                source: parent.iconPath
            }
            Glyph {
                anchors.centerIn: parent
                visible: parent.iconPath === ""
                text: vr.fallbackIcon
                glyphColor: vr.has && vr.node.audio.muted ? Color.muted : Color.text
            }
            MouseArea {
                anchors.fill: parent
                onClicked: if (vr.has) vr.node.audio.muted = !vr.node.audio.muted
            }
        }

        Column {
            width: parent.width - 20 - 40 - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: vr.title
                color: Color.subtext0
                font.family: Style.fontFamily
                font.pixelSize: Style.fontCaption
                elide: Text.ElideRight
            }
            Slider {
                width: parent.width
                value: vr.has ? vr.node.audio.volume : 0
                muted: vr.has && vr.node.audio.muted
                onMoved: v => { if (vr.has) vr.node.audio.volume = v; }
            }
        }

        Text {
            width: 40
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: vr.has ? Math.round(vr.node.audio.volume * 100) + "%" : ""
            color: Color.text
            font.family: Style.fontFamily
            font.pixelSize: Style.fontSmall
        }
    }

    Column {
        width: parent.width
        spacing: 8

        VolumeRow {
            node: root.sink
            fallbackIcon: root.sink && root.sink.audio ? Icons.volumeFor(root.sink.audio.volume, root.sink.audio.muted) : Icons.volumeMute
            title: root.sink ? (root.sink.description || root.sink.name) : "No output"
        }

        Header {
            visible: root.sinks.length > 1
            text: "OUTPUT DEVICE"
        }

        Repeater {
            model: root.sinks.length > 1 ? root.sinks : []

            Rectangle {
                id: sinkRow
                required property var modelData
                readonly property bool current: modelData === root.sink
                width: parent.width
                height: 28
                radius: Style.radius
                color: current ? Color.rowSelected : (mouse.containsMouse ? Util.alpha(Color.surface1, 0.5) : "transparent")

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Glyph {
                        text: sinkRow.current ? Icons.check : ""
                        glyphColor: Color.green
                        width: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sinkRow.modelData.description || sinkRow.modelData.name
                        color: Color.text
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontSmall
                        elide: Text.ElideRight
                        width: parent.width - 22
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Pipewire.preferredDefaultAudioSink = sinkRow.modelData
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Color.surface1 }

        VolumeRow {
            node: root.source
            fallbackIcon: root.source && root.source.audio && root.source.audio.muted ? Icons.micOff : Icons.mic
            title: root.source ? (root.source.description || root.source.name) : "No input"
        }

        Rectangle { visible: root.streams.length > 0; width: parent.width; height: 1; color: Color.surface1 }

        Header {
            visible: root.streams.length > 0
            text: "APPLICATIONS"
        }

        Repeater {
            model: root.streams

            VolumeRow {
                required property var modelData
                node: modelData
                fallbackIcon: Icons.music
                title: (modelData.properties && modelData.properties["application.name"]) || modelData.nickname || modelData.name
            }
        }
    }
}
