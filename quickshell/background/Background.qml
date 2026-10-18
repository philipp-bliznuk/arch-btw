pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core

// Background layer per screen. Current file = ~/.local/state/qs/background symlink
// (managed by bin/qs-wallpaper, which calls `qs-shell -q background refresh`).
// Fallback: ~/.config/wallpapers/wallpaper1.jpg.
Scope {
    id: root

    readonly property string fallback: Util.home() + "/.config/wallpapers/wallpaper1.jpg"
    property string current: "" // "" until the resolver answers, so its first answer is a change

    function refresh() {
        resolver.running = true;
    }

    Process {
        id: resolver
        command: ["readlink", "-e", Util.stateDir + "/background"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                root.current = p !== "" ? p : root.fallback;
            }
        }
        onExited: (code, status) => { // qmllint disable signal-handler-parameters
            if (code !== 0)
                root.current = root.fallback;
        }
    }

    Component.onCompleted: refresh()

    IpcHandler {
        target: "background"

        function refresh(): void {
            root.refresh();
        }
    }

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
            color: Theme.base

            WlrLayershell.namespace: "qs-wallpaper"
            WlrLayershell.layer: WlrLayer.Background

            // Two layers for the crossfade: a change loads into the back one,
            // which becomes the front once decoded. A panel created later (new
            // output) starts on the current file; at startup nothing is decoded
            // before the resolver answers.
            property int front: 0
            readonly property var layers: [a, b]

            Component.onCompleted: a.source = Util.fileUrl(root.current)

            Connections {
                target: root
                function onCurrentChanged() {
                    panel.layers[1 - panel.front].source = Util.fileUrl(root.current);
                }
            }

            component Layer: Image {
                id: img
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: panel.screen.width
                sourceSize.height: panel.screen.height
                opacity: 0
                Behavior on opacity {
                    NumberAnimation { duration: 350 }
                }
                onStatusChanged: {
                    if (status === Image.Ready && panel.layers[panel.front] !== img) {
                        panel.front = panel.layers.indexOf(img);
                        for (const l of panel.layers)
                            l.opacity = l === img ? 1 : 0;
                    }
                }
            }

            Layer { id: a; opacity: 1 }
            Layer { id: b }

            // Stay-awake toggle. Sway counts a layer-surface inhibitor only
            // while its surface is mapped, which the wallpaper always is.
            IdleInhibitor {
                enabled: Toggles.has("awake")
                window: panel
            }
        }
    }
}
