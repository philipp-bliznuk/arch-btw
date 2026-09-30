import QtQuick
import qs.core

// Nerd Font glyph in a fixed-height box so it centres like a Label in a Row.
// Sized and centred by ink, not advance: many icons overhang their advance
// width, which otherwise pushes them past the right edge of a Segment.
Item {
    property string text: ""
    property color glyphColor: Color.icon
    property int size: Style.fontIcon

    implicitWidth: Math.ceil(metrics.tightBoundingRect.width)
    implicitHeight: Style.segmentHeight

    TextMetrics {
        id: metrics
        font: glyph.font
        text: glyph.text
        renderType: glyph.renderType
    }

    Text {
        id: glyph
        x: Math.round((parent.width - metrics.tightBoundingRect.width) / 2 - metrics.tightBoundingRect.x)
        anchors.verticalCenter: parent.verticalCenter
        text: parent.text
        font.family: Style.fontFamily
        font.pixelSize: parent.size
        font.weight: Style.fontWeight
        color: parent.glyphColor
        renderType: Style.renderType
    }
}
