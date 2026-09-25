pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.ui

// Manual-state glyphs, hidden until something is active (omarchy pattern).
Pill {
    id: root
    readonly property var items: [
        { name: "awake", glyph: Icons.eye, tip: "Stay awake" },
        { name: "nightlight", glyph: Icons.moon, tip: "Night light" },
        { name: "dnd", glyph: Icons.bellOff, tip: "Do not disturb" },
    ].filter(i => Toggles.has(i.name))

    visible: items.length > 0
    hoverable: false

    content: Row {
        spacing: 6

        Repeater {
            model: root.items

            Glyph {
                required property var modelData
                text: modelData.glyph
                glyphColor: Color.yellow
            }
        }
    }
}
