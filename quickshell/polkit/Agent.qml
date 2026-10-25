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
    // Whitespace collapsed first: the message is the requester's, and a
    // newline would skip the match and stretch the card.
    function describe(message) {
        const flat = String(message || "").replace(/\s+/g, " ").trim();
        const m = /^Authentication is (?:needed|required) to (.+)$/i.exec(flat);
        const s = m ? m[1].replace(/`([^`']+)'/g, "$1") : flat;
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function phase() {
        if (submitted)
            return "Checking";
        if (flow && flow.supplementaryMessage)
            return flow.supplementaryMessage;
        return "Authenticating";
    }

    // A locked screen approves nothing. PAM starts the moment a request
    // arrives, so a flow hidden behind the lock would hold the token in
    // pam_u2f while the lock screen asks for a touch, and that touch would
    // approve an action nothing on screen named. Flows arriving while locked
    // and a flow still open when the lock engages are cancelled (README,
    // Security: each costs a faillock strike). Deferred: a cancel completes
    // the flow synchronously and the next queued request starts inside the
    // same call.
    function cancelIfLocked() {
        if (Lock.locked && flow) {
            field.text = "";
            flow.cancelAuthenticationRequest();
        }
    }

    PolkitAgent {
        id: agent
        path: "/org/qs/PolkitAgent"
        onAuthenticationRequestStarted: {
            root.submitted = false;
            root.error = "";
            root.note = "";
            field.text = "";
            if (Lock.locked) {
                console.info("polkit: request while locked, cancelling " + (root.flow ? root.flow.actionId : ""));
                Qt.callLater(root.cancelIfLocked);
                return;
            }
            root.refocus();
        }
    }

    Connections {
        target: Lock

        function onLockedChanged() {
            if (Lock.locked && root.flow) {
                console.info("polkit: lock engaged, cancelling " + root.flow.actionId);
                Qt.callLater(root.cancelIfLocked);
            }
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

    // Never shown while locked; see cancelIfLocked.
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
                                // bounded: the requester writes this, the line
                                // under it says who asked and must stay on screen
                                maximumLineCount: 3
                                elide: Text.ElideRight
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

                            // win.visible, not just status.visible: an animation in a hidden
                            // window still runs and Qt then repaints the one exposed window,
                            // the bar, every vsync (README, Idle CPU).
                            SequentialAnimation on opacity {
                                running: win.visible && status.visible && !root.submitted
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
                        textFormat: Text.PlainText
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
