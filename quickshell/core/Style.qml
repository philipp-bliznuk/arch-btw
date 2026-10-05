pragma Singleton
import QtQuick

// Design tokens. One font weight, one render type; every Text goes through
// ui/Label or ui/Glyph so baselines line up.
QtObject {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontCaption: 10
    readonly property int fontSmall: 12
    readonly property int fontBody: 13
    readonly property int fontTitle: 16
    readonly property int fontIcon: 14
    readonly property int fontWeight: Font.Medium
    readonly property int renderType: Text.NativeRendering

    readonly property int panelHeight: 30
    readonly property int segmentHeight: 22
    readonly property int segmentPadX: 4
    readonly property int radius: 6

    readonly property int spaceXs: 4
    readonly property int spaceSm: 6
    readonly property int spaceMd: 8
    readonly property int spaceLg: 10
    readonly property int spaceXl: 12

    readonly property int cardWidth: 680
    readonly property int cardMaxHeight: 520
    readonly property int rowHeight: 36
    readonly property int crumbHeight: 14
    readonly property int cardRadius: 10
    readonly property int cardPadding: 10

    readonly property int notifWidth: 380
    readonly property int popupWidth: 320
    readonly property int osdWidth: 260
    readonly property int mediaWidth: 260
    readonly property int tooltipDelay: 600
}
