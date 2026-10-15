pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.core
import Quickshell.Io
import qs.ui

// In-shell polkit authentication agent. Replaces polkit-gnome/-kde agents.
// PAM runs its modules one after another, so while pam_u2f waits for a
// YubiKey touch nothing can be typed: the field only exists while PAM asks
// for text, a status row takes its place otherwise.
Scope {
    id: root

    readonly property var flow: agent.flow
    readonly property bool active: agent.isActive
    readonly property bool prompting: flow ? flow.isResponseRequired && !submitted : false
    property bool submitted: false
    property string error: ""
    // PAM line shown under the field. quickshell never clears
    // supplementaryMessage, so the pam_u2f cue would still sit there when the
    // password prompt opens 29 s later; only a line that arrived with the
    // prompt (faillock's lockout notice) or during it is kept.
    property string note: ""
    property double noteAt: 0

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

    // The field takes focus while it is shown; the scope around the card
    // otherwise, so Esc still cancels during the touch wait.
    function refocus() {
        Qt.callLater(() => {
            if (!win.visible)
                return;
            if (root.prompting)
                field.input.forceActiveFocus();
            else
                scope.forceActiveFocus();
        });
    }

    // "Authentication is required to run `/usr/bin/x' as the super user" ->
    // "Run /usr/bin/x as the super user": the title already says the rest.
    function describe(message) {
        const m = /^Authentication is (?:needed|required) to (.+)$/i.exec(message || "");
        const s = m ? m[1].replace(/`([^`']+)'/g, "$1") : (message || "");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function phase() {
        if (submitted)
            return "Checking";
        if (flow && flow.supplementaryMessage)
            return flow.supplementaryMessage;
        return "Authenticating";
    }

    PolkitAgent {
        id: agent
        path: "/org/qs/PolkitAgent"
        onAuthenticationRequestStarted: {
            root.submitted = false;
            root.error = "";
            root.note = "";
            field.text = "";
            root.refocus();
        }
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true

        function onIsResponseRequiredChanged() {
            if (root.flow && root.flow.isResponseRequired) {
                root.submitted = false;
                root.note = Date.now() - root.noteAt < 1000 ? root.flow.supplementaryMessage : "";
            }
            root.refocus();
        }

        function onSupplementaryMessageChanged() {
            root.noteAt = Date.now();
            if (root.prompting)
                root.note = root.flow.supplementaryMessage;
        }

        function onAuthenticationFailed() {
            root.submitted = false;
            root.error = "Authentication failed";
            root.note = "";
            field.text = "";
            shake.restart();
            root.refocus();
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
        onVisibleChanged: if (visible) root.refocus()

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

            // Holds keyboard focus whenever the field is hidden.
            FocusScope {
                id: scope
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.cancel()

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
                                textFormat: Text.PlainText
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
                        textFormat: Text.PlainText
                        color: Theme.muted
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontCaption
                    }

                    Field {
                        id: field
                        width: parent.width
                        visible: root.prompting
                        placeholder: root.flow && root.flow.inputPrompt ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        onAccepted: root.submit()
                        onEscaped: root.cancel()
                    }

                    // Same box as the field: PAM's own words while it waits
                    // (the pam_u2f touch cue), "Checking" after a submit.
                    Rectangle {
                        id: status
                        width: parent.width
                        visible: !root.prompting
                        height: Style.rowHeight
                        radius: Style.radius
                        color: Theme.surface0
                        border.width: 1
                        border.color: Theme.surface1

                        Label {
                            id: phaseLabel
                            anchors.fill: parent
                            anchors.leftMargin: Style.spaceLg
                            anchors.rightMargin: Style.spaceLg
                            text: root.phase()
                            color: Theme.subtext0

                            SequentialAnimation on opacity {
                                running: status.visible && !root.submitted
                                loops: Animation.Infinite
                                onStopped: phaseLabel.opacity = 1
                                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.error || root.note
                        color: root.error || (root.flow && root.flow.supplementaryIsError) ? Theme.urgent : Theme.muted
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontCaption
                        wrapMode: Text.Wrap
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: (root.flow ? root.flow.actionId + "   " : "") + (root.prompting ? "Esc cancel · Enter submit" : "Esc cancel")
                        textFormat: Text.PlainText
                        color: Theme.overlay0
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontCaption
                        elide: Text.ElideLeft
                    }
                }
            }
        }
    }
}
