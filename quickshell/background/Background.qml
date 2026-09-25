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
    property string current: fallback

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

        function current(): string {
            return root.current;
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
            color: Color.base

            WlrLayershell.namespace: "qs-wallpaper"
            WlrLayershell.layer: WlrLayer.Background

            // two layers for crossfade
            property int front: 0
            readonly property var layers: [a, b]

            Connections {
                target: root
                function onCurrentChanged() {
                    const back = panel.layers[1 - panel.front];
                    back.source = root.current;
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

            Layer { id: a; source: root.current; opacity: 1 }
            Layer { id: b }
        }
    }
}
