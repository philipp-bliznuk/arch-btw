import QtQuick
import qs.core
import qs.ui

// Popup list row: glyph + title + subtitle + optional trailing text.
Rectangle {
    id: root
    property string glyph: ""
    property color glyphColor: Color.text
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property bool selected: false
    property bool dim: false

    signal clicked(var mouse)

    width: parent ? parent.width : implicitWidth
    height: subtitle !== "" ? 40 : 30
    radius: Style.radius
    color: selected ? Color.rowSelected : (mouse.containsMouse ? Util.alpha(Color.surface1, 0.5) : "transparent")
    opacity: dim ? 0.55 : 1

    Row {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Glyph {
            width: 16
            height: parent.height
            visible: root.glyph !== ""
            text: root.glyph
            glyphColor: root.glyphColor
        }

        Column {
            width: parent.width - (root.glyph !== "" ? 24 : 0) - (trail.visible ? trail.width + 8 : 0)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.title
                color: Color.text
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: root.subtitle !== ""
                text: root.subtitle
                color: Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontCaption
                elide: Text.ElideRight
            }
        }

        Text {
            id: trail
            visible: root.trailing !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.trailing
            color: Color.muted
            font.family: Style.fontFamily
            font.pixelSize: Style.fontCaption
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => root.clicked(m)
    }
}
