pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// One lock surface per output: blurred wallpaper, clock, password field.
// Typed text lives in the service so every output shows the same dots;
// whichever surface holds the keyboard edits it.
WlSessionLockSurface {
    id: surface

    required property var service

    color: Theme.base

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Util.fileUrl(surface.service.wallpaper)
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: surface.screen ? surface.screen.width : surface.width
        sourceSize.height: surface.screen ? surface.screen.height : surface.height
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: wallpaper
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        // cache the blur: the cursor blink would re-render it every 500 ms
        layer.enabled: true
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -surface.height / 10
        spacing: Style.spaceLg

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: 88
            font.weight: Font.Bold
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
            font.pixelSize: Style.fontTitle
            color: Theme.subtext0
        }

        Item {
            width: 1
            height: Style.spaceXl * 3
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: Style.rowHeight + 4
            radius: Style.cardRadius
            color: Theme.cardBg
            border.width: 1
            border.color: input.activeFocus ? Theme.accent : Theme.cardBorder
            opacity: surface.service.authenticating ? 0.6 : 1

            Glyph {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Style.spaceLg
                anchors.verticalCenter: parent.verticalCenter
                text: surface.service.fidoPresent ? Icons.shield : Icons.lock
                alternatives: [Icons.shield, Icons.lock]
                glyphColor: Theme.muted
            }

            TextInput {
                id: input
                anchors.left: icon.right
                anchors.right: parent.right
                anchors.leftMargin: Style.spaceLg
                anchors.rightMargin: Style.spaceLg
                anchors.verticalCenter: parent.verticalCenter
                echoMode: TextInput.Password
                passwordMaskDelay: 0
                color: Theme.text
                font.family: Style.fontFamily
                font.pixelSize: Style.fontTitle
                font.weight: Style.fontWeight
                renderType: Style.renderType
                readOnly: surface.service.authenticating
                focus: true
                clip: true
                onTextEdited: surface.service.typed = text
                onAccepted: surface.service.submit()
                Keys.onPressed: event => {
                    const clear = event.key === Qt.Key_Escape || (event.key === Qt.Key_U && event.modifiers & Qt.ControlModifier);
                    if (!clear)
                        return;
                    event.accepted = true;
                    surface.service.typed = "";
                }

                Connections {
                    target: surface.service

                    function onTypedChanged() {
                        if (input.text !== surface.service.typed)
                            input.text = surface.service.typed;
                    }
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: surface.service.status || surface.service.hint
            font.pixelSize: Style.fontSmall
            color: surface.service.statusIsError ? Theme.urgent : Theme.muted
        }
    }
}
