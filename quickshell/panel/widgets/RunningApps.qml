pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.core
import qs.ui

// One icon per open window on this output (dwm-titus RunningAppsArea).
Pill {
    id: root
    property var screen
    readonly property var windows: ToplevelManager.toplevels.values.filter(t => !screen || t.screens.length === 0 || t.screens.includes(screen))

    visible: windows.length > 0
    hoverable: false

    function iconFor(t) {
        const e = DesktopEntries.heuristicLookup(t.appId);
        return Quickshell.iconPath(e && e.icon ? e.icon : t.appId, true);
    }

    content: Row {
        spacing: 4

        Repeater {
            model: root.windows

            Rectangle {
                id: item
                required property var modelData
                readonly property bool active: modelData === ToplevelManager.activeToplevel
                readonly property string iconPath: root.iconFor(modelData)
                width: 20
                height: 20
                radius: Style.radius - 1
                color: active ? Util.alpha(Color.accent, 0.35) : (mouse.containsMouse ? Color.pillHover : "transparent")

                IconImage {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    visible: item.iconPath !== ""
                    source: item.iconPath
                }
                Glyph {
                    anchors.centerIn: parent
                    visible: item.iconPath === ""
                    text: Icons.window
                    glyphColor: item.active ? Color.accent : Color.text
                    size: Style.fontSmall
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton)
                            item.modelData.close();
                        else
                            item.modelData.activate();
                    }
                }
            }
        }
    }
}
