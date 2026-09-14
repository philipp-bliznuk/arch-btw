import QtQuick
import qs.Commons

// Two small stacked labels (sketchybar datetime / net-rate style).
Column {
    id: root
    property string topText: ""
    property string bottomText: ""
    property color topColor: Color.label
    property color bottomColor: Color.label
    property int topSize: Style.fontCaption
    property int bottomSize: Style.fontCaption
    property int minWidth: 0

    spacing: -1

    Text {
        text: root.topText
        color: root.topColor
        font.family: Style.fontFamily
        font.pixelSize: root.topSize
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        width: Math.max(implicitWidth, root.minWidth)
        renderType: Text.NativeRendering
    }

    Text {
        text: root.bottomText
        color: root.bottomColor
        font.family: Style.fontFamily
        font.pixelSize: root.bottomSize
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        width: Math.max(implicitWidth, root.minWidth)
        renderType: Text.NativeRendering
    }
}
