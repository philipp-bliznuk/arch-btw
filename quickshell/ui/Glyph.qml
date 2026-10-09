import QtQuick
import qs.core

// Nerd Font glyph in a fixed-height box so it centres like a Label in a Row.
// Sized and centred by ink, not advance: many icons overhang their advance
// width, which otherwise pushes them past the right edge of a Segment.
// `alternatives` lists every glyph this slot may show (volume levels, battery
// steps); the box takes the widest so swapping the icon never shifts its
// neighbours.
Item {
    id: root

    property string text: ""
    property color glyphColor: Theme.icon
    property int size: Style.fontIcon
    property list<string> alternatives: []
    property real slotWidth: 0

    implicitWidth: Math.ceil(Math.max(metrics.tightBoundingRect.width, slotWidth))
    implicitHeight: Style.segmentHeight

    function measure() {
        let w = 0;
        for (const alt of alternatives) {
            probe.text = alt;
            w = Math.max(w, probe.tightBoundingRect.width);
        }
        slotWidth = w;
    }

    onAlternativesChanged: measure()
    Component.onCompleted: measure()

    TextMetrics {
        id: metrics
        font: glyph.font
        text: glyph.text
        renderType: glyph.renderType
    }

    TextMetrics {
        id: probe
        font: glyph.font
        renderType: glyph.renderType
        onFontChanged: root.measure()
    }

    Text {
        id: glyph
        x: Math.round((parent.width - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x)
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.family: Style.fontFamily
        font.pixelSize: root.size
        font.weight: Style.fontWeight
        color: root.glyphColor
        renderType: Style.renderType
    }
}
