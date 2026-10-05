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
import qs.ui

ShellRoot {
    id: root

    Background {}

    Service {
        id: notifications
    }

    Agent {}

    Osd {}

    Clipboard {
        id: clipboard
    }

    PopupHost {}

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
        target: "system"

        function refresh(): void {
            System.refresh();
        }

        function rebootRequired(): string {
            return System.summary;
        }
    }

    IpcHandler {
        target: "popups"

        function toggle(id: string): void {
            Popups.toggle(id);
        }

        function open(id: string): void {
            Popups.open(id);
        }

        function close(): void {
            Popups.close();
        }

        function current(): string {
            return Popups.current;
        }
    }

    IpcHandler {
        target: "shell"

        function ping(): string {
            return "pong";
        }

        // Timers run on the monotonic clock and freeze across suspend/hibernate;
        // swayidle calls this on wake so clock-bound state catches up at once.
        function resume(): void {
            Weather.refresh();
            Sun.wake();
            Metrics.resetRates();
        }
    }
}
