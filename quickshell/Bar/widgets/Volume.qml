import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

Pill {
    id: root
    readonly property var node: Pipewire.defaultAudioSink
    readonly property bool muted: node && node.audio ? node.audio.muted : true
    readonly property real vol: node && node.audio ? node.audio.volume : 0
    visible: node !== null
    icon: Icons.volumeFor(vol, muted)
    iconColor: muted ? Color.muted : Color.text
    label: muted ? "" : Math.round(vol * 100) + "%"
    labelSize: Style.fontSmall

    PwObjectTracker {
        objects: root.node ? [root.node] : []
    }

    onClicked: {
        if (node && node.audio)
            node.audio.muted = !node.audio.muted
    }
    onWheel: w => {
        if (!node || !node.audio)
            return
        const step = w.angleDelta.y > 0 ? 0.05 : -0.05
        node.audio.volume = Util.clamp(node.audio.volume + step, 0, 1)
    }
}
