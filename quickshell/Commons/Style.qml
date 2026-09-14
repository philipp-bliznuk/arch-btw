pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontCaption: 10
    readonly property int fontSmall: 11
    readonly property int fontBody: 13
    readonly property int fontIcon: 14
    readonly property int fontTitle: 16

    readonly property int barHeight: 28
    readonly property int barPadding: 6
    readonly property int pillHeight: 22
    readonly property int pillPadding: 8
    readonly property int pillGap: 6
    readonly property int radius: 5

    readonly property int cardWidth: 640
    readonly property int cardMaxHeight: 520
    readonly property int rowHeight: 36
    readonly property int cardRadius: 10
    readonly property int cardPadding: 10
}
