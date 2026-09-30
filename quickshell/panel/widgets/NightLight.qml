import QtQuick
import qs.core
import qs.ui

// Night light (wlsunset 4000 K via bin/qs-toggle): always visible, click toggles.
Segment {
    readonly property bool on: Toggles.has("nightlight")
    icon: Icons.nightlight
    iconColor: on ? Color.peach : Color.overlay1
    tooltip: on ? "Night light 4000 K · click for daylight" : "Daylight · click for night light"
    onClicked: Toggles.flip("nightlight")
}
