pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.ui

// Weather: glyph + temperature in the bar; popup with hero, location
// (editable), feels/wind/humidity, sunrise/sunset. Click opens the popup.
// Keys: e/Enter edit location · r refresh · u toggle °C/°F · d IP location.
Segment {
    id: root
    visible: Weather.ready
    icon: Weather.glyph(Weather.current.weather_code, Weather.current.is_day)
    iconColor: Color.yellow
    label: Weather.temp(Weather.current.temperature_2m)
    active: popup.open
    property bool editing: false

    onClicked: popup.toggle()

    function startEdit() {
        editing = true;
        search.text = "";
        search.input.forceActiveFocus();
    }

    function commitEdit() {
        const q = search.text.trim();
        stopEdit();
        if (q)
            Weather.setLocation(q);
    }

    // Hand focus back to the card's key handler, not the card itself.
    function stopEdit() {
        editing = false;
        popup.focusKeys();
    }

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "weather"
        cardWidth: 300
        onOpenChanged: if (!open) root.editing = false
        keymap: [
            { key: "e Enter", run: () => root.startEdit() },
            { key: "r", run: () => Weather.refresh() },
            { key: "u", run: () => Settings.set("weatherUnit", Weather.imperial ? "metric" : "imperial") },
            { key: "d", run: () => Weather.clearLocation() }
        ]

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
                }
            }

            ListRow {
                visible: !root.editing
                glyph: Icons.mapMarker
                glyphColor: Color.accent
                title: Weather.name || "Detecting location…"
                onClicked: root.startEdit()
            }

            Row {
                visible: root.editing
                width: parent.width
                spacing: Style.spaceXs

                Field {
                    id: search
                    width: parent.width - clear.width - parent.spacing
                    placeholder: "City, e.g. Lviv or Kyiv, UA - Enter to set, Esc to cancel"
                    onAccepted: root.commitEdit()
                    onEscaped: root.stopEdit()
                }
                Segment {
                    id: clear
                    anchors.verticalCenter: parent.verticalCenter
                    icon: Icons.close
                    onClicked: {
                        root.stopEdit();
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
                    value: (Weather.current.relative_humidity_2m ?? "-") + "%"
                }
            }

            Row {
                visible: Sun.known
                width: parent.width
                spacing: Style.spaceMd

                Stat {
                    glyph: Icons.sunrise
                    title: "SUNRISE"
                    value: Qt.formatTime(Sun.sunrise, "HH:mm")
                }
                Stat {
                    glyph: Icons.sunset
                    title: "SUNSET"
                    value: Qt.formatTime(Sun.sunset, "HH:mm")
                }
                Stat {
                    glyph: Icons.nightlight
                    title: "NIGHT LIGHT"
                    value: Sun.auto ? "auto" : "manual"
                }
            }
        }
    }
}
