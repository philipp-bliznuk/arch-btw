pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QC
import Quickshell
import qs.core
import qs.ui

// Clock: `Wed 30 14:05:09`, fixed width so per-second redraws never shift the
// bar. Calendar popup with year progress, ISO weeks, week-start toggle.
// Keys: h/l or [ ] month · j/k or { } year · t/Enter today · w week start.
Segment {
    id: root
    readonly property bool mondayFirst: Settings.get("weekStartMonday")
    property date shown: new Date()
    active: popup.open

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // NativeRendering rounds the hinted width differently per digit set
    // (117 vs 118 px), so size the label from a sample once instead.
    TextMetrics {
        id: metrics
        font.family: Style.fontFamily
        font.pixelSize: root.labelSize
        font.weight: Style.fontWeight
        renderType: Style.renderType
        text: "Www 00 00:00:00"
    }

    label: Qt.formatDateTime(clock.date, "ddd d HH:mm:ss")
    labelSize: Style.fontBody
    labelWidth: Math.ceil(metrics.advanceWidth) + 2
    tooltip: Qt.formatDateTime(clock.date, "dddd d MMMM yyyy") + " · week " + weekNumber(clock.date)

    function weekNumber(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        const day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        const start = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - start) / 86400000 + 1) / 7);
    }

    function yearProgress(d) {
        const start = new Date(d.getFullYear(), 0, 1);
        const end = new Date(d.getFullYear() + 1, 0, 1);
        return (d - start) / (end - start);
    }

    function shift(months, years) {
        shown = new Date(shown.getFullYear() + years, shown.getMonth() + months, 1);
    }

    function today() {
        shown = new Date();
    }

    onClicked: {
        today();
        popup.toggle();
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "clock"
        cardWidth: 300
        onAction: a => {
            switch (a) {
            case "left":
            case "prevMonth":
                root.shift(-1, 0);
                break;
            case "right":
            case "nextMonth":
                root.shift(1, 0);
                break;
            case "down":
            case "leftBig":
            case "prevYear":
                root.shift(0, -1);
                break;
            case "up":
            case "rightBig":
            case "nextYear":
                root.shift(0, 1);
                break;
            case "today":
            case "activate":
                root.today();
                break;
            case "week":
                Settings.set("weekStartMonday", !root.mondayFirst);
                break;
            }
        }

        Column {
            width: parent.width
            spacing: Style.spaceSm

            Item {
                id: hero
                width: parent.width
                height: 40

                Glyph {
                    id: heroGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 40
                    text: Icons.calendar
                    glyphColor: Color.accent
                    size: Style.fontTitle + 8
                }
                Column {
                    anchors.left: heroGlyph.right
                    anchors.leftMargin: Style.spaceMd
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        text: Qt.formatDate(clock.date, "dddd, MMMM d")
                        font.pixelSize: Style.fontTitle
                    }
                    Label {
                        width: parent.width
                        text: "Week " + root.weekNumber(clock.date) + " · day " + Math.ceil(root.yearProgress(clock.date) * 365) + " of " + clock.date.getFullYear()
                        color: Color.muted
                        font.pixelSize: Style.fontCaption
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.today()
                }
            }

            Row {
                width: parent.width
                spacing: Style.spaceMd

                Label {
                    text: clock.date.getFullYear()
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                    height: 10
                }
                Rectangle {
                    width: parent.width - 30 - 34 - parent.spacing * 2
                    height: 4
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Color.surface1

                    Rectangle {
                        width: parent.width * root.yearProgress(clock.date)
                        height: parent.height
                        radius: parent.radius
                        color: Color.accent
                    }
                }
                Label {
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.yearProgress(clock.date) * 100) + "%"
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                    height: 10
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Color.surface1
            }

            Row {
                width: parent.width
                height: Style.segmentHeight

                Segment {
                    icon: Icons.chevronLeft
                    onClicked: root.shift(-1, 0)
                }
                Label {
                    width: parent.width - 2 * (Style.segmentHeight + Style.segmentPadX)
                    height: parent.height
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(root.shown, "MMMM yyyy")

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.today()
                    }
                }
                Segment {
                    icon: Icons.chevronRight
                    onClicked: root.shift(1, 0)
                }
            }

            Row {
                width: parent.width
                spacing: Style.spaceXs

                Column {
                    width: 28
                    spacing: Style.spaceXs

                    Label {
                        width: parent.width
                        height: days.height
                        horizontalAlignment: Text.AlignHCenter
                        text: "W"
                        color: Color.overlay0
                        font.pixelSize: Style.fontCaption

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Settings.set("weekStartMonday", !root.mondayFirst)
                        }
                    }
                    QC.WeekNumberColumn {
                        month: root.shown.getMonth()
                        year: root.shown.getFullYear()
                        locale: Qt.locale(root.mondayFirst ? "en_GB" : "en_US")
                        width: parent.width
                        height: grid.height
                        delegate: Label {
                            required property int weekNumber
                            text: weekNumber
                            color: Color.overlay0
                            font.pixelSize: Style.fontCaption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Column {
                    width: parent.width - 28 - parent.spacing
                    spacing: Style.spaceXs

                    QC.DayOfWeekRow {
                        id: days
                        width: parent.width
                        locale: Qt.locale(root.mondayFirst ? "en_GB" : "en_US")
                        delegate: Label {
                            required property string shortName
                            text: shortName
                            color: Color.muted
                            font.pixelSize: Style.fontCaption
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    QC.MonthGrid {
                        id: grid
                        width: parent.width
                        height: 6 * 24 + 5 * spacing
                        month: root.shown.getMonth()
                        year: root.shown.getFullYear()
                        locale: Qt.locale(root.mondayFirst ? "en_GB" : "en_US")
                        spacing: 2
                        delegate: Rectangle {
                            required property var model
                            readonly property bool today: model.today
                            readonly property bool inMonth: model.month === grid.month
                            readonly property bool weekend: model.date.getDay() === 0 || model.date.getDay() === 6
                            implicitHeight: 24
                            radius: Style.radius
                            color: today ? Color.accent : "transparent"

                            Label {
                                anchors.centerIn: parent
                                text: parent.model.day
                                color: parent.today ? Color.base : (!parent.inMonth ? Color.surface2 : (parent.weekend ? Color.overlay1 : Color.text))
                                font.pixelSize: Style.fontSmall
                            }
                        }
                    }
                }
            }
        }
    }
}
