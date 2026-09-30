pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import "KeyModel.js" as KeyModel

// Card popup under a bar segment. Declared inside the widget, but the card
// reparents into the per-output PopupHost layer so the panel never nests
// windows. Sized to content; slides horizontally to stay on the output.
//
// Vim keys: j/k move `cursor` over `count` rows, Enter/h/l/y/m… are emitted
// as `action(name)` for the popup to interpret. Arrows work too.
Rectangle {
    id: root

    required property Item anchorItem
    required property string popupId
    property int cardWidth: Style.popupWidth
    default property alias content: host.data
    readonly property var ownerWindow: anchorItem.QsWindow.window
    readonly property var ownerScreen: ownerWindow ? ownerWindow.screen : null
    readonly property bool open: Popups.isOpenOn(popupId, ownerScreen)

    property int count: 0
    property int cursor: 0

    signal action(string name)

    function toggle() {
        Popups.toggle(popupId, ownerScreen);
    }

    parent: Popups.hostFor(ownerScreen)
    visible: open && parent !== null

    // mapToItem is not reactive; re-measure whenever we open or the bar moves.
    property real anchorX: 0
    function place() {
        if (anchorItem)
            anchorX = anchorItem.mapToItem(null, 0, 0).x + anchorItem.width / 2;
    }
    x: parent ? Math.round(Util.clamp(anchorX - width / 2, Style.spaceXs, parent.width - width - Style.spaceXs)) : 0
    y: Style.spaceXs
    width: cardWidth
    height: host.childrenRect.height + Style.cardPadding * 2
    radius: Style.cardRadius
    color: Color.cardBg
    border.width: 1
    border.color: Color.cardBorder

    onOpenChanged: {
        cursor = 0;
        if (open) {
            place();
            keys.forceActiveFocus();
        }
    }

    Connections {
        target: root.anchorItem
        function onXChanged() { root.place(); }
        function onWidthChanged() { root.place(); }
    }
    onCountChanged: cursor = Math.min(cursor, Math.max(0, count - 1))

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const a = KeyModel.normal(event);
            event.accepted = a !== "";
            if (a === "escape" || a === "close") {
                Popups.close();
                return;
            }
            const next = KeyModel.step(a, root.cursor, root.count, 5);
            if (next >= 0)
                root.cursor = next;
            else if (a)
                root.action(a);
        }
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
