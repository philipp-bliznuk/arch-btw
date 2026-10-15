import QtQuick
import qs.core

// The only Text. Family/weight/rendering come from Style so nothing drifts.
// Plain text always: Qt's AutoText would switch to StyledText on the first
// tag, and StyledText fetches <img src> - labels show notification, clipboard
// and tray strings that other processes wrote.
Text {
    color: Theme.text
    font.family: Style.fontFamily
    font.pixelSize: Style.fontBody
    font.weight: Style.fontWeight
    renderType: Style.renderType
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
}
