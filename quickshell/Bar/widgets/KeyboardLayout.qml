import QtQuick
import Quickshell.Io
import Quickshell.I3
import qs.Commons
import qs.Ui

Pill {
    id: root
    property string layout: ""
    icon: Icons.keyboard
    label: layout
    labelSize: Style.fontSmall
    visible: layout !== ""

    function shortName(name) {
        const n = name.toLowerCase()
        if (n.startsWith("english"))
            return "US"
        if (n.startsWith("ukrain"))
            return "UA"
        if (n.startsWith("russ"))
            return "RU"
        return name.split(" ")[0].slice(0, 2).toUpperCase()
    }

    Process {
        id: proc
        command: ["swaymsg", "-t", "get_inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const inputs = JSON.parse(text)
                    for (const i of inputs) {
                        if (i.type === "keyboard" && i.xkb_active_layout_name) {
                            root.layout = root.shortName(i.xkb_active_layout_name)
                            return
                        }
                    }
                } catch (e) {}
            }
        }
    }

    Connections {
        target: I3
        function onRawEvent(event) {
            if (event.type === "input")
                proc.running = true
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }

    onClicked: Util.execDetached("swaymsg input type:keyboard xkb_switch_layout next")
}
