pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.core
import qs.ui

Rectangle {
    id: card
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

    implicitHeight: body.implicitHeight + Style.cardPadding * 2
    radius: Style.cardRadius
    color: Color.cardBg
    border.width: 1
    border.color: critical ? Color.urgent : Color.cardBorder

    function defaultAction() {
        for (const a of notification.actions)
            if (a.identifier === "default")
                return a;
        return null;
    }

    Timer {
        interval: card.timeout
        running: !hover.containsMouse
        onTriggered: card.notification.expire()
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => {
            if (m.button !== Qt.LeftButton) {
                card.notification.dismiss();
                return;
            }
            const a = card.defaultAction();
            if (a)
                a.invoke();
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
            visible: true

            IconImage {
                anchors.fill: parent
                visible: card.iconSource !== ""
                source: card.iconSource
            }
            Glyph {
                anchors.centerIn: parent
                visible: card.iconSource === ""
                text: card.critical ? Icons.alert : Icons.bell
                glyphColor: card.critical ? Color.urgent : Color.accent
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
                    color: Color.text
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontBody
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, parent.width - app.width - parent.spacing)
                }
                Text {
                    id: app
                    text: card.notification.appName
                    color: Color.muted
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontCaption
                    anchors.baseline: parent.children[0].baseline
                }
            }

            Text {
                width: parent.width
                visible: card.notification.body !== ""
                text: card.notification.body
                textFormat: Text.StyledText
                color: Color.subtext0
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
