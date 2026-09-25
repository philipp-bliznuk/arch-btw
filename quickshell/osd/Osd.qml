pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// On-screen display for volume / mic / brightness.
// Volume + mic: reacts to Pipewire node changes (any source: keys, wheel, apps).
// Brightness: sysfs has no inotify → sway bind calls `qs-shell -q osd brightness`.
Scope {
    id: root

    property string icon: ""
    property string label: ""
    property real value: 0
    property bool muted: false
    property bool shown: false
    // suppress the first second after (re)load: Pipewire fires initial change events
    property bool armed: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    function show(icon, label, value, muted) {
        if (!armed)
            return;
        root.icon = icon;
        root.label = label;
        root.value = value;
        root.muted = muted === true;
        shown = true;
        hide.restart();
    }

    function showSink() {
        if (!sink || !sink.audio)
            return;
        show(Icons.volumeFor(sink.audio.volume, sink.audio.muted), sink.audio.muted ? "Muted" : Math.round(sink.audio.volume * 100) + "%", sink.audio.volume, sink.audio.muted);
    }

    function showSource() {
        if (!source || !source.audio)
            return;
        show(source.audio.muted ? Icons.micOff : Icons.mic, source.audio.muted ? "Mic muted" : Math.round(source.audio.volume * 100) + "%", source.audio.volume, source.audio.muted);
    }

    function showBrightness() {
        brightness.running = true;
    }

    PwObjectTracker {
        objects: [root.sink, root.source].filter(n => n)
    }

    Connections {
        target: root.sink ? root.sink.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.showSink(); }
        function onMutedChanged() { root.showSink(); }
    }

    Connections {
        target: root.source ? root.source.audio : null
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.showSource(); }
        function onMutedChanged() { root.showSource(); }
    }

    Process {
        id: brightness
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length < 4)
                    return;
                const pct = parseInt(f[3]) / 100;
                root.show(Icons.brightness, f[3], pct, false);
            }
        }
    }

    Timer {
        id: hide
        interval: 1200
        onTriggered: root.shown = false
    }

    Timer {
        interval: 1000
        running: true
        onTriggered: root.armed = true
    }

    IpcHandler {
        target: "osd"

        function brightness(): void {
            root.showBrightness();
        }

        function volume(): void {
            root.showSink();
        }

        function mic(): void {
            root.showSource();
        }
    }

    PanelWindow {
        visible: root.shown
        screen: SwayState.focusedScreen
        anchors.bottom: true
        margins.bottom: 60 // qmllint disable unqualified
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        implicitWidth: Style.osdWidth
        implicitHeight: 48
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: Style.cardRadius
            color: Color.cardBg
            border.width: 1
            border.color: Color.cardBorder

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Glyph {
                    text: root.icon
                    glyphColor: root.muted ? Color.muted : Color.accent
                    size: Style.fontTitle + 2
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: parent.width - 30 - 52 - parent.spacing * 2
                    height: 6
                    radius: 3
                    color: Color.surface1
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: parent.width * Util.clamp(root.value, 0, 1)
                        height: parent.height
                        radius: parent.radius
                        color: root.muted ? Color.overlay0 : Color.accent
                        Behavior on width {
                            NumberAnimation { duration: 80 }
                        }
                    }
                }

                Text {
                    width: 52
                    text: root.label
                    color: Color.text
                    horizontalAlignment: Text.AlignRight
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontSmall
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
