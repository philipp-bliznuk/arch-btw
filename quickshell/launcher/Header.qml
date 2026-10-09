pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.ui

// Launcher header: section glyph, breadcrumb, mode caption, count / calc.
Item {
    id: root
    property string glyph: Icons.apps
    property var crumbs: []
    property string mode: "insert"
    property string status: ""

    implicitHeight: Style.segmentHeight
    width: parent ? parent.width : implicitWidth

    Row {
        anchors.left: parent.left
        anchors.right: right.left
        anchors.rightMargin: Style.spaceMd
        height: parent.height
        spacing: Style.spaceSm

        Glyph {
            text: root.glyph
            glyphColor: Theme.accent
            size: Style.fontTitle
        }

        Repeater {
            model: root.crumbs

            Row {
                id: crumb
                required property string modelData
                required property int index
                height: parent.height
                spacing: Style.spaceSm

                Label {
                    visible: crumb.index > 0
                    height: parent.height
                    text: "›"
                    color: Theme.overlay0
                }
                Label {
                    height: parent.height
                    text: crumb.modelData
                    color: crumb.index === root.crumbs.length - 1 ? Theme.text : Theme.muted
                }
            }
        }
    }

    Row {
        id: right
        anchors.right: parent.right
        height: parent.height
        spacing: Style.spaceMd

        Label {
            height: parent.height
            text: root.status
            color: Theme.muted
            font.pixelSize: Style.fontCaption
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: modeLabel.implicitWidth + Style.spaceMd
            height: Style.segmentHeight - 6
            radius: Style.radius - 2
            color: root.mode === "insert" ? Theme.accent : Theme.peach

            Label {
                id: modeLabel
                anchors.centerIn: parent
                text: root.mode.toUpperCase()
                color: Theme.base
                font.pixelSize: Style.fontCaption
            }
        }
    }
}
