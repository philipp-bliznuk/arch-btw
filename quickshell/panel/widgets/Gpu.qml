import QtQuick
import qs.core
import qs.ui

// Render busy % (see core/Metrics for sources).
Segment {
    icon: Icons.gpu
    iconColor: Color.mauve
    label: Metrics.gpu + "%"
    labelTemplate: "99%"
    labelAlign: Text.AlignRight
    hoverable: false
}
