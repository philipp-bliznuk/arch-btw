import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Pill {
    id: root
    property int pct: 0
    property real prevIdle: -1
    property real prevTotal: -1
    icon: Icons.cpu
    iconColor: Color.green
    label: pct + "%"

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
            const idle = line[3] + line[4]
            const total = line.reduce((a, b) => a + b, 0)
            if (root.prevTotal >= 0) {
                const dt = total - root.prevTotal
                const di = idle - root.prevIdle
                if (dt > 0)
                    root.pct = Math.round((dt - di) * 100 / dt)
            }
            root.prevIdle = idle
            root.prevTotal = total
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: stat.reload()
    }
}
