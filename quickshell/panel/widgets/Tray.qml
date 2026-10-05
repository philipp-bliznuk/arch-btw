pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core
import qs.ui
import ".."

// Tray icons. Left click activates, middle click secondary-activates,
// right click (or left click on menu-only items) opens the item's menu as a
// popup card under the icon. Each item's menu layout is fetched once when the
// item appears, so the first open is already populated.
Segment {
    id: root
    visible: SystemTray.items.values.length > 0
    hoverable: false

    TrayMenu {
        id: menu
        home: root
        anchorItem: root
    }

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

                QsMenuOpener {
                    menu: item.modelData.menu
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: m => {
                        const it = item.modelData;
                        if (m.button === Qt.RightButton || it.onlyMenu) {
                            if (it.hasMenu)
                                menu.show(item, it.menu);
                        } else if (m.button === Qt.MiddleButton) {
                            it.secondaryActivate();
                        } else {
                            it.activate();
                        }
                    }
                }
            }
        }
    }
}
