import QtQuick
import qs.core

// Horizontal slider, 0..1. Emits moved(value) while dragging / on wheel.
// `peak` >= 0 draws a live level bar inside the track (mic meter).
Item {
    id: root
    property real value: 0
    property bool muted: false
    property real peak: -1

    property real wheelAcc: 0

    signal moved(real value)

    implicitHeight: 18

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Theme.surface1

        Rectangle {
            width: parent.width * Util.clamp(root.value, 0, 1)
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.overlay0 : Theme.accent
        }

        Rectangle {
            visible: root.peak >= 0
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * Util.clamp(root.peak, 0, 1)
            height: 4
            radius: 2
            color: root.muted ? Theme.overlay2 : Theme.green
            Behavior on width {
                NumberAnimation { duration: 60 }
            }
        }

        Rectangle {
            x: parent.width * Util.clamp(root.value, 0, 1) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: root.muted ? Theme.overlay1 : Theme.text
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: m => root.moved(Util.clamp(m.x / width, 0, 1))
        onPositionChanged: m => {
            if (pressed)
                root.moved(Util.clamp(m.x / width, 0, 1));
        }
        onWheel: w => {
            const r = Util.wheelSteps(root.wheelAcc, w.angleDelta.y);
            root.wheelAcc = r.remainder;
            if (r.steps)
                root.moved(Util.clamp(root.value + r.steps * 0.05, 0, 1));
        }
    }
}
