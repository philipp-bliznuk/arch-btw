import QtQuick
import qs.core

// Single-line input styled like a pill.
Rectangle {
    id: root
    property alias text: input.text
    property alias echoMode: input.echoMode
    property string placeholder: ""
    property alias input: input

    signal accepted
    signal escaped

    implicitHeight: Style.rowHeight
    radius: Style.radius
    color: Color.pillBg
    border.width: 1
    border.color: input.activeFocus ? Color.accent : Color.pillBorder

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: Color.text
        font.family: Style.fontFamily
        font.pixelSize: Style.fontBody
        selectionColor: Color.accent
        selectedTextColor: Color.base
        clip: true
        onAccepted: root.accepted()
        Keys.onEscapePressed: root.escaped()
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.preeditText
        text: root.placeholder
        color: Color.overlay0
        font.family: Style.fontFamily
        font.pixelSize: Style.fontBody
    }
}
