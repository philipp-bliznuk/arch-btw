import QtQuick
import qs.core
import qs.ui

Segment {
    icon: Icons.cpu
    iconColor: Theme.green
    label: Metrics.cpu + "%"
    labelTemplate: "99%"
    labelAlign: Text.AlignRight
    hoverable: false
}
