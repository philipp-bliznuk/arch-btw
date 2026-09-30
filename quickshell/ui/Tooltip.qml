import QtQuick
import Quickshell
import qs.core

// Delayed tooltip under a bar item. Suppressed while a panel popup is open:
// a new xdg popup must chain from the grabbing one, so we simply don't show.
PopupWindow {
    id: root

    required property Item target
    property string text: ""
    property bool hovered: false
    readonly property bool wanted: text !== "" && hovered && Popups.current === ""

    visible: false
    color: "transparent"
    implicitWidth: label.implicitWidth + Style.spaceMd * 2
    implicitHeight: Style.segmentHeight

    anchor {
        item: root.target
        edges: Edges.Bottom
        gravity: Edges.Bottom
        adjustment: PopupAdjustment.SlideX
        margins.top: Style.spaceXs
    }

    onWantedChanged: {
        if (wanted) {
            delay.restart();
            return;
        }
        delay.stop();
        visible = false;
    }

    Timer {
        id: delay
        interval: Style.tooltipDelay
        onTriggered: root.visible = root.wanted
    }

    Rectangle {
        anchors.fill: parent
        radius: Style.radius
        color: Color.surface0
        border.width: 1
        border.color: Color.cardBorder

        Label {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: Color.subtext1
            font.pixelSize: Style.fontCaption
        }
    }
}
