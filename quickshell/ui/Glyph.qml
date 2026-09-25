import QtQuick
import qs.core

// Nerd Font glyph with fixed vertical centering.
Text {
    property color glyphColor: Color.icon
    property int size: Style.fontIcon
    font.family: Style.fontFamily
    font.pixelSize: size
    font.bold: true
    color: glyphColor
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    renderType: Text.NativeRendering
}
