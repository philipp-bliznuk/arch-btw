import QtQuick
import Quickshell.Wayland
import qs.Commons

Text {
    id: root
    property int maxWidth: 400
    readonly property var win: ToplevelManager.activeToplevel
    text: win ? (win.title || win.appId || "") : ""
    visible: text !== ""
    width: Math.min(implicitWidth, maxWidth)
    elide: Text.ElideRight
    color: Color.subtext1
    font.family: Style.fontFamily
    font.pixelSize: Style.fontSmall
    font.weight: Font.DemiBold
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
}
