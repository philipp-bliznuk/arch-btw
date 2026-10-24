import QtQuick
import qs.core
import qs.ui

// Night light (wlsunset 4000 K via bin/qs-toggle): always visible. Click
// toggles now; right-click flips the sunset/sunrise automation (core/Sun).
Segment {
    readonly property bool on: Toggles.has("nightlight")
    icon: Icons.nightlight
    iconColor: on ? Theme.peach : Theme.overlay1
    tooltip: "right-click: auto " + (Sun.auto ? "off" : "on")
    onClicked: Toggles.flip("nightlight")
    onRightClicked: Settings.set("nightLightAuto", !Sun.auto)
}
