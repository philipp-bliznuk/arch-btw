import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import "widgets"

// Solid bar: flat segments, one popup at a time. One instance per output.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel
        required property var modelData

        screen: modelData
        readonly property bool fullscreen: SwayState.fullscreenOn(modelData)
        visible: !Toggles.has("bar-hidden") && !fullscreen
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: Style.panelHeight
        exclusionMode: ExclusionMode.Auto
        color: Theme.panelBg

        WlrLayershell.namespace: "qs-bar"
        WlrLayershell.layer: WlrLayer.Top

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.panelLine
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: Style.spaceXs
            anchors.rightMargin: Style.spaceXs
            anchors.bottomMargin: 1

            Row {
                id: left
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Workspaces {
                    screen: panel.screen
                }
                Disk {}
                Ram {}
                Cpu {}
                Gpu {}
                NetRate {}
            }

            Mode {
                id: modeHint
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }

            Media {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // stay clear of both rows and yield the centre to the mode indicator
                visible: !modeHint.visible && Player.player !== null && width < right.x - (left.x + left.width) - Style.spaceXl * 2
            }

            Row {
                id: right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Tray {}
                Weather {}
                Indicators {}
                Dnd {}
                NightLight {}
                Volume {}
                Network {}
                Battery {}
                KeyboardLayout {}
                Clock {}
            }
        }
    }
}
