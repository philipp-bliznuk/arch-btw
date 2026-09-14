import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Pill {
    id: root
    icon: ""

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    content: Stacked {
        topText: Qt.formatDateTime(clock.date, "ddd dd MMM")
        bottomText: Qt.formatDateTime(clock.date, "HH:mm:ss")
        topSize: Style.fontCaption
        bottomSize: Style.fontSmall
        topColor: Color.subtext0
        bottomColor: Color.text
        minWidth: 72
    }
}
