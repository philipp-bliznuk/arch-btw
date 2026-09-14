import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Pill {
    id: root
    property int usedPct: 0
    icon: Icons.memory
    iconColor: Color.peach
    label: usedPct + "%"

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text()
            const total = parseInt((t.match(/MemTotal:\s+(\d+)/) || [0, 0])[1])
            const avail = parseInt((t.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1])
            if (total > 0)
                root.usedPct = Math.round((total - avail) * 100 / total)
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: meminfo.reload()
    }
}
