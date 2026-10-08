pragma Singleton
import QtQuick
import Quickshell

// Single execution funnel. Every actionable row/button is data; only this
// file turns data into a process.
//
// Row keys, checked in order:
//   entry -> DesktopEntry.execute()
//   argv  -> exec argv directly (preferred)
//   term  -> argv inside a new terminal window (editors, TUIs)
//   task  -> argv via qs-task: floating terminal that waits for Enter when done
//   sway  -> swaymsg <cmd>
//   copy  -> put text on the clipboard
QtObject {
    function run(r) {
        if (!r)
            return false;
        if (r.entry) {
            r.entry.execute();
            return true;
        }
        if (r.argv) {
            Quickshell.execDetached(r.argv);
            return true;
        }
        if (r.term) {
            Quickshell.execDetached(term(r.term));
            return true;
        }
        if (r.task) {
            Quickshell.execDetached([Util.bin("qs-task")].concat(r.task));
            return true;
        }
        if (r.sway) {
            Quickshell.execDetached(["swaymsg", r.sway]);
            return true;
        }
        if (r.copy !== undefined) {
            copy(r.copy);
            return true;
        }
        return false;
    }

    function copy(text) {
        Quickshell.execDetached(["bash", "-c", 'printf %s "$1" | wl-copy', "bash", String(text ?? "")]);
    }

    // The only place besides sway/config and bin/qs-task that names the terminal.
    function term(argv) {
        return ["kitty", "-1", "--class", "qs-term", "--"].concat(argv);
    }
}
