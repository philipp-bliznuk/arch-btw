pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core
import qs.ui

Segment {
    id: root
    visible: SystemTray.items.values.length > 0
    hoverable: false

    content: Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spaceSm

        Repeater {
            model: SystemTray.items

            Item {
                id: item
                required property SystemTrayItem modelData
                width: 16
                height: 16

                IconImage {
                    anchors.fill: parent
                    source: item.modelData.icon
                }

                QsMenuAnchor {
                    id: menu
                    menu: item.modelData.menu
                    anchor.item: item
                    anchor.edges: Edges.Bottom
                }

                HoverHandler {
                    id: hover
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: m => {
                        const it = item.modelData;
                        if (m.button === Qt.RightButton || it.onlyMenu) {
                            if (it.hasMenu)
                                menu.open();
                        } else if (m.button === Qt.MiddleButton) {
                            it.secondaryActivate();
                        } else {
                            it.activate();
                        }
                    }
                }

                Tooltip {
                    target: item
                    hovered: hover.hovered
                    text: item.modelData.tooltipTitle || item.modelData.title || item.modelData.id
                }
            }
        }
    }
}
