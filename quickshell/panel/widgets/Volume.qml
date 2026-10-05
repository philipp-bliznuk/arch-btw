import QtQuick
import Quickshell.Services.Pipewire
import qs.core
import qs.ui
import ".."

// Volume: icon + output %. Right-click mutes; the audio popup (devices, mic,
// per-app) opens via $mod+o a. Label keeps its width and text while muted so
// the bar never shifts under an open popup.
Segment {
    id: root
    readonly property var node: Pipewire.defaultAudioSink
    readonly property bool muted: node && node.audio ? node.audio.muted : true
    readonly property real vol: node && node.audio ? node.audio.volume : 0
    visible: node !== null
    icon: Icons.volumeFor(vol, muted)
    iconColor: muted ? Color.muted : Color.text
    label: Math.round(vol * 100) + "%"
    labelColor: muted ? Color.muted : Color.text
    labelTemplate: "99%"
    labelAlign: Text.AlignRight
    tooltip: "right-click: mute"
    active: popup.open

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    onClicked: m => {
        if (m.button === Qt.RightButton && node && node.audio)
            node.audio.muted = !node.audio.muted;
    }

    AudioPopup {
        id: popup
        anchorItem: root
    }
}
