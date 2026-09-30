import QtQuick
import Quickshell.Services.Pipewire
import qs.core
import qs.ui
import ".."

// Volume: icon + output %, click opens audio popup (in/out devices, mic),
// right-click mutes, wheel adjusts.
Segment {
    id: root
    readonly property var node: Pipewire.defaultAudioSink
    readonly property bool muted: node && node.audio ? node.audio.muted : true
    readonly property real vol: node && node.audio ? node.audio.volume : 0
    visible: node !== null
    icon: Icons.volumeFor(vol, muted)
    iconColor: muted ? Color.muted : Color.text
    label: muted ? "" : Math.round(vol * 100) + "%"
    tooltip: (node ? (node.description || node.name) : "") + (muted ? " · muted" : "") + " · right-click mute"
    active: popup.open

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    onClicked: m => {
        if (m.button === Qt.LeftButton) {
            popup.toggle();
            return;
        }
        if (node && node.audio)
            node.audio.muted = !node.audio.muted;
    }
    onWheel: w => {
        if (!node || !node.audio)
            return;
        const step = w.angleDelta.y > 0 ? 0.05 : -0.05;
        node.audio.volume = Util.clamp(node.audio.volume + step, 0, 1);
    }

    AudioPopup {
        id: popup
        anchorItem: root
    }
}
