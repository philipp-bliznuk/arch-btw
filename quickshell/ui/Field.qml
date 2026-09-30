import QtQuick
import qs.core
import qs.ui

// Single-line input. `keyPressed` fires before the TextInput handles a key;
// set event.accepted to swallow it (launcher vim bindings).
Rectangle {
    id: root
    property alias text: input.text
    property alias echoMode: input.echoMode
    property string placeholder: ""
    property alias input: input

    signal accepted
    signal escaped
    signal keyPressed(var event)

    implicitHeight: Style.rowHeight
    radius: Style.radius
    color: Color.surface0
    border.width: 1
    border.color: input.activeFocus ? Color.accent : Color.surface1

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Style.spaceLg
        anchors.rightMargin: Style.spaceLg
        verticalAlignment: TextInput.AlignVCenter
        color: Color.text
        font.family: Style.fontFamily
        font.pixelSize: Style.fontBody
        font.weight: Style.fontWeight
        renderType: Style.renderType
        selectionColor: Color.accent
        selectedTextColor: Color.base
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
        anchors.fill: input
        visible: input.text === "" && !input.preeditText
        text: root.placeholder
        color: Color.overlay0
    }
}
