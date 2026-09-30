pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.ui

// Hidden-until-active state glyphs (stay awake, reboot required). DND and
// night light have their own always-visible segments.
Segment {
    id: root
    readonly property var toggles: [
        {
            name: "awake",
            glyph: Icons.eye,
            color: Color.yellow,
            tip: "Stay awake"
        }
    ].filter(i => Toggles.has(i.name))
    readonly property var items: toggles.concat(System.rebootRequired ? [
        {
            name: "reboot",
            glyph: Icons.restart,
            color: Color.peach,
            tip: "Reboot required · " + System.summary
        }
    ] : [])

    visible: items.length > 0
    tooltip: items.map(i => i.tip).join(" · ")
    onClicked: Quickshell.execDetached([Util.bin("qs-shell"), "-q", "launcher", "open", System.rebootRequired ? "system" : "toggle"])

    content: Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spaceSm

        Repeater {
            model: root.items

            Glyph {
                required property var modelData
                text: modelData.glyph
                glyphColor: modelData.color
            }
        }
    }
}
