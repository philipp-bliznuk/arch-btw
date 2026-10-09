pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.I3
import qs.core
import qs.ui

// Workspaces owned by this output. Focused = accent fill, urgent = red,
// dot = holds windows. Sway keeps a visible-but-empty workspace per output,
// so occupancy comes from get_workspaces' `representation` ("H[]" = empty);
// SwayState refreshes it when windows open, close, move or float.
Row {
    id: root
    property var screen
    readonly property var monitor: screen ? I3.monitorFor(screen) : null
    spacing: Style.spaceXs

    function occupied(ws) {
        const rep = ws.lastIpcObject ? ws.lastIpcObject.representation : null;
        return typeof rep === "string" && !rep.endsWith("[]");
    }

    Repeater {
        model: I3.workspaces

        Rectangle {
            id: ws
            required property I3Workspace modelData
            readonly property bool owned: !modelData.monitor || (root.monitor ? modelData.monitor === root.monitor : (!root.screen || modelData.monitor.name === root.screen.name))
            readonly property bool hovered: hover.hovered
            readonly property bool occupied: root.occupied(modelData)
            visible: owned
            width: visible ? Math.max(Style.segmentHeight, label.implicitWidth + Style.segmentPadX * 2) : 0
            height: Style.segmentHeight
            radius: Style.radius
            color: modelData.focused ? Theme.accent : (modelData.active ? Theme.segmentActive : (hovered ? Theme.segmentHover : "transparent"))

            Label {
                id: label
                anchors.centerIn: parent
                text: ws.modelData.name
                font.pixelSize: Style.fontSmall
                color: ws.modelData.focused ? Theme.base : (ws.modelData.urgent ? Theme.urgent : Theme.text)
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: 3
                height: 3
                radius: 1.5
                visible: !ws.modelData.focused && (ws.occupied || ws.modelData.urgent)
                color: ws.modelData.urgent ? Theme.urgent : Theme.overlay1
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
