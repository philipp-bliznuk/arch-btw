import QtQuick
import qs.Commons

// Nerd Font glyph with fixed vertical centering.
Text {
    property color glyphColor: Color.icon
    font.family: Style.fontFamily
    font.pixelSize: Style.fontIcon
    font.bold: true
    color: glyphColor
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering
}
