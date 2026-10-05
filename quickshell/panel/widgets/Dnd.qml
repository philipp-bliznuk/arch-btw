import QtQuick
import qs.core
import qs.ui

// Do not disturb: always visible, click toggles the
// `dnd` flag (bin/qs-toggle) that notifications/Service honours.
Segment {
    readonly property bool on: Toggles.has("dnd")
    icon: Icons.bellOff
    iconColor: on ? Color.yellow : Color.overlay1
    onClicked: Toggles.flip("dnd")
}
