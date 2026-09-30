pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.I3
import qs.core
import qs.ui

// Workspaces owned by this output. Focused = accent fill, urgent = red,
// every other listed workspace is occupied (sway drops empty ones) → dot.
Row {
    id: root
    property var screen
    readonly property var monitor: screen ? I3.monitorFor(screen) : null
    spacing: Style.spaceXs

    Repeater {
        model: I3.workspaces

        Rectangle {
            id: ws
            required property I3Workspace modelData
            readonly property bool owned: !modelData.monitor || (root.monitor ? modelData.monitor === root.monitor : (!root.screen || modelData.monitor.name === root.screen.name))
            readonly property bool hovered: hover.hovered
            visible: owned
            width: visible ? Math.max(Style.segmentHeight, label.implicitWidth + Style.segmentPadX * 2) : 0
            height: Style.segmentHeight
            radius: Style.radius
            color: modelData.focused ? Color.accent : (modelData.active ? Color.segmentActive : (hovered ? Color.segmentHover : "transparent"))

            Label {
                id: label
                anchors.centerIn: parent
                text: ws.modelData.name
                font.pixelSize: Style.fontSmall
                color: ws.modelData.focused ? Color.base : (ws.modelData.urgent ? Color.urgent : Color.text)
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: 3
                height: 3
                radius: 1.5
                visible: !ws.modelData.focused
                color: ws.modelData.urgent ? Color.urgent : Color.overlay1
            }

            HoverHandler {
                id: hover
            }

            MouseArea {
                anchors.fill: parent
                onClicked: ws.modelData.activate()
                onWheel: w => I3.dispatch(w.angleDelta.y > 0 ? "workspace prev_on_output" : "workspace next_on_output")
            }
        }
    }
}
