pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reboot-required detection (CachyOS style). Two sources, polled every minute:
//   kernel    — /usr/lib/modules/$(uname -r) is removed by a kernel upgrade
//   /run/reboot-required — written by the pacman hook (post-install.sh)
// Notifies once per boot; Indicators + launcher show it until reboot.
Singleton {
    id: root

    property var reasons: []
    readonly property bool rebootRequired: reasons.length > 0
    readonly property string summary: reasons.join(", ")
    property bool notified: false

    function refresh() {
        probe.running = true;
    }

    Process {
        id: probe
        command: ["sh", "-c", '[ -d "/usr/lib/modules/$(uname -r)" ] || echo kernel; [ -r /run/reboot-required ] && cat /run/reboot-required; exit 0']
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const next = [];
                for (const line of text.split(/\s+/)) {
                    if (line && !seen[line]) {
                        seen[line] = true;
                        next.push(line);
                    }
                }
                root.reasons = next;
            }
        }
    }

    onRebootRequiredChanged: {
        if (!rebootRequired || notified)
            return;
        notified = true;
        Quickshell.execDetached([Util.bin("qs-notify"), "-i", "system-reboot", "Reboot required", summary]);
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
