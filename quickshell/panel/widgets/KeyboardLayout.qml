import QtQuick
import qs.core
import qs.ui

// Active xkb layout, fed by SwayState's `input` subscription (instant,
// no polling). Switch with Alt+Shift (sway/config xkb_options).
Segment {
    icon: Icons.keyboard
    label: SwayState.layoutShort
    visible: label !== ""
    hoverable: false
}
