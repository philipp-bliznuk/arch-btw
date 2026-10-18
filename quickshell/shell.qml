//@ pragma NativeTextRendering
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
import "lock"
import qs.core
import qs.ui

ShellRoot {
    id: root

    Background {
        id: background
    }

    Locker {
        id: locker
        wallpaper: background.current
    }

    Idle {}

    Service {
        id: notifications
    }

    Agent {}

    Osd {
        id: osd
    }

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

    // sway: set $menu qs-shell launcher toggle
    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle();
        }

        function open(section: string): void {
            launcher.openSection(section);
        }
    }

    IpcHandler {
        target: "toggles"

        function refresh(): void {
            Toggles.refresh();
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
    }

    // Locking must close anything holding exclusive keyboard focus: sway 1.12
    // lets such layer surfaces keep the keyboard away from the lock surface.
    Connections {
        target: Lock

        function onLockedChanged() {
            if (!Lock.locked)
                return;
            launcher.close();
            Popups.close();
        }
    }

    // sway media binds; the same player the bar shows, then the OSD toast.
    IpcHandler {
        target: "media"

        function toggle(): void {
            Player.toggle();
            osd.showMedia();
        }

        function next(): void {
            Player.next();
            osd.showMedia();
        }

        function previous(): void {
            Player.previous();
            osd.showMedia();
        }
    }

    // No unlock here on purpose: any process of the user can call IPC.
    IpcHandler {
        target: "lock"

        function lock(): string {
            return locker.lock();
        }

        function status(): string {
            return locker.statusJson();
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
            Toggles.refresh();
            Metrics.resetRates();
        }
    }
}
