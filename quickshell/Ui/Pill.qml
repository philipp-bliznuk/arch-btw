import QtQuick
import qs.Commons

// Sketchybar-style bar item: bordered rounded pill, icon + label.
Rectangle {
    id: root

    property string icon: ""
    property color iconColor: Color.icon
    property string label: ""
    property color labelColor: Color.label
    property int labelSize: Style.fontBody
    property bool highlighted: false
    property bool hoverable: true
    property alias content: extra.data
    property alias contentItem: extra

    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitHeight: Math.max(Style.pillHeight, row.implicitHeight + 2)
    implicitWidth: row.implicitWidth + Style.pillPadding * 2
    radius: Style.radius
    color: highlighted ? Color.pillHover : (mouse.containsMouse && hoverable ? Color.pillHover : Color.pillBg)
    border.width: 1
    border.color: Color.pillBorder

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Glyph {
            visible: root.icon !== ""
            text: root.icon
            glyphColor: root.iconColor
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.label !== ""
            text: root.label
            color: root.labelColor
            font.family: Style.fontFamily
            font.pixelSize: root.labelSize
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
            renderType: Text.NativeRendering
        }

        Item {
            id: extra
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            visible: children.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.hoverable
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => root.clicked(m)
        onWheel: w => root.wheel(w)
    }
}
