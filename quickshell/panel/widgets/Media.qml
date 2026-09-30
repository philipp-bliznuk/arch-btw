import QtQuick
import qs.core
import qs.ui
import ".."

// Now playing, centred in the bar. Click play/pause · middle next ·
// right-click popup. Dimmed while paused, hidden when no player exists.
Segment {
    id: root
    readonly property var player: Player.player
    visible: player !== null
    icon: Player.playing ? Icons.music : Icons.pause
    iconColor: Player.playing ? Color.sky : Color.muted
    label: Util.truncate(Player.line || (player ? player.identity : ""), 35)
    labelColor: Player.playing ? Color.text : Color.muted
    tooltip: player ? [player.identity, Player.album, Player.fmt(player.position) + " / " + Player.fmt(player.length)].filter(x => x).join(" · ") + " · Super+Shift+p" : ""
    active: popup.open

    onClicked: m => {
        if (m.button === Qt.MiddleButton)
            Player.next();
        else if (m.button === Qt.RightButton)
            popup.toggle();
        else
            Player.toggle();
    }

    MediaPopup {
        id: popup
        anchorItem: root
    }
}
