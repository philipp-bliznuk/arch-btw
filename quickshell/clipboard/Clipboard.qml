import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Clipboard history owner. Two wl-paste watchers feed bin/qs-clipboard-capture,
// which maintains ~/.local/state/qs/clipboard.json and pings `clipboard refresh`.
// Watchers die with Quickshell (Process children are killed on exit).
Scope {
    id: root

    property var entries: []

    function refresh() {
        store.reload();
    }

    function remove(entry) {
        entries = entries.filter(e => !(e.kind === entry.kind && (e.text === entry.text && e.file === entry.file)));
        store.setText(JSON.stringify(entries));
        if (entry.kind === "image" && entry.file)
            Quickshell.execDetached(["rm", "-f", entry.file]);
    }

    function clear() {
        entries = [];
        store.setText("[]");
        Quickshell.execDetached(["bash", "-c", 'rm -f "$1"/*', "bash", Util.stateDir + "/clipboard-images"]);
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
        atomicWrites: true
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
        command: ["wl-paste", "--type", "text", "--watch", Util.bin("qs-clipboard-capture"), "text"]
        running: true
    }

    Process {
        command: ["wl-paste", "--type", "image/png", "--watch", Util.bin("qs-clipboard-capture"), "image"]
        running: true
    }

    IpcHandler {
        target: "clipboard"

        function refresh(): void {
            root.refresh();
        }

        function clear(): void {
            root.clear();
        }

        function count(): int {
            return root.entries.length;
        }
    }
}
