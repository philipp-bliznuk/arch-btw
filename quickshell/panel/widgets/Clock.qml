pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QC
import Quickshell
import qs.core
import qs.ui

Pill {
    id: root
    icon: ""
    property bool seconds: true
    property date shown: new Date()
    highlighted: popup.open

    SystemClock {
        id: clock
        precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    content: Stacked {
        topText: Qt.formatDateTime(clock.date, "ddd dd MMM")
        bottomText: Qt.formatDateTime(clock.date, root.seconds ? "HH:mm:ss" : "HH:mm")
        topSize: Style.fontCaption
        bottomSize: Style.fontSmall
        topColor: Color.subtext0
        bottomColor: Color.text
        minWidth: root.seconds ? 72 : 60
    }

    onClicked: m => {
        if (m.button === Qt.RightButton) {
            seconds = !seconds;
            return;
        }
        shown = new Date();
        Popups.toggle("clock");
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "clock"
        cardWidth: 300

        Column {
            width: parent.width
            spacing: 6

            Row {
                width: parent.width
                height: Style.rowHeight - 6

                Pill {
                    icon: Icons.chevronLeft
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() - 1, 1)
                }
                Text {
                    width: parent.width - 2 * Style.pillHeight - 20
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(root.shown, "MMMM yyyy")
                    color: Color.text
                    font.family: Style.fontFamily
                    font.pixelSize: Style.fontBody
                    font.weight: Font.DemiBold

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.shown = new Date()
                    }
                }
                Pill {
                    icon: Icons.chevronRight
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.shown = new Date(root.shown.getFullYear(), root.shown.getMonth() + 1, 1)
                }
            }

            Row {
                width: parent.width
                spacing: 4

                QC.WeekNumberColumn {
                    id: weeks
                    month: root.shown.getMonth()
                    year: root.shown.getFullYear()
                    locale: Qt.locale("en_GB")
                    width: 28
                    height: grid.height
                    y: days.height + 4
                    delegate: Text {
                        required property int weekNumber
                        text: weekNumber
                        color: Color.overlay0
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontCaption
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Column {
                    width: parent.width - weeks.width - parent.spacing
                    spacing: 4

                    QC.DayOfWeekRow {
                        id: days
                        width: parent.width
                        locale: Qt.locale("en_GB")
                        delegate: Text {
                            required property string shortName
                            text: shortName
                            color: Color.muted
                            font.family: Style.fontFamily
                            font.pixelSize: Style.fontCaption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    QC.MonthGrid {
                        id: grid
                        width: parent.width
                        month: root.shown.getMonth()
                        year: root.shown.getFullYear()
                        locale: Qt.locale("en_GB")
                        spacing: 2
                        delegate: Rectangle {
                            required property var model
                            readonly property bool today: model.today
                            readonly property bool inMonth: model.month === grid.month
                            implicitHeight: 24
                            radius: Style.radius
                            color: today ? Color.accent : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: parent.model.day
                                color: parent.today ? Color.base : (parent.inMonth ? Color.text : Color.overlay0)
                                font.family: Style.fontFamily
                                font.pixelSize: Style.fontSmall
                                font.weight: parent.today ? Font.Bold : Font.Normal
                            }
                        }
                    }
                }
            }
        }
    }
}
