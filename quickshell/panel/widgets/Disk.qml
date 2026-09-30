import QtQuick
import qs.core
import qs.ui

Segment {
    icon: Icons.disk
    iconColor: Color.blue
    label: Metrics.disk
    tooltip: Metrics.disk + " free on /"
    onClicked: Commands.run({
        argv: Commands.term(["btop"])
    })
}
