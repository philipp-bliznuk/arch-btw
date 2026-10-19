import QtQuick
import qs.core
import qs.ui

// Single-line input. `keyPressed` fires before the TextInput handles a key;
// set event.accepted to swallow it (launcher vim bindings).
Rectangle {
    id: root
    property alias text: textInput.text
    property alias echoMode: textInput.echoMode
    property string placeholder: ""
    property alias input: textInput

    signal accepted
    signal escaped
    signal keyPressed(var event)

    implicitHeight: Style.rowHeight
    radius: Style.radius
    color: Theme.surface0
    border.width: 1
    border.color: textInput.activeFocus ? Theme.accent : Theme.surface1

    TextInput {
        id: textInput
        anchors.fill: parent
        anchors.leftMargin: Style.spaceLg
        anchors.rightMargin: Style.spaceLg
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Style.fontFamily
        font.pixelSize: Style.fontBody
        font.weight: Style.fontWeight
        selectionColor: Theme.accent
        selectedTextColor: Theme.base
        clip: true
        onAccepted: root.accepted()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                event.accepted = true;
                root.escaped();
                return;
            }
            root.keyPressed(event);
        }
    }

    Label {
        anchors.fill: textInput
        visible: textInput.text === "" && !textInput.preeditText
        text: root.placeholder
        color: Theme.overlay0
    }
}
