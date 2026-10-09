import QtQuick
import qs.core
import qs.ui

Segment {
    icon: Icons.memory
    iconColor: Theme.peach
    label: Metrics.mem + "%"
    labelTemplate: "99%"
    labelAlign: Text.AlignRight
    hoverable: false
}
