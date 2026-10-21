import QtQuick
import Quickshell
import qs.core

// Label capped at `maxWidth`. When the text overflows it scrolls once every
// `interval`, pauses at the end and snaps back; otherwise it is a plain Label.
Item {
    id: root

    property string text: ""
    property color color: Theme.text
    property int size: Style.fontSmall
    property int maxWidth: 200
    property int interval: 10000
    property int speed: 40
    property int pause: 1500
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property int duration: overflow / speed * 1000
    // Scrolling only when someone could see it. The item reads visible inside
    // a hidden window (bar hidden, fullscreen), so the window is asked too.
    // Not while locked: the bar sits unexposed under the lock surface and the
    // scroll would make the lock surface repaint every vsync (README, Idle CPU).
    readonly property var ownerWindow: QsWindow.window
    readonly property bool shown: visible && (ownerWindow ? ownerWindow.visible : true) && !Lock.locked

    clip: true
    implicitWidth: Math.min(maxWidth, label.implicitWidth)
    implicitHeight: label.implicitHeight

    onTextChanged: rewind()
    onOverflowChanged: rewind()
    onShownChanged: rewind()

    // restart() forces the timer on over its `running` binding until that
    // re-evaluates, so re-arm it under the binding's own condition only.
    function rewind() {
        scroll.stop();
        label.x = 0;
        if (root.overflow > 0 && root.shown)
            tick.restart();
        else
            tick.stop();
    }

    Label {
        id: label
        height: parent.height
        width: implicitWidth
        elide: Text.ElideNone
        text: root.text
        color: root.color
        font.pixelSize: root.size
    }

    // Never restart mid-scroll: a long title needs duration + pause to finish.
    Timer {
        id: tick
        interval: Math.max(root.interval, root.duration + root.pause + 1000)
        running: root.overflow > 0 && root.shown
        repeat: true
        onTriggered: scroll.restart()
    }

    SequentialAnimation {
        id: scroll

        NumberAnimation {
            target: label
            property: "x"
            from: 0
            to: -root.overflow
            duration: root.duration
        }

        PauseAnimation {
            duration: root.pause
        }

        PropertyAction {
            target: label
            property: "x"
            value: 0
        }
    }
}
