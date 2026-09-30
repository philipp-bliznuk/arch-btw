pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.ui

// Category chips for the Apps section. `names` = ["All", …], `current` index.
Row {
    id: root
    property var names: []
    property int current: 0

    signal picked(int index)

    spacing: Style.spaceXs

    Repeater {
        model: root.names

        Chip {
            required property string modelData
            required property int index
            text: modelData
            active: index === root.current
            onClicked: root.picked(index)
        }
    }
}
