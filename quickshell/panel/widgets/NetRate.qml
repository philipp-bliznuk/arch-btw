import QtQuick
import qs.core
import qs.ui

// ⇡ up · ⇣ down. Both labels share one fixed width (widest sample) and the
// number is padded to three characters, so the left row does not shift and
// the unit stays in place as the digits change.
Segment {
    id: root
    hoverable: false

    function pad(rate) {
        const i = rate.indexOf(" ");
        return rate.slice(0, i).padStart(3) + rate.slice(i);
    }

    TextMetrics {
        id: metrics
        font.family: Style.fontFamily
        font.pixelSize: Style.fontSmall
        font.weight: Style.fontWeight
        renderType: Style.renderType
        text: Icons.arrowUp + " 999 KiB/s"
    }

    content: Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spaceSm

        Label {
            width: Math.ceil(metrics.advanceWidth) + 2
            height: Style.segmentHeight
            text: Icons.arrowUp + " " + root.pad(Metrics.up)
            color: Color.green
            font.pixelSize: Style.fontSmall
        }
        Label {
            width: Math.ceil(metrics.advanceWidth) + 2
            height: Style.segmentHeight
            text: Icons.arrowDown + " " + root.pad(Metrics.down)
            color: Color.red
            font.pixelSize: Style.fontSmall
        }
    }
}
