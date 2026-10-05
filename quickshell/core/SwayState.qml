pragma Singleton
import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Io

// Sway facts derived from Quickshell.I3, shared by panel/popups/launcher.
// focusedScreen chain: focusedMonitor → focusedWorkspace.monitor → screens[0].
//
// Quickshell.I3 only forwards workspace/output events, so one persistent
// `swaymsg -m subscribe` here carries everything else the bar needs:
// window (occupancy + fullscreen), mode (binding mode), input (xkb layout).
Singleton {
    id: root

    readonly property var focusedMonitor: I3.focusedMonitor ?? (I3.focusedWorkspace ? I3.focusedWorkspace.monitor : null)
    readonly property var focusedScreen: screenFor(focusedMonitor) ?? (Quickshell.screens.length ? Quickshell.screens[0] : null)

    // Active binding mode ("default", "resize", "popup"…).
    property string mode: "default"

    // Active xkb layout name as sway reports it ("English (US)").
    property string layoutName: ""

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

    Process {
        id: inputProbe
        running: true
        command: ["swaymsg", "-t", "get_inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kb = JSON.parse(text).find(i => i.type === "keyboard" && i.xkb_active_layout_name);
                    if (kb)
                        root.layoutName = kb.xkb_active_layout_name;
                } catch (e) {}
            }
        }
    }

    Connections {
        target: I3
        function onRawEvent(event) {
            if (event.type === "workspace" || event.type === "output")
                treeProbe.running = true;
        }
    }

    Component.onCompleted: treeProbe.running = true

    // Workspace occupancy lives in get_workspaces' `representation`, which only
    // moves when a window appears, leaves or changes workspace; focus and
    // title events (browsers retitle constantly) are ignored.
    readonly property var occupancyEvents: ["new", "close", "move", "floating"]

    function onWindow(ev) {
        if (occupancyEvents.includes(ev.change))
            I3.refreshWorkspaces();
        if (ev.change === "fullscreen_mode" || ev.change === "close" || ev.change === "move")
            treeProbe.running = true;
    }

    function onEvent(line) {
        const ev = JSON.parse(line);
        if (ev.input !== undefined && ev.change === "xkb_layout")
            root.layoutName = ev.input.xkb_active_layout_name;
        else if (ev.container !== undefined)
            onWindow(ev);
        else if (ev.pango_markup !== undefined)
            root.mode = ev.change;
    }

    Process {
        id: events
        running: true
        command: ["swaymsg", "-m", "-r", "-t", "subscribe", "[\"window\", \"mode\", \"input\"]"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    root.onEvent(line);
                } catch (e) {}
            }
        }
        onExited: retry.start() // qmllint disable signal-handler-parameters
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: events.running = true
    }

    function screenFor(monitor) {
        if (!monitor)
            return null;
        for (const s of Quickshell.screens) {
            if (I3.monitorFor(s) === monitor || s.name === monitor.name)
                return s;
        }
        return null;
    }
}
