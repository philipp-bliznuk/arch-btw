import QtQuick
import qs.core

// Small filter chip (launcher categories). Active = accent fill.
Rectangle {
    id: root

    property string text: ""
    property bool active: false
    readonly property bool hovered: hover.hovered

    signal clicked

    implicitHeight: Style.segmentHeight - 2
    implicitWidth: label.implicitWidth + Style.spaceMd * 2
    radius: Style.radius
    color: active ? Color.accent : (hovered ? Color.segmentActive : Color.surface0)

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.active ? Color.base : Color.subtext1
        font.pixelSize: Style.fontCaption
    }
}
