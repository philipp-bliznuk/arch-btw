import QtQuick
import qs.core
import qs.ui

// Active xkb layout, fed by SwayState's `input` subscription (instant,
// no polling). Switch with Alt+Shift (sway/config xkb_options).
Segment {
    id: root
    readonly property string layout: shortName(SwayState.layoutName)
    icon: Icons.keyboard
    label: layout
    visible: layout !== ""
    hoverable: false

    function shortName(name) {
        if (!name)
            return "";
        const n = name.toLowerCase();
        if (n.startsWith("english"))
            return "US";
        if (n.startsWith("ukrain"))
            return "UA";
        if (n.startsWith("russ"))
            return "RU";
        return name.split(" ")[0].slice(0, 2).toUpperCase();
    }
}
