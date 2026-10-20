pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Package state the pacman hooks (post-install.sh step pacman_hooks) leave
// behind, watched for creation/changes, never polled.
//
// Reboot required: /run/reboot-required; tmpfs, so a reboot clears it.
// kernel-modules-hook keeps the running kernel's modules through an upgrade,
// so their absence is no signal here. Indicators + launcher show it until
// reboot; no notification (too easy to miss).
//
// pacnew: /var/lib/pacnew-pending lists the .pacnew/.pacsave files pacdiff -o
// found after a transaction that touched /etc. Not /run: the files outlive a
// reboot. qs-pkg pacdiff rewrites it after a merge session.
Singleton {
    id: root

    property var flagged: []
    readonly property var reasons: {
        const seen = {};
        return flagged.filter(r => r && !seen[r] && (seen[r] = true));
    }
    readonly property bool rebootRequired: reasons.length > 0
    readonly property string summary: reasons.join(", ")

    property var pacnew: []

    FileView {
        id: flag
        path: "/run/reboot-required"
        watchChanges: true
        printErrors: false
        onLoaded: root.flagged = text().split(/\s+/)
        onLoadFailed: root.flagged = [] // qmllint disable signal-handler-parameters
        onFileChanged: reload()
    }

    FileView {
        id: pacnewFlag
        path: "/var/lib/pacnew-pending"
        watchChanges: true
        printErrors: false
        onLoaded: root.pacnew = text().split("\n").filter(l => l)
        onLoadFailed: root.pacnew = [] // qmllint disable signal-handler-parameters
        onFileChanged: reload()
    }
}
