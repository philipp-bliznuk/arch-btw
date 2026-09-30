pragma Singleton
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io

// Sway facts derived from Quickshell.I3, shared by panel/popups/launcher.
// focusedScreen chain: focusedMonitor → focusedWorkspace.monitor → screens[0].
Singleton {
    id: root

    readonly property var focusedMonitor: I3.focusedMonitor ?? (I3.focusedWorkspace ? I3.focusedWorkspace.monitor : null)
    readonly property var focusedScreen: screenFor(focusedMonitor) ?? (Quickshell.screens.length ? Quickshell.screens[0] : null)

    // Outputs showing a fullscreen window right now (fullscreen_mode 2 = all).
    // Read from sway's tree: foreign-toplevel screen lists flap during
    // relayout and made the bar on the *other* output jitter.
    property var fullscreenOutputs: []

    function fullscreenOn(screen) {
        return !!screen && (fullscreenOutputs.includes("*") || fullscreenOutputs.includes(screen.name));
    }

    Process {
        id: treeProbe
        command: ["sh", "-c", "swaymsg -t get_tree | jq -r '[.. | objects | select(.fullscreen_mode? == 2 and .visible? == true)] | length > 0 | if . then \"*\" else empty end, (.. | objects | select(.type? == \"output\") | select([.. | objects | select(.fullscreen_mode? == 1 and .visible? == true)] | length > 0) | .name)'"]
        stdout: StdioCollector {
            onStreamFinished: root.fullscreenOutputs = text.split("\n").filter(l => l)
        }
    }

    Connections {
        target: I3
        function onRawEvent(event) {
            if (event.type === "window" || event.type === "workspace" || event.type === "output")
                treeProbe.running = true;
        }
    }

    Component.onCompleted: treeProbe.running = true

    function screenFor(monitor) {
        if (!monitor)
            return null;
        for (const s of Quickshell.screens) {
            if (I3.monitorFor(s) === monitor || s.name === monitor.name)
                return s;
        }
        return null;
    }

    function workspacesOn(screen) {
        const mon = screen ? I3.monitorFor(screen) : null;
        return I3.workspaces.values.filter(w => !mon || !w.monitor || w.monitor === mon);
    }
}
