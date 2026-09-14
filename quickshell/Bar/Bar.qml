import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "widgets"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel
        required property var modelData

        screen: modelData
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

                Workspaces {
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

                Tray {}
                Mic {}
                Volume {}
                Network {}
                Battery {}
                KeyboardLayout {}
                Clock {}
            }
        }
    }
}
