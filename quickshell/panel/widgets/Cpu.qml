import QtQuick
import qs.core
import qs.ui

Segment {
    icon: Icons.cpu
    iconColor: Color.green
    label: Metrics.cpu + "%"
    tooltip: "CPU " + Metrics.cpu + "% · click btop"
    onClicked: Commands.run({
        argv: Commands.term(["btop"])
    })
}
