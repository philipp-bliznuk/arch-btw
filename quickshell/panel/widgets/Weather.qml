pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.ui

// Weather (omarchy parity): glyph + temperature in the bar; popup with hero,
// location (editable), feels/wind/humidity, 3-day forecast.
// Click popup · middle refresh · right-click notification summary.
// Keys: e/Enter edit location · r refresh · u toggle °C/°F · Esc.
Segment {
    id: root
    visible: Weather.ready
    icon: Weather.glyph(Weather.current.weather_code, Weather.current.is_day)
    iconColor: Color.yellow
    label: Weather.temp(Weather.current.temperature_2m)
    tooltip: Weather.ready ? Weather.name + " · " + Weather.describe(Weather.current.weather_code) + " · feels " + Weather.temp(Weather.current.apparent_temperature) : ""
    active: popup.open
    property bool editing: false

    onClicked: m => {
        if (m.button === Qt.MiddleButton)
            Weather.refresh();
        else if (m.button === Qt.RightButton)
            Quickshell.execDetached(["sh", "-c", Util.bin("qs-notify") + ' -i weather-clear "Weather" "$(' + Util.bin("qs-weather") + ' status)"']);
        else
            popup.toggle();
    }

    function dayName(iso, i) {
        if (i === 0)
            return "Today";
        const d = new Date(iso + "T12:00:00");
        return Qt.formatDate(d, "ddd");
    }

    function startEdit() {
        editing = true;
        search.text = "";
        search.input.forceActiveFocus();
    }

    function commitEdit() {
        const q = search.text.trim();
        editing = false;
        if (q)
            Weather.setLocation(q);
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "weather"
        cardWidth: 300
        onOpenChanged: if (!open) root.editing = false
        onAction: a => {
            switch (a) {
            case "edit":
            case "activate":
                root.startEdit();
                break;
            case "loop":
                Weather.refresh();
                break;
            case "unit":
                Settings.set("weatherUnit", Weather.imperial ? "metric" : "imperial");
                break;
            case "delete":
                Weather.clearLocation();
                break;
            }
        }

        component Stat: Column {
            id: stat
            property string glyph: ""
            property string title: ""
            property string value: ""
            width: (parent.width - Style.spaceMd * 2) / 3
            spacing: 0

            Row {
                spacing: Style.spaceXs
                Glyph {
                    text: stat.glyph
                    glyphColor: Color.muted
                    size: Style.fontSmall
                    height: 14
                }
                Label {
                    text: stat.title
                    color: Color.muted
                    font.pixelSize: Style.fontCaption
                    height: 14
                }
            }
            Label {
                text: stat.value
                font.pixelSize: Style.fontSmall
            }
        }

        Column {
            width: parent.width
            spacing: Style.spaceMd

            Item {
                width: parent.width
                height: 56

                Glyph {
                    id: heroGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56
                    height: 56
                    text: root.icon
                    glyphColor: Color.yellow
                    size: 44
                }
                Column {
                    anchors.left: heroGlyph.right
                    anchors.leftMargin: Style.spaceMd
                    anchors.right: heroTemp.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        text: Weather.describe(Weather.current.weather_code)
                        font.pixelSize: Style.fontTitle
                    }
                    Label {
                        width: parent.width
                        text: Weather.busy ? "updating…" : Weather.name
                        color: Color.muted
                        font.pixelSize: Style.fontCaption
                    }
                }
                Label {
                    id: heroTemp
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.temp(Weather.current.temperature_2m).replace("°", "") + Weather.unit
                    font.pixelSize: Style.fontTitle + 8

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Settings.set("weatherUnit", Weather.imperial ? "metric" : "imperial")
                    }
                }
            }

            ListRow {
                visible: !root.editing
                glyph: Icons.mapMarker
                glyphColor: Color.accent
                title: Weather.name || "Detecting location…"
                trailing: "change · e"
                onClicked: root.startEdit()
            }

            Row {
                visible: root.editing
                width: parent.width
                spacing: Style.spaceXs

                Field {
                    id: search
                    width: parent.width - clear.width - parent.spacing
                    placeholder: "City, e.g. Lviv or Kyiv, UA — Enter to set, Esc to cancel"
                    onAccepted: root.commitEdit()
                    onEscaped: {
                        root.editing = false;
                        popup.forceActiveFocus();
                    }
                }
                Segment {
                    id: clear
                    icon: Icons.close
                    tooltip: "Use IP location"
                    onClicked: {
                        root.editing = false;
                        Weather.clearLocation();
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Style.spaceMd

                Stat {
                    glyph: Icons.thermometer
                    title: "FEELS"
                    value: Weather.temp(Weather.current.apparent_temperature)
                }
                Stat {
                    glyph: Icons.windy
                    title: "WIND"
                    value: Weather.wind(Weather.current.wind_speed_10m)
                }
                Stat {
                    glyph: Icons.humidity
                    title: "HUMID"
                    value: (Weather.current.relative_humidity_2m ?? "–") + "%"
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Color.surface1
            }

            Row {
                width: parent.width
                spacing: Style.spaceXs

                Repeater {
                    model: Weather.daily.time ? Weather.daily.time.slice(1, 4) : []

                    Column {
                        id: day
                        required property string modelData
                        required property int index
                        readonly property int i: index + 1
                        width: (parent.width - Style.spaceXs * 2) / 3
                        spacing: 2

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.dayName(day.modelData, day.i)
                            color: Color.muted
                            font.pixelSize: Style.fontCaption
                        }
                        Glyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Weather.glyph(Weather.daily.weather_code[day.i], true)
                            glyphColor: Color.yellow
                            size: Style.fontTitle + 4
                            height: 28
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Weather.temp(Weather.daily.temperature_2m_max[day.i]) + " / " + Weather.temp(Weather.daily.temperature_2m_min[day.i])
                            font.pixelSize: Style.fontSmall
                        }
                    }
                }
            }
        }
    }
}
