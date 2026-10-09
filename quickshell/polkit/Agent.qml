pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.core
import Quickshell.Io
import qs.ui

// In-shell polkit authentication agent. Replaces polkit-gnome/-kde agents.
Scope {
    id: root

    readonly property var flow: agent.flow
    readonly property bool active: agent.isActive
    property bool submitted: false
    property string error: ""

    function submit() {
        if (!flow || !flow.isResponseRequired || submitted)
            return;
        submitted = true;
        error = "";
        flow.submit(field.text);
        field.text = "";
    }

    function cancel() {
        field.text = "";
        submitted = false;
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    // "Authentication is required to run `/usr/bin/x' as the super user" ->
    // "Run /usr/bin/x as the super user": the title already says the rest.
    function describe(message) {
        const m = /^Authentication is (?:needed|required) to (.+)$/i.exec(message || "");
        const s = m ? m[1].replace(/`([^`']+)'/g, "$1") : (message || "");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    PolkitAgent {
        id: agent
        path: "/org/qs/PolkitAgent"
        onAuthenticationRequestStarted: {
            root.submitted = false;
            root.error = "";
            field.text = "";
            Qt.callLater(() => field.input.forceActiveFocus());
        }
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true

        function onIsResponseRequiredChanged() {
            if (root.flow && root.flow.isResponseRequired) {
                root.submitted = false;
                Qt.callLater(() => field.input.forceActiveFocus());
            }
        }

        function onAuthenticationFailed() {
            root.submitted = false;
            root.error = "Authentication failed";
            field.text = "";
            shake.restart();
            Qt.callLater(() => field.input.forceActiveFocus());
        }
    }

    IpcHandler {
        target: "polkit"

        function status(): string {
            return JSON.stringify({ registered: agent.isRegistered, active: agent.isActive, responseRequired: root.flow ? root.flow.isResponseRequired : false });
        }
    }

    // Hidden while locked: the request stays pending and shows after unlock.
    PanelWindow {
        id: win
        visible: root.active && !Lock.locked
        screen: SwayState.focusedScreen
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-polkit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
        }

        Rectangle {
            id: card
            property int shakeOffset: 0
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: shakeOffset
            width: 420
            height: column.implicitHeight + Style.cardPadding * 2 + 8
            radius: Style.cardRadius
            color: Theme.cardBg
            border.width: 1
            border.color: root.error ? Theme.urgent : Theme.cardBorder

            SequentialAnimation {
                id: shake
                NumberAnimation { target: card; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
                NumberAnimation { target: card; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
            }

            Column {
                id: column
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: Style.cardPadding + 4
                }
                spacing: 10

                Row {
                    spacing: 10
                    width: parent.width

                    Glyph {
                        text: Icons.shield
                        glyphColor: Theme.accent
                        size: Style.fontTitle + 4
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        width: parent.width - 30
                        spacing: 2
                        Text {
                            width: parent.width
                            text: "Authentication required"
                            color: Theme.text
                            font.family: Style.fontFamily
                            font.pixelSize: Style.fontTitle
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: root.flow ? root.describe(root.flow.message) : ""
                            color: Theme.subtext0
                            font.family: Style.fontFamily
                            font.pixelSize: Style.fontSmall
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.flow && root.flow.selectedIdentity ? "as " + root.flow.selectedIdentity.displayName : ""
                    color: Theme.muted
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                }

                // Read-only, not disabled: a disabled item drops keyboard focus,
                // and Esc must still cancel while PAM waits for a YubiKey touch.
                Field {
                    id: field
                    width: parent.width
                    placeholder: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                    echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    input.readOnly: root.flow ? !root.flow.isResponseRequired || root.submitted : true
                    opacity: input.readOnly ? 0.5 : 1
                    onAccepted: root.submit()
                    onEscaped: root.cancel()
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.error || (root.flow && root.flow.supplementaryMessage ? root.flow.supplementaryMessage : "")
                    color: root.error || (root.flow && root.flow.supplementaryIsError) ? Theme.urgent : Theme.muted
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: (root.flow ? root.flow.actionId + "   " : "") + "Esc cancel · Enter submit"
                    color: Theme.overlay0
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                    elide: Text.ElideLeft
                }
            }
        }
    }
}
