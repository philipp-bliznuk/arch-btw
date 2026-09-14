import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Pill {
    id: root
    property string avail: "…"
    icon: Icons.disk
    iconColor: Color.blue
    label: avail

    Process {
        id: proc
        command: ["sh", "-c", "df -h --output=avail / | tail -1 | tr -d ' '"]
        stdout: StdioCollector {
            onStreamFinished: root.avail = text.trim()
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
