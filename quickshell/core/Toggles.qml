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

    // Last requested state per toggle, applied one qs-toggle at a time.
    // Concurrent on/off runs raced and the slower one won.
    property var pending: ({})

    function set(name, on) {
        if (has(name) === on && pending[name] === undefined)
            return;
        const next = Object.assign({}, active);
        if (on)
            next[name] = true;
        else
            delete next[name];
        active = next;
        pending = Object.assign({}, pending, {
            [name]: on
        });
        drain();
    }

    function flip(name) {
        set(name, !has(name));
    }

    function refresh() {
        lister.running = true;
    }

    function drain() {
        if (runner.running)
            return;
        const name = Object.keys(pending)[0];
        if (name === undefined)
            return;
        const on = pending[name];
        const rest = Object.assign({}, pending);
        delete rest[name];
        pending = rest;
        runner.command = [Util.bin("qs-toggle"), name, on ? "on" : "off"];
        runner.running = true;
    }

    Process {
        id: runner
        onExited: root.drain() // qmllint disable signal-handler-parameters
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
