import QtQuick
import qs.core

// The default Text. Family/weight/colour come from Style and Theme; the
// NativeTextRendering pragma in shell.qml covers rendering for every Text.
// Plain text always: Qt's AutoText would switch to StyledText on the first
// tag, and StyledText fetches <img src> - labels show notification, clipboard
// and tray strings that other processes wrote.
Text {
    color: Theme.text
    font.family: Style.fontFamily
    font.pixelSize: Style.fontBody
    font.weight: Style.fontWeight
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
}
