pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reboot-required detection, event-driven:
//   /run/reboot-required - written by the pacman hook (post-install.sh),
//                          watched for creation/changes; tmpfs, so a reboot clears it
//   kernel               - /usr/lib/modules/$(uname -r) missing at startup
//                          (upgrade happened before the shell started)
// Notifies once per boot; Indicators + launcher show it until reboot.
Singleton {
    id: root

    property var flagged: []
    property var kernel: []
    readonly property var reasons: {
        const seen = {};
        return kernel.concat(flagged).filter(r => r && !seen[r] && (seen[r] = true));
    }
    readonly property bool rebootRequired: reasons.length > 0
    readonly property string summary: reasons.join(", ")
    property bool notified: false

    function refresh() {
        flag.reload();
        probe.running = true;
    }

    FileView {
        id: flag
        path: "/run/reboot-required"
        watchChanges: true
        printErrors: false
        onLoaded: root.flagged = text().split(/\s+/)
        onLoadFailed: root.flagged = [] // qmllint disable signal-handler-parameters
        onFileChanged: reload()
    }

    Process {
        id: probe
        running: true
        command: ["sh", "-c", '[ -d "/usr/lib/modules/$(uname -r)" ] || echo kernel']
        stdout: StdioCollector {
            onStreamFinished: root.kernel = text.trim() ? ["kernel"] : []
        }
    }

    onRebootRequiredChanged: {
        if (!rebootRequired || notified)
            return;
        notified = true;
        Commands.run({
            argv: [Util.bin("qs-notify"), "-i", "system-reboot", "Reboot required", summary]
        });
    }
}
