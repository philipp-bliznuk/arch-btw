pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core

// Card anchored below a panel pill. Transparent click-away surface spans the
// output below the panel; Esc or outside click closes. Content sizes the card.
PopupWindow {
    id: root

    required property Item anchorItem
    readonly property var panel: anchorItem ? anchorItem.QsWindow.window : null
    required property string popupId
    property int cardWidth: Style.popupWidth
    default property alias content: host.data

    readonly property bool open: Popups.isOpen(popupId)
    readonly property int panelHeight: panel ? panel.height : 0

    visible: open
    color: "transparent"
    grabFocus: true
    implicitWidth: panel ? panel.width : 1
    implicitHeight: panel && panel.screen ? Math.max(1, panel.screen.height - panelHeight) : 1

    anchor {
        window: root.panel
        rect.x: 0
        rect.y: root.panelHeight
    }

    onOpenChanged: if (open) keys.forceActiveFocus()

    MouseArea {
        anchors.fill: parent
        onClicked: Popups.close()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Popups.close()
    }

    Rectangle {
        id: card
        readonly property real anchorX: root.anchorItem ? root.anchorItem.mapToItem(null, 0, 0).x + root.anchorItem.width / 2 : root.width / 2
        x: Math.round(Util.clamp(anchorX - width / 2, Style.barPadding, root.width - width - Style.barPadding))
        y: 4
        width: root.cardWidth
        height: host.childrenRect.height + Style.cardPadding * 2
        radius: Style.cardRadius
        color: Color.cardBg
        border.width: 1
        border.color: Color.cardBorder

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: host
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Style.cardPadding
            }
            height: childrenRect.height
        }
    }
}
