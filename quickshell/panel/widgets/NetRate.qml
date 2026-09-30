import QtQuick
import qs.core
import qs.ui

// ⇡ up · ⇣ down (sketchybar network_rates).
Segment {
    tooltip: "↑ " + Metrics.up + " · ↓ " + Metrics.down
    onClicked: Commands.run({
        argv: Commands.term(["nmtui"])
    })

    content: Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spaceSm

        Label {
            height: Style.segmentHeight
            text: Icons.arrowUp + " " + Metrics.up
            color: Color.green
            font.pixelSize: Style.fontSmall
        }
        Label {
            height: Style.segmentHeight
            text: Icons.arrowDown + " " + Metrics.down
            color: Color.red
            font.pixelSize: Style.fontSmall
        }
    }
}
