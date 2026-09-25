import QtQuick
import qs.core

// Horizontal slider, 0..1. Emits moved(value) while dragging / on wheel.
Item {
    id: root
    property real value: 0
    property color fill: Color.accent
    property bool muted: false

    signal moved(real value)

    implicitHeight: 18

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Color.surface1

        Rectangle {
            width: parent.width * Util.clamp(root.value, 0, 1)
            height: parent.height
            radius: parent.radius
            color: root.muted ? Color.overlay0 : root.fill
        }

        Rectangle {
            x: parent.width * Util.clamp(root.value, 0, 1) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: root.muted ? Color.overlay1 : Color.text
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: m => root.moved(Util.clamp(m.x / width, 0, 1))
        onPositionChanged: m => {
            if (pressed)
                root.moved(Util.clamp(m.x / width, 0, 1));
        }
        onWheel: w => root.moved(Util.clamp(root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05), 0, 1))
    }
}
