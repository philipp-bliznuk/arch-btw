import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Background layer per screen. ~/.config/wallpapers -> dotfiles/wallpapers (post-install symlink).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel
        required property var modelData
        screen: modelData

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Color.base

        WlrLayershell.namespace: "qs-wallpaper"
        WlrLayershell.layer: WlrLayer.Background

        Image {
            anchors.fill: parent
            source: Util.home() + "/.config/wallpapers/wallpaper1.jpg"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: panel.screen.width
            sourceSize.height: panel.screen.height
        }
    }
}
