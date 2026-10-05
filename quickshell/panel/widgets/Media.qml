import QtQuick
import qs.core
import qs.ui
import ".."

// Now playing, centred in the bar. Display only: the global $mod+p / $mod+[ ]
// binds drive playback, $mod+Shift+p or $mod+o m opens the popup. Dimmed
// while paused; Panel hides it when no player exists. Long titles scroll once
// every 10 s (ui/Marquee) instead of being cut.
Segment {
    id: root
    readonly property var player: Player.player
    hoverable: false
    icon: Player.playing ? Icons.music : Icons.pause
    iconColor: Player.playing ? Color.sky : Color.muted
    active: popup.open

    content: Marquee {
        height: parent.height
        maxWidth: Style.mediaWidth
        text: Player.line || (root.player ? root.player.identity : "")
        color: Player.playing ? Color.text : Color.muted
    }

    MediaPopup {
        id: popup
        anchorItem: root
    }
}
