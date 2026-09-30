pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs.core
import qs.ui

// Media popup: art, track, seek bar, transport, player volume, player chips.
// Keys: Enter play/pause · h/l prev/next · H/L seek ±10 s · j/k volume ±5 %
//       · s shuffle · r loop · Esc/q close.
PopupCard {
    id: root
    popupId: "media"
    cardWidth: 340

    readonly property var player: Player.player
    readonly property bool has: player !== null
    // Firefox drops mpris:length between tracks/buffering; remember the last
    // non-zero value for the current track so the seek row never flickers.
    property real length: 0
    readonly property real position: has && player.positionSupported ? player.position : 0
    readonly property real reported: has && player.lengthSupported ? player.length : 0
    readonly property string track: Player.title + "|" + Player.album
    readonly property bool seekable: has && player.canSeek && length > 0
    onReportedChanged: if (reported > 0) length = reported
    onTrackChanged: length = reported

    onAction: a => {
        switch (a) {
        case "activate":
            Player.toggle();
            break;
        case "left":
            Player.previous();
            break;
        case "right":
            Player.next();
            break;
        case "leftBig":
            Player.seek(-10);
            break;
        case "rightBig":
            Player.seek(10);
            break;
        case "down":
            Player.nudgeVolume(-0.05);
            break;
        case "up":
            Player.nudgeVolume(0.05);
            break;
        case "shuffle":
            Player.toggleShuffle();
            break;
        case "loop":
            Player.cycleLoop();
            break;
        }
    }

    // MPRIS position does not tick on its own; poll while visible.
    Timer {
        interval: 1000
        running: root.open && root.has && root.player.isPlaying
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    component Button: Segment {
        property bool enabledState: true
        opacity: enabledState ? 1 : 0.35
        hoverable: enabledState
    }

    Column {
        width: parent.width
        spacing: Style.spaceMd

        Row {
            width: parent.width
            spacing: Style.spaceLg

            Rectangle {
                width: 72
                height: 72
                radius: Style.radius
                color: Color.surface0
                clip: true

                Image {
                    anchors.fill: parent
                    source: Player.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 144
                    visible: status === Image.Ready
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: Player.artUrl === ""
                    text: Icons.music
                    glyphColor: Color.overlay1
                    size: Style.fontTitle + 8
                }
            }

            Column {
                width: parent.width - 72 - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    width: parent.width
                    text: Player.title || (root.has ? root.player.identity : "Nothing playing")
                    font.pixelSize: Style.fontBody
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: Player.artist
                    color: Color.subtext1
                    font.pixelSize: Style.fontSmall
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: Player.album
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                }
            }
        }

        Column {
            width: parent.width
            spacing: 2

            Slider {
                width: parent.width
                value: root.length > 0 ? Util.clamp(root.position / root.length, 0, 1) : 0
                fill: Color.sky
                muted: !root.seekable
                onMoved: v => {
                    if (root.seekable)
                        root.player.position = v * root.length;
                }
            }
            Row {
                width: parent.width

                Label {
                    text: Player.fmt(root.position)
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                }
                Item {
                    width: parent.width - x - end.width
                    height: 1
                }
                Label {
                    id: end
                    text: root.length > 0 ? Player.fmt(root.length) : "–:––"
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spaceMd

            Button {
                icon: root.has && root.player.shuffle ? Icons.shuffle : Icons.shuffleOff
                iconColor: root.has && root.player.shuffle ? Color.sky : Color.muted
                enabledState: root.has && root.player.shuffleSupported
                onClicked: Player.toggleShuffle()
            }
            Button {
                icon: Icons.skipPrev
                enabledState: root.has && root.player.canGoPrevious
                onClicked: Player.previous()
            }
            Button {
                icon: Player.playing ? Icons.pause : Icons.play
                iconColor: Color.sky
                labelSize: Style.fontTitle
                enabledState: root.has && root.player.canTogglePlaying
                onClicked: Player.toggle()
            }
            Button {
                icon: Icons.skipNext
                enabledState: root.has && root.player.canGoNext
                onClicked: Player.next()
            }
            Button {
                readonly property int loop: root.has ? root.player.loopState : MprisLoopState.None
                icon: loop === MprisLoopState.Track ? Icons.repeatOnce : (loop === MprisLoopState.Playlist ? Icons.repeat : Icons.repeatOff)
                iconColor: loop === MprisLoopState.None ? Color.muted : Color.sky
                enabledState: root.has && root.player.loopSupported
                onClicked: Player.cycleLoop()
            }
        }

        Row {
            width: parent.width
            spacing: Style.spaceMd
            visible: root.has && root.player.volumeSupported

            Glyph {
                text: Icons.volumeFor(root.has ? root.player.volume : 0, false)
                glyphColor: Color.muted
            }
            Slider {
                width: parent.width - Style.segmentHeight - 40 - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                value: root.has ? root.player.volume : 0
                onMoved: v => {
                    if (root.has)
                        root.player.volume = v;
                }
            }
            Label {
                width: 40
                height: Style.segmentHeight
                horizontalAlignment: Text.AlignRight
                text: root.has ? Math.round(root.player.volume * 100) + "%" : ""
                font.pixelSize: Style.fontSmall
            }
        }

        Row {
            spacing: Style.spaceXs
            visible: Player.players.length > 1

            Repeater {
                model: Player.players

                Chip {
                    required property var modelData
                    text: modelData.identity
                    active: modelData === root.player
                }
            }
        }
    }
}
