import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

Pill {
    id: root
    readonly property var player: {
        const ps = Mpris.players.values
        for (const p of ps)
            if (p.isPlaying)
                return p
        return null
    }
    visible: player !== null
    icon: Icons.music
    iconColor: Color.sky
    label: player ? Util.truncate((player.trackArtist ? player.trackArtist + " - " : "") + (player.trackTitle || ""), 35) : ""
    labelSize: Style.fontSmall
    onClicked: mouse => {
        if (!player)
            return
        if (mouse.button === Qt.MiddleButton)
            player.next()
        else if (player.canTogglePlaying)
            player.togglePlaying()
    }
}
