import QtQuick
import qs.core
import qs.ui

// Sway binding-mode indicator, tmux-style: fills the centre of the bar while
// a mode other than "default" is active and lists the keys that work in it.
Rectangle {
    id: root
    readonly property string mode: SwayState.mode
    readonly property var hints: ({
        popup: "m media · a audio · n network · b battery · c calendar · w weather",
        resize: "h j k l shrink/grow · Esc"
    })
    visible: mode !== "default"
    implicitWidth: row.implicitWidth + Style.spaceMd * 2
    implicitHeight: Style.segmentHeight
    radius: Style.radius
    color: Theme.accent

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.spaceMd

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode.toUpperCase()
            color: Theme.crust
            font.pixelSize: Style.fontCaption
            font.weight: Font.Bold
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: root.hints[root.mode] ?? "Esc to leave"
            color: Theme.crust
            font.pixelSize: Style.fontCaption
        }
    }
}
