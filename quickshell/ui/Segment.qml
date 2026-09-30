pragma ComponentBehavior: Bound
import QtQuick
import qs.core

// Flat bar segment (dwm-titus grammar): fixed height, hover/active fill,
// optional tooltip. The click area sits *below* the content so nested
// MouseAreas (tray icons, running apps) receive their own clicks.
Rectangle {
    id: root

    property string icon: ""
    property color iconColor: Color.icon
    property string label: ""
    property color labelColor: Color.label
    property int labelSize: Style.fontSmall
    property int labelWidth: 0
    property bool active: false
    property bool hoverable: true
    property string tooltip: ""
    property alias content: extra.data
    readonly property bool hovered: hover.hovered

    signal clicked(var mouse)
    signal wheel(var wheel)

    implicitHeight: Style.segmentHeight
    implicitWidth: row.implicitWidth + Style.segmentPadX * 2
    radius: Style.radius
    color: active ? Color.segmentActive : (hoverable && hovered ? Color.segmentHover : "transparent")

    MouseArea {
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => root.clicked(m)
        onWheel: w => root.wheel(w)
    }

    HoverHandler {
        id: hover
    }

    Row {
        id: row
        anchors.centerIn: parent
        height: parent.height
        spacing: Style.spaceSm

        Glyph {
            visible: root.icon !== ""
            height: parent.height
            text: root.icon
            glyphColor: root.iconColor
        }

        Label {
            visible: root.label !== ""
            height: parent.height
            width: root.labelWidth > 0 ? root.labelWidth : implicitWidth
            horizontalAlignment: root.labelWidth > 0 ? Text.AlignHCenter : Text.AlignLeft
            text: root.label
            color: root.labelColor
            font.pixelSize: root.labelSize
        }

        Item {
            id: extra
            visible: children.length > 0
            height: parent.height
            implicitWidth: childrenRect.width
        }
    }

    // Lazy: a Tooltip is a PopupWindow, and segments inside popups must not
    // spawn nested popups (Wayland rejects them, the parent card fails).
    Loader {
        active: root.tooltip !== ""
        sourceComponent: Tooltip {
            target: root
            text: root.tooltip
            hovered: root.hovered
        }
    }
}
