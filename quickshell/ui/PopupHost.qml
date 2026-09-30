pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// One overlay layer per output that hosts whichever PopupCard is open there.
// PopupCards live inside widgets but reparent their card into this window,
// so nothing nests windows (hot reload safe) and keyboard focus comes from
// the layer — works for keybind/IPC opens, unlike xdg popup grabs.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: host
        required property var modelData
        readonly property bool open: Popups.current !== "" && Popups.sameScreen(Popups.screen, modelData)

        screen: modelData
        visible: open
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        margins.top: Style.panelHeight // qmllint disable unqualified
        WlrLayershell.namespace: "qs-popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Component.onCompleted: Popups.registerHost(modelData, slot)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: Popups.close()
        }

        Item {
            id: slot
            anchors.fill: parent
        }
    }
}
