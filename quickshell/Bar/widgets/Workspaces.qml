import QtQuick
import Quickshell
import Quickshell.I3
import qs.Commons

Row {
    id: root
    property var screen
    readonly property var monitor: screen ? I3.monitorFor(screen) : null
    spacing: 2

    Repeater {
        model: I3.workspaces

        Rectangle {
            required property I3Workspace modelData
            readonly property bool onThisMonitor: !root.monitor || !modelData.monitor || modelData.monitor === root.monitor
            visible: onThisMonitor
            width: visible ? Math.max(Style.pillHeight, label.implicitWidth + Style.pillPadding * 2) : 0
            height: Style.pillHeight
            radius: Style.radius
            color: modelData.focused ? Color.accent : (hover.containsMouse ? Color.pillHover : Color.pillBg)
            border.width: 1
            border.color: modelData.urgent ? Color.urgent : Color.pillBorder

            Text {
                id: label
                anchors.centerIn: parent
                text: parent.modelData.name
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                color: parent.modelData.focused ? Color.base : (parent.modelData.urgent ? Color.urgent : Color.text)
            }

            MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: parent.modelData.activate()
            }
        }
    }
}
