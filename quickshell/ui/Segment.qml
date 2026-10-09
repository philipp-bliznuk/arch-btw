pragma ComponentBehavior: Bound
import QtQuick
import qs.core

// Flat bar segment: fixed height, hover/active fill, optional tooltip. The
// click area sits *below* the content so nested MouseAreas (tray icons)
// receive their own clicks.
Rectangle {
    id: root

    property string icon: ""
    property color iconColor: Theme.icon
    property string label: ""
    property color labelColor: Theme.label
    property int labelSize: Style.fontSmall
    // Sample text that fixes the label width (e.g. "99%"), so values that
    // change digit count do not shift the neighbours. Size it for the typical
    // value: wider text still expands, narrower text leaves a gap. Right-align
    // numbers so that gap sits next to the icon, not between segments.
    property string labelTemplate: ""
    property int labelWidth: labelTemplate !== "" ? Math.ceil(metrics.advanceWidth) + 2 : 0
    property int labelAlign: Text.AlignLeft
    property bool active: false
    property bool hoverable: true
    property string tooltip: ""
    property alias content: extra.data
    readonly property bool hovered: hover.hovered

    signal clicked(var mouse)

    implicitHeight: Style.segmentHeight
    implicitWidth: row.implicitWidth + Style.segmentPadX * 2
    radius: Style.radius
    color: active ? Theme.segmentActive : (hoverable && hovered ? Theme.segmentHover : "transparent")

    // NativeRendering rounds the hinted width differently per digit set,
    // so measure the template once rather than the live text.
    TextMetrics {
        id: metrics
        font.family: Style.fontFamily
        font.pixelSize: root.labelSize
        font.weight: Style.fontWeight
        renderType: Style.renderType
        text: root.labelTemplate
    }

    MouseArea {
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => root.clicked(m)
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
            width: Math.max(root.labelWidth, implicitWidth)
            horizontalAlignment: root.labelAlign
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
