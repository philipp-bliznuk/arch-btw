pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.ui

// Tray item menu rendered as a popup card (quickshell is not in QApplication
// mode, so platform menus are unavailable). `stack` holds the open menu chain:
// the item's root menu first, then every submenu descended into.
//
// Keys: j/k row · l/Enter activate or descend · h back · q/Esc close.
PopupCard {
    id: root
    popupId: "tray"
    cardWidth: 240

    // Segment the card falls back to once the clicked icon is gone (app quit).
    required property Item home
    property var stack: []
    readonly property QsMenuOpener level: levels.count > 0 ? levels.objectAt(levels.count - 1) as QsMenuOpener : null
    readonly property var entries: level ? level.children.values : []
    readonly property var actionable: entries.filter(e => !e.isSeparator)
    count: actionable.length

    function show(target, handle) {
        anchorItem = target;
        stack = [handle];
        if (!open)
            toggle();
    }

    function selected() {
        return actionable[cursor] ?? null;
    }

    function activate(entry) {
        if (!entry || !entry.enabled)
            return;
        if (entry.hasChildren) {
            stack = stack.concat([entry]);
            cursor = 0;
            return;
        }
        entry.triggered();
        Popups.close();
    }

    function back() {
        if (stack.length > 1) {
            stack = stack.slice(0, -1);
            cursor = 0;
        } else {
            Popups.close();
        }
    }

    onOpenChanged: {
        if (open)
            return;
        stack = [];
        anchorItem = home;
    }

    keymap: [
        { key: "l Right Enter", run: () => root.activate(root.selected()) },
        { key: "h Left", run: () => root.back() }
    ]

    // Every level stays referenced while descended: releasing a parent menu
    // invalidates the submenu entries below it. The last level is the one shown.
    Instantiator {
        id: levels
        model: root.stack
        QsMenuOpener {
            required property var modelData
            menu: modelData
        }
    }

    Column {
        width: parent.width
        spacing: 2

        Label {
            visible: root.entries.length === 0
            text: "Empty menu"
            color: Theme.muted
            leftPadding: Style.spaceMd
            height: Style.rowHeight
        }

        Repeater {
            model: root.entries

            Item {
                id: row
                required property var modelData
                readonly property bool checked: modelData.checkState === Qt.Checked
                width: parent.width
                height: modelData.isSeparator ? Style.spaceSm : Style.rowHeight

                Rectangle {
                    visible: row.modelData.isSeparator
                    anchors.centerIn: parent
                    width: parent.width - Style.spaceMd * 2
                    height: 1
                    color: Theme.cardBorder
                }

                ListRow {
                    visible: !row.modelData.isSeparator
                    iconSource: row.modelData.icon
                    title: row.modelData.text
                    dim: !row.modelData.enabled
                    selected: root.selected() === row.modelData
                    trailing: row.modelData.hasChildren ? "›" : (row.checked ? "✓" : "")
                    trailingColor: row.checked ? Theme.accent : Theme.muted
                    onHoveredChanged: {
                        const i = root.actionable.indexOf(row.modelData);
                        if (hovered && i >= 0)
                            root.cursor = i;
                    }
                    onClicked: root.activate(row.modelData)
                }
            }
        }
    }
}
