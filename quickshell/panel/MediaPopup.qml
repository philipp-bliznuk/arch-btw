pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// Media popup: art, track, transport, volume of the player's PipeWire stream.
// Keys: p play/pause · h/l or [ ] prev/next · j/k volume ±5 %.
PopupCard {
    id: root
    popupId: "media"
    cardWidth: 340

    readonly property var player: Player.player
    readonly property bool has: player !== null

    keymap: [
        { key: "p", run: () => Player.toggle() },
        { key: "h l [ ]", run: k => k === "h" || k === "[" ? Player.previous() : Player.next() },
        { key: "j k", run: k => Player.nudgeVolume(k === "j" ? -0.05 : 0.05) }
    ]

    PwObjectTracker {
        objects: root.open ? Player.streams : []
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
                    id: art
                    anchors.fill: parent
                    source: Player.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 144
                    visible: status === Image.Ready
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
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

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spaceMd

            Button {
                icon: Icons.skipPrev
                enabledState: root.has && root.player.canGoPrevious
                onClicked: Player.previous()
            }
            Button {
                icon: Player.playing ? Icons.pause : Icons.play
                iconColor: Color.sky
                enabledState: root.has && root.player.canTogglePlaying
                onClicked: Player.toggle()
            }
            Button {
                icon: Icons.skipNext
                enabledState: root.has && root.player.canGoNext
                onClicked: Player.next()
            }
        }

        Row {
            width: parent.width
            spacing: Style.spaceMd
            visible: Player.volumeSupported

            Glyph {
                id: volGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.volumeFor(Player.volume, false)
                glyphColor: Color.muted
            }
            Slider {
                width: parent.width - volGlyph.width - volLabel.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                value: Player.volume / Player.volumeMax
                onMoved: v => Player.setVolume(v * Player.volumeMax)
            }
            Label {
                id: volLabel
                width: 40
                height: Style.segmentHeight
                horizontalAlignment: Text.AlignRight
                text: Math.round(Player.volume * 100) + "%"
                font.pixelSize: Style.fontSmall
            }
        }
    }
}
