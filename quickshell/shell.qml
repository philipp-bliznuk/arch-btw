import QtQuick
import Quickshell
import Quickshell.Io
import "Bar"
import "Launcher"
import "Wallpaper"

ShellRoot {
    id: root

    Wallpaper {}

    Bar {}

    Launcher {
        id: launcher
    }

    // sway: set $menu qs ipc call launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle();
        }

        function open(section: string): void {
            launcher.openSection(section);
        }

        function close(): void {
            launcher.close();
        }
    }
}
