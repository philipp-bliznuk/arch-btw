import QtQuick
import qs.core
import qs.ui

Segment {
    icon: Icons.memory
    iconColor: Color.peach
    label: Metrics.mem + "%"
    tooltip: "Memory " + Metrics.memUsed
    onClicked: Commands.run({
        argv: Commands.term(["btop"])
    })
}
