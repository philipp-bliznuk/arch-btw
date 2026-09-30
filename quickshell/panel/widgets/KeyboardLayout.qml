import QtQuick
import Quickshell.Io
import qs.core
import qs.ui

// Active xkb layout; click cycles. Quickshell's I3 module only subscribes to
// workspace/output events, so we keep our own `swaymsg -m` subscription for
// `input` — layout changes show up instantly instead of on a poll.
Segment {
    id: root
    property string layout: ""
    property string fullName: ""
    icon: Icons.keyboard
    label: layout
    visible: layout !== ""
    tooltip: fullName + " · click to switch"

    function shortName(name) {
        const n = name.toLowerCase();
        if (n.startsWith("english"))
            return "US";
        if (n.startsWith("ukrain"))
            return "UA";
        if (n.startsWith("russ"))
            return "RU";
        return name.split(" ")[0].slice(0, 2).toUpperCase();
    }

    function apply(name) {
        if (!name)
            return;
        fullName = name;
        layout = shortName(name);
    }

    Process {
        running: true
        command: ["swaymsg", "-t", "get_inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kb = JSON.parse(text).find(i => i.type === "keyboard" && i.xkb_active_layout_name);
                    if (kb)
                        root.apply(kb.xkb_active_layout_name);
                } catch (e) {}
            }
        }
    }

    Process {
        id: events
        running: true
        command: ["swaymsg", "-m", "-r", "-t", "subscribe", "[\"input\"]"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const ev = JSON.parse(line);
                    if (ev.change === "xkb_layout")
                        root.apply(ev.input.xkb_active_layout_name);
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

    onClicked: Commands.run({
        sway: "input type:keyboard xkb_switch_layout next"
    })
}
