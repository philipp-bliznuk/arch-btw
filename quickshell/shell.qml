import QtQuick
import Quickshell
import Quickshell.Io
import "panel"
import "launcher"
import "background"
import "notifications"
import "polkit"
import "osd"
import "clipboard"
import qs.core

ShellRoot {
    id: root

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Util.stateDir + "/toggles"])

    Background {}

    Service {
        id: notifications
    }

    Agent {}

    Osd {}

    Clipboard {
        id: clipboard
    }

    Panel {}

    Launcher {
        id: launcher
        notifications: notifications
        clipboard: clipboard
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

        function select(prompt: string, tsv: string, outfile: string): void {
            launcher.openSelect(prompt, tsv, outfile);
        }
    }

    IpcHandler {
        target: "toggles"

        function refresh(): void {
            Toggles.refresh();
        }
    }

    IpcHandler {
        target: "shell"

        function ping(): string {
            return "pong";
        }
    }
}
