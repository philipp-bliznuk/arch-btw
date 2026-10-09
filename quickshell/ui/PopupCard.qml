pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import "KeyModel.js" as KeyModel

// Card popup under a bar segment. Declared inside the widget, but the card
// reparents into the per-output PopupHost layer so the panel never nests
// windows. Sized to content; slides horizontally to stay on the output.
//
// Keys: `keymap` is a list of { key, run } tried first against the typed
// character ("Enter", "Space", "Left/Right/Up/Down" for those keys; `key` may
// list alternatives separated by spaces, run(k) receives the one pressed).
// Esc/q always close; then j/k/arrows move `cursor` over `count` rows.
// No on-screen legend: keys live in README.
Rectangle {
    id: root

    required property Item anchorItem
    required property string popupId
    property int cardWidth: Style.popupWidth
    default property alias content: host.data
    readonly property var ownerWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property var ownerScreen: ownerWindow ? ownerWindow.screen : null
    readonly property bool open: Popups.isOpenOn(popupId, ownerScreen)

    property int count: 0
    property int cursor: 0
    property var keymap: []
    readonly property var arrowNames: ({ [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down" })

    function toggle() {
        Popups.toggle(popupId, ownerScreen);
    }

    function focusKeys() {
        keys.forceActiveFocus();
    }

    function keyName(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            return "Enter";
        if (event.key === Qt.Key_Space)
            return "Space";
        return arrowNames[event.key] ?? event.text;
    }

    function dispatch(event) {
        const name = keyName(event);
        if (name === "" || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            return false;
        const hit = keymap.find(k => k.key.split(" ").includes(name));
        if (!hit)
            return false;
        hit.run(name);
        return true;
    }

    parent: Popups.hostFor(ownerScreen)
    visible: open && parent !== null

    // mapToItem is not reactive; measure on open and hold still while open so
    // a segment changing width (mute, % toggle) never drags the card around.
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
    color: Theme.cardBg
    border.width: 1
    border.color: Theme.cardBorder

    onOpenChanged: {
        cursor = 0;
        if (open) {
            place();
            keys.forceActiveFocus();
        }
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
            if (root.dispatch(event)) {
                event.accepted = true;
                return;
            }
            const a = KeyModel.normal(event);
            event.accepted = a !== "";
            if (a === "escape" || a === "close") {
                Popups.close();
                return;
            }
            const next = KeyModel.step(a, root.cursor, root.count, 5);
            if (next >= 0)
                root.cursor = next;
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
