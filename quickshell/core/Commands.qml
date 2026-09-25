pragma Singleton
import QtQuick
import Quickshell

// Single execution funnel. Every actionable row/button is data; only this
// file turns data into a process.
//
// Row keys, checked in order:
//   entry -> DesktopEntry.execute()
//   argv  -> exec argv directly (preferred)
//   sway  -> swaymsg <cmd>
//   copy  -> put text on the clipboard
//   run   -> shell string via bash -lc (legacy, avoid for new rows)
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
        if (r.sway) {
            Quickshell.execDetached(["swaymsg", r.sway]);
            return true;
        }
        if (r.copy !== undefined) {
            copy(r.copy);
            return true;
        }
        if (r.run) {
            Quickshell.execDetached(["bash", "-lc", r.run]);
            return true;
        }
        return false;
    }

    function copy(text) {
        Quickshell.execDetached(["bash", "-c", 'printf %s "$1" | wl-copy', "bash", String(text ?? "")]);
    }

    function term(argv) {
        return ["ghostty", "-e"].concat(argv);
    }
}
