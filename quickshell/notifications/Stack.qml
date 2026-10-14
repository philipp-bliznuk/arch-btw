pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Top-right popup stack. It opens on the focused output and stays there until
// the last toast is gone: following focus would re-map the window under a
// pointer that just crossed outputs. sway 1.12 sends no wl_pointer.enter to a
// layer surface mapped under a stationary pointer (handle_map rebases the
// cursor before the first buffer arrives), so such a card never reads as
// hovered and expires under the pointer. Mapping any other layer surface makes
// sway rebase against the drawn toast: the 1x1 nudge window below is shown on
// the first frame after a card appears and hidden 100 ms later (two rebases,
// the second one catches a frame drawn at the old size).
Scope {
    id: root
    required property var service

    PanelWindow {
        id: win
        // output name while toasts show, empty otherwise
        property string pinned: ""
        property bool nudgePending: false

        screen: SwayState.screenNamed(pinned) ?? SwayState.focusedScreen
        visible: root.service.popups.count > 0
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

        function repin() {
            if (root.service.popups.count === 0) {
                pinned = "";
                return;
            }
            if (SwayState.screenNamed(pinned))
                return;
            pinned = SwayState.focusedScreen ? SwayState.focusedScreen.name : "";
        }

        Connections {
            target: root.service.popups
            function onCountChanged() {
                win.repin();
            }
        }

        Connections {
            target: Quickshell
            function onScreensChanged() {
                win.repin();
            }
        }

        Connections {
            target: column.Window.window
            function onFrameSwapped() {
                if (!win.nudgePending)
                    return;
                win.nudgePending = false;
                nudge.visible = true;
                nudgeOff.restart();
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: 8

            Repeater {
                model: root.service.popups
                onItemAdded: win.nudgePending = true

                Card {
                    required property int index
                    width: column.width
                    visible: index < root.service.maxVisible
                    service: root.service
                    timeout: root.service.timeoutFor(notification)
                }
            }
        }
    }

    PanelWindow {
        id: nudge
        visible: false
        screen: win.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-nudge"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors {
            bottom: true
            left: true
        }
        implicitWidth: 1
        implicitHeight: 1
        mask: Region {}
    }

    Timer {
        id: nudgeOff
        interval: 100
        onTriggered: nudge.visible = false
    }
}
