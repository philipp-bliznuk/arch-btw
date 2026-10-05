pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Boolean shell state as flag files in ~/.local/state/qs/toggles/<name>.
// Side effects (wlsunset, systemd-inhibit) live in bin/qs-toggle so shell
// scripts and the launcher share one implementation. qs-toggle calls
// `qs-shell -q toggles refresh` after each change.
Singleton {
    id: root

    readonly property string dir: Util.stateDir + "/toggles"
    property var active: ({})

    function has(name) {
        return active[name] === true;
    }

    function set(name, on) {
        const next = Object.assign({}, active);
        if (on)
            next[name] = true;
        else
            delete next[name];
        active = next;
        Commands.run({
            argv: [Util.bin("qs-toggle"), name, on ? "on" : "off"]
        });
    }

    function flip(name) {
        set(name, !has(name));
    }

    function refresh() {
        lister.running = true;
    }

    Process {
        id: lister
        command: ["ls", "-1", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const next = {};
                for (const line of text.split("\n"))
                    if (line.trim())
                        next[line.trim()] = true;
                root.active = next;
            }
        }
    }

    Component.onCompleted: refresh()
}
