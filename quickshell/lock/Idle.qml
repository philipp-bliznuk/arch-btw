import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Idle ladder on ext-idle-notify (compositor-timed, so suspend never leaves a
// stale remainder the way a Qt timer would): screensaver, lock, suspend.
// Thresholds are Settings keys in seconds; 0 disables a rung. Monitors
// respect idle inhibitors, so the awake toggle (IdleInhibitor on the
// wallpaper window) and players holding inhibit-idle pause the whole ladder.
// A disabled monitor reads as not idle, so locking stops the screensaver.
//
// The lid is logind's (post-install step lid): the sleep it starts reaches
// the shell through swayidle's before-sleep (shell.qml, `lock sleep`).
Scope {
    id: root

    readonly property int screensaverAfter: Settings.get("idleScreensaver")
    readonly property int lockAfter: Settings.get("idleLock")
    readonly property int suspendAfter: Settings.get("idleSuspend")

    function screensaver(on: bool) {
        Quickshell.execDetached([Util.bin("qs-screensaver"), on ? "start" : "stop"]);
    }

    function suspend() {
        Quickshell.execDetached(["systemctl", "suspend-then-hibernate"]);
    }

    IdleMonitor {
        enabled: !Lock.locked && root.screensaverAfter > 0
        timeout: root.screensaverAfter
        onIsIdleChanged: root.screensaver(isIdle)
    }

    IdleMonitor {
        enabled: !Lock.locked && root.lockAfter > 0
        timeout: root.lockAfter
        onIsIdleChanged: {
            if (isIdle)
                Lock.lock();
        }
    }

    IdleMonitor {
        enabled: root.suspendAfter > 0
        timeout: root.suspendAfter
        onIsIdleChanged: {
            if (isIdle)
                root.suspend();
        }
    }
}
