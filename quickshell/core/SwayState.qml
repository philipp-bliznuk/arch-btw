pragma Singleton
import QtQuick
import Quickshell
import Quickshell.I3

// Sway facts derived from Quickshell.I3, shared by panel/popups/launcher.
Singleton {
    id: root

    readonly property var focusedMonitor: I3.focusedMonitor
    readonly property var focusedScreen: screenFor(focusedMonitor) ?? (Quickshell.screens.length ? Quickshell.screens[0] : null)

    function screenFor(monitor) {
        if (!monitor)
            return null;
        for (const s of Quickshell.screens)
            if (I3.monitorFor(s) === monitor)
                return s;
        return null;
    }

    function workspacesOn(screen) {
        const mon = screen ? I3.monitorFor(screen) : null;
        return I3.workspaces.values.filter(w => !mon || !w.monitor || w.monitor === mon);
    }
}
