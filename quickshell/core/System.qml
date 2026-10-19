pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reboot-required detection, event-driven: /run/reboot-required is written by
// the pacman hook (post-install.sh step pacman_hooks) and watched for
// creation/changes; tmpfs, so a reboot clears it. kernel-modules-hook keeps
// the running kernel's modules through an upgrade, so their absence is no
// signal here. Indicators + launcher show it until reboot; no notification
// (too easy to miss).
Singleton {
    id: root

    property var flagged: []
    readonly property var reasons: {
        const seen = {};
        return flagged.filter(r => r && !seen[r] && (seen[r] = true));
    }
    readonly property bool rebootRequired: reasons.length > 0
    readonly property string summary: reasons.join(", ")

    FileView {
        id: flag
        path: "/run/reboot-required"
        watchChanges: true
        printErrors: false
        onLoaded: root.flagged = text().split(/\s+/)
        onLoadFailed: root.flagged = [] // qmllint disable signal-handler-parameters
        onFileChanged: reload()
    }
}
