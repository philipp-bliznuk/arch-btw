pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.core
import qs.ui
import "Body.js" as Body

Rectangle {
    id: card
    required property var service
    required property var notification
    property int timeout: 5000

    readonly property bool critical: notification.urgency === NotificationUrgency.Critical
    readonly property string iconSource: {
        if (notification.image)
            return notification.image;
        if (notification.appIcon)
            return Quickshell.iconPath(notification.appIcon, true);
        return "";
    }
    readonly property bool iconShown: iconSource !== "" && icon.status !== Image.Error

    implicitHeight: body.implicitHeight + Style.cardPadding * 2
    radius: Style.cardRadius
    color: Theme.cardBg
    border.width: 1
    border.color: critical ? Theme.urgent : Theme.cardBorder

    // Countdown pauses while hovered and resumes with what was left, instead
    // of restarting. A replaces_id update rewrites the object under the card
    // (no second onNotification), and new text deserves the full time again.
    property real remaining: timeout
    property double armedAt: 0

    function arm() {
        armedAt = Date.now();
        expiry.interval = Math.max(1, remaining);
        expiry.restart();
    }

    function pause() {
        expiry.stop();
        remaining = Math.max(0, remaining - (Date.now() - armedAt));
    }

    function reset() {
        remaining = timeout;
        if (!hover.containsMouse)
            arm();
    }

    Component.onCompleted: reset()
    onTimeoutChanged: reset()

    Timer {
        id: expiry
        onTriggered: card.notification.expire()
    }

    Connections {
        target: card.notification
        function onSummaryChanged() { card.reset(); }
        function onBodyChanged() { card.reset(); }
        function onImageChanged() { card.reset(); }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onContainsMouseChanged: containsMouse ? card.pause() : card.arm()
        onClicked: m => {
            if (m.button === Qt.LeftButton)
                card.service.activate(card.notification);
            else
                card.notification.dismiss();
        }
    }

    Row {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Style.cardPadding
        }
        spacing: 10

        Item {
            width: 32
            height: 32

            IconImage {
                id: icon
                anchors.fill: parent
                visible: card.iconShown
                source: card.iconSource
            }
            Glyph {
                anchors.centerIn: parent
                visible: !card.iconShown
                text: card.service.glyph(card.notification) || (card.critical ? Icons.alert : Icons.bell)
                glyphColor: card.critical ? Theme.urgent : Theme.accent
                size: Style.fontTitle
            }
        }

        Column {
            width: parent.width - 32 - parent.spacing
            spacing: 4

            Row {
                width: parent.width
                spacing: 6

                Text {
                    text: card.notification.summary
                    textFormat: Text.PlainText
                    color: Theme.text
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontBody
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - app.width - parent.spacing)
                }
                Text {
                    id: app
                    text: card.notification.appName
                    textFormat: Text.PlainText
                    color: Theme.muted
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                    anchors.baseline: parent.children[0].baseline
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: Body.styled(card.notification.body, card.notification.appName, card.notification.appIcon)
                textFormat: Text.StyledText
                color: Theme.subtext0
                font.family: Style.fontFamily
                font.pixelSize: Style.fontSmall
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                onLinkActivated: link => Commands.run({ argv: ["xdg-open", link] })
            }

            Flow {
                width: parent.width
                spacing: 6
                visible: card.notification.actions.length > 0

                Repeater {
                    model: card.notification.actions

                    Chip {
                        required property var modelData
                        visible: modelData.identifier !== "default"
                        text: modelData.text
                        onClicked: {
                            modelData.invoke();
                            if (!card.notification.resident)
                                card.notification.dismiss();
                        }
                    }
                }
            }
        }
    }
}
