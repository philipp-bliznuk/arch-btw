pragma Singleton
import QtQuick

// Catppuccin Mocha, hardcoded.
QtObject {
    readonly property color rosewater: "#f5e0dc"
    readonly property color flamingo: "#f2cdcd"
    readonly property color pink: "#f5c2e7"
    readonly property color mauve: "#cba6f7"
    readonly property color red: "#f38ba8"
    readonly property color maroon: "#eba0ac"
    readonly property color peach: "#fab387"
    readonly property color yellow: "#f9e2af"
    readonly property color green: "#a6e3a1"
    readonly property color teal: "#94e2d5"
    readonly property color sky: "#89dceb"
    readonly property color sapphire: "#74c7ec"
    readonly property color blue: "#89b4fa"
    readonly property color lavender: "#b4befe"
    readonly property color text: "#cdd6f4"
    readonly property color subtext1: "#bac2de"
    readonly property color subtext0: "#a6adc8"
    readonly property color overlay2: "#9399b2"
    readonly property color overlay1: "#7f849c"
    readonly property color overlay0: "#6c7086"
    readonly property color surface2: "#585b70"
    readonly property color surface1: "#45475a"
    readonly property color surface0: "#313244"
    readonly property color base: "#1e1e2e"
    readonly property color mantle: "#181825"
    readonly property color crust: "#11111b"

    // Semantic
    readonly property color barBg: "transparent"
    readonly property color pillBg: surface0
    readonly property color pillBorder: Qt.rgba(surface2.r, surface2.g, surface2.b, 0.38)
    readonly property color pillHover: surface1
    readonly property color icon: text
    readonly property color label: text
    readonly property color muted: overlay1
    readonly property color accent: blue
    readonly property color urgent: red
    readonly property color scrim: Qt.rgba(crust.r, crust.g, crust.b, 0.55)
    readonly property color cardBg: base
    readonly property color cardBorder: overlay0
    readonly property color rowSelected: surface1
}
