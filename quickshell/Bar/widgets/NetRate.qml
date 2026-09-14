import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Pill {
    id: root
    property real prevRx: -1
    property real prevTx: -1
    property real prevTime: 0
    property string up: "0 B/s"
    property string down: "0 B/s"
    icon: ""

    content: Stacked {
        topText: Icons.arrowUp + " " + root.up
        bottomText: Icons.arrowDown + " " + root.down
        topColor: Color.green
        bottomColor: Color.red
        minWidth: 76
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^(\S+):\s*(.*)$/)
                if (!m || m[1] === "lo")
                    continue
                const f = m[2].trim().split(/\s+/).map(Number)
                rx += f[0]
                tx += f[8]
            }
            const now = Date.now() / 1000
            if (root.prevRx >= 0 && now > root.prevTime) {
                const dt = now - root.prevTime
                root.down = Util.humanBytes((rx - root.prevRx) / dt)
                root.up = Util.humanBytes((tx - root.prevTx) / dt)
            }
            root.prevRx = rx
            root.prevTx = tx
            root.prevTime = now
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: netdev.reload()
    }
}
