import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import "widgets"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel
        required property var modelData

        screen: modelData
        readonly property bool fullscreen: ToplevelManager.toplevels.values.some(t => t.fullscreen && (t.screens.length === 0 || t.screens.includes(panel.screen)))
        visible: !Toggles.has("bar-hidden") && !fullscreen
        anchors {
            top: true
            left: true
            right: true
        }
        implicitHeight: Style.barHeight
        exclusionMode: ExclusionMode.Auto
        color: Color.barBg

        WlrLayershell.namespace: "qs-bar"
        WlrLayershell.layer: WlrLayer.Top

        Item {
            anchors.fill: parent
            anchors.leftMargin: Style.barPadding
            anchors.rightMargin: Style.barPadding

            Row {
                id: left
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.pillGap

                Menu {}
                Workspaces {
                    screen: panel.screen
                }
                RunningApps {
                    screen: panel.screen
                }
                Disk {}
                Ram {}
                Cpu {}
                NetRate {}
                Media {}
            }

            ActiveWindow {
                anchors.centerIn: parent
                maxWidth: parent.width - left.width - right.width - Style.pillGap * 4
            }

            Row {
                id: right
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.pillGap

                Indicators {}
                Tray {}
                Mic {}
                Volume {}
                BluetoothPill {}
                Network {}
                Battery {}
                KeyboardLayout {}
                Clock {}
            }
        }
    }
}
