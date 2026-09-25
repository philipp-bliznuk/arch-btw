pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Top-right popup stack on the focused output.
PanelWindow {
    id: win
    required property var service

    screen: SwayState.focusedScreen
    visible: service.visible.length > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: true
        right: true
    }
    // qmllint disable unqualified
    margins {
        top: 8
        right: 8
    }
    // qmllint enable unqualified
    implicitWidth: Style.notifWidth
    implicitHeight: Math.max(1, column.implicitHeight)

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: win.service.visible

            Card {
                required property var modelData
                width: column.width
                notification: modelData
                timeout: win.service.timeoutFor(modelData)
            }
        }
    }
}
