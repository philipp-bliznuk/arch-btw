import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

// List row for popups and the launcher: icon24 | title | subtext (fills) |
// trailing text | trailing slot. Title is capped at 55% when a subtext exists.
// A crumb adds a second muted line under the title (search results from a
// submenu show where they came from).
Rectangle {
    id: root

    property string glyph: ""
    property color glyphColor: Color.text
    property string iconSource: ""
    property string title: ""
    property string subtext: ""
    property string crumb: ""
    property string trailing: ""
    property color trailingColor: Color.muted
    property bool selected: false
    property bool dim: false
    property alias trailingItem: trailSlot.data
    readonly property bool hovered: hover.hovered

    signal clicked(var mouse)

    width: parent ? parent.width : implicitWidth
    implicitWidth: layout.implicitWidth + Style.spaceMd * 2
    implicitHeight: Style.rowHeight + (crumb !== "" ? Style.crumbHeight : 0)
    radius: Style.radius
    color: selected ? Color.rowSelected : (hovered ? Color.segmentHover : "transparent")
    opacity: dim ? 0.55 : 1

    HoverHandler {
        id: hover
    }

    MouseArea {
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => root.clicked(m)
    }

    RowLayout {
        id: layout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spaceMd
        anchors.rightMargin: Style.spaceMd
        height: root.crumb !== "" ? Style.rowHeight - Style.spaceXs : Style.rowHeight
        spacing: Style.spaceMd

        Item {
            visible: root.glyph !== "" || root.iconSource !== ""
            Layout.preferredWidth: 24
            Layout.fillHeight: true

            IconImage {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: root.iconSource !== ""
                source: root.iconSource
                asynchronous: true
            }

            Glyph {
                anchors.centerIn: parent
                visible: root.iconSource === ""
                text: root.glyph
                glyphColor: root.glyphColor
            }
        }

        Label {
            text: root.title
            Layout.fillWidth: root.subtext === ""
            Layout.maximumWidth: root.subtext === "" ? -1 : Math.floor(root.width * 0.55)
        }

        Label {
            visible: root.subtext !== ""
            text: root.subtext
            color: Color.muted
            font.pixelSize: Style.fontSmall
            Layout.fillWidth: true
        }

        Label {
            visible: root.trailing !== ""
            text: root.trailing
            color: root.trailingColor
            font.pixelSize: Style.fontCaption
        }

        Item {
            id: trailSlot
            visible: children.length > 0
            implicitWidth: childrenRect.width
            Layout.fillHeight: true
        }
    }

    Label {
        visible: root.crumb !== ""
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spaceSm
        anchors.left: parent.left
        anchors.leftMargin: Style.spaceMd + 24 + Style.spaceMd
        text: "↳ " + root.crumb
        color: Color.muted
        font.pixelSize: Style.fontCaption
    }
}
