import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Clipboard history reader. bin/qs-clipboard owns ~/.local/state/qs/clipboard.json:
// two wl-paste watchers feed it, remove and clear go through it, and it pings
// `clipboard refresh` after every write, so one lock orders them all.
// Watchers outlive a crashed shell; qs-session kills them before relaunching.
Scope {
    id: root

    property var entries: []

    function refresh() {
        store.reload();
    }

    function remove(entry) {
        Quickshell.execDetached([Util.bin("qs-clipboard"), "remove", entry.kind, String(entry.time)]);
    }

    function clear() {
        Quickshell.execDetached([Util.bin("qs-clipboard"), "clear"]);
    }

    function copy(entry) {
        if (entry.kind === "image")
            Quickshell.execDetached(["bash", "-c", 'wl-copy -t image/png < "$1"', "bash", entry.file]);
        else
            Commands.copy(entry.text);
    }

    FileView {
        id: store
        path: Util.stateDir + "/clipboard.json"
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed))
                    root.entries = parsed;
            } catch (e) {
                console.warn("clipboard: bad history file, ignoring");
            }
        }
    }

    Process {
        command: ["wl-paste", "--type", "text", "--watch", Util.bin("qs-clipboard"), "text"]
        running: true
    }

    Process {
        command: ["wl-paste", "--type", "image/png", "--watch", Util.bin("qs-clipboard"), "image"]
        running: true
    }

    IpcHandler {
        target: "clipboard"

        function refresh(): void {
            root.refresh();
        }
    }
}
