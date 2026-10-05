pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import qs.core
import qs.ui

// Battery: 10-level glyphs, optional %, "Holding" when the charge limit is
// reached; popup with power profiles and charge limit. State lives in
// core/Power (one udev listener, one toast for all outputs).
// Keys: j/k profile · Enter apply · c charge limit · p toggle %.
Segment {
    id: root
    readonly property bool showPct: Settings.get("batteryPercent")
    readonly property bool charging: Power.charging && !Power.holding

    visible: Power.present
    icon: Icons.batteryFor(Power.pct, charging)
    iconColor: charging ? Color.green : (Power.pct < 10 ? Color.red : (Power.pct < 30 ? Color.yellow : Color.text))
    label: showPct ? Power.pct + "%" : ""
    active: popup.open

    onClicked: popup.toggle()

    PopupCard {
        id: popup
        anchorItem: root
        popupId: "battery"
        cardWidth: 300
        count: Power.profiles.length
        keymap: [
            { key: "j k", run: k => cursor = Util.clamp(cursor + (k === "j" ? 1 : -1), 0, count - 1) },
            { key: "Enter", run: () => { if (Power.profiles[cursor] !== undefined) PowerProfiles.profile = Power.profiles[cursor]; } },
            { key: "c", run: () => Power.toggleLimit() },
            { key: "p", run: () => Settings.set("batteryPercent", !root.showPct) }
        ]

        onOpenChanged: if (open) Power.refreshLimit()

        Column {
            width: parent.width
            spacing: Style.spaceMd

            Item {
                width: parent.width
                height: 40

                Glyph {
                    id: heroGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 40
                    text: root.icon
                    glyphColor: root.iconColor
                    size: Style.fontTitle + 8
                }
                Column {
                    anchors.left: heroGlyph.right
                    anchors.leftMargin: Style.spaceMd
                    anchors.right: heroPct.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        width: parent.width
                        text: Power.mode
                        font.pixelSize: Style.fontTitle
                    }
                    Label {
                        width: parent.width
                        text: Power.remaining || (Power.holding ? "charge limit reached" : "")
                        color: Color.muted
                        font.pixelSize: Style.fontCaption
                    }
                }
                Label {
                    id: heroPct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Power.pct + "%"
                    font.pixelSize: Style.fontTitle + 6
                    color: root.iconColor
                }
            }

            Rectangle {
                width: parent.width
                height: 6
                radius: 3
                color: Color.surface1

                Rectangle {
                    id: fill
                    width: parent.width * Power.pct / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.iconColor

                    SequentialAnimation on opacity {
                        running: root.charging && popup.open
                        loops: Animation.Infinite
                        NumberAnimation {
                            to: 0.45
                            duration: 900
                        }
                        NumberAnimation {
                            to: 1
                            duration: 900
                        }
                        onRunningChanged: if (!running) fill.opacity = 1
                    }
                }
            }

            // Charge limit: holds the cell between start→end % while plugged in.
            // Lithium cells age fastest sitting at 100 %; 80 % roughly doubles
            // cycle life. Turn it off before travel to top up.
            Rectangle {
                id: limitRow
                visible: Power.limit.supported === true
                width: parent.width
                height: Style.rowHeight
                radius: Style.radius
                color: limitHover.hovered ? Color.surface1 : Color.surface0

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spaceMd

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.batteryFor(Power.limit.end ?? 80, false)
                        glyphColor: Power.limit.enabled ? Color.green : Color.subtext0
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Label {
                            text: "Charge limit"
                            font.pixelSize: Style.fontSmall
                        }
                        Label {
                            text: Power.limit.enabled ? "charges " + Power.limit.start + " → " + Power.limit.end + " %, kinder to the cell" : "off - charges to 100 %"
                            color: Color.muted
                            font.pixelSize: Style.fontCaption
                        }
                    }
                }
                Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    text: Power.limit.enabled ? "ON" : "OFF"
                    color: Power.limit.enabled ? Color.green : Color.muted
                    font.pixelSize: Style.fontCaption
                    font.weight: Font.Bold
                }
                HoverHandler {
                    id: limitHover
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Power.toggleLimit()
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Color.surface1
                visible: Power.profilesAvailable
            }

            Label {
                visible: Power.profilesAvailable
                text: "POWER PROFILE"
                color: Color.muted
                font.pixelSize: Style.fontCaption
            }

            Row {
                visible: Power.profilesAvailable
                width: parent.width
                spacing: Style.spaceXs

                Repeater {
                    model: Power.profiles

                    Rectangle {
                        id: prof
                        required property var modelData
                        required property int index
                        readonly property bool current: PowerProfiles.profile === modelData
                        width: (parent.width - Style.spaceXs * (Power.profiles.length - 1)) / Power.profiles.length
                        height: 48
                        radius: Style.radius
                        color: current ? Color.segmentActive : (popup.cursor === index ? Color.segmentHover : Color.surface0)
                        border.width: popup.cursor === index ? 1 : 0
                        border.color: Color.accent

                        Column {
                            anchors.centerIn: parent
                            spacing: 0

                            Glyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Power.profileGlyph(prof.modelData)
                                glyphColor: prof.current ? Color.accent : Color.subtext0
                            }
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Power.profileName(prof.modelData)
                                color: prof.current ? Color.text : Color.muted
                                font.pixelSize: Style.fontCaption
                            }
                        }

                        HoverHandler {
                            onHoveredChanged: if (hovered) popup.cursor = prof.index
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: PowerProfiles.profile = prof.modelData
                        }
                    }
                }
            }
        }
    }
}
