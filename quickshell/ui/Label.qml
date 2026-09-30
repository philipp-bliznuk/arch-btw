import QtQuick
import qs.core

// The only Text. Family/weight/rendering come from Style so nothing drifts.
Text {
    color: Color.text
    font.family: Style.fontFamily
    font.pixelSize: Style.fontBody
    font.weight: Style.fontWeight
    renderType: Style.renderType
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
}
