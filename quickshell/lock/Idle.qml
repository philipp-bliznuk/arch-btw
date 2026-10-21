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
// Lid policy, fed by sway's bindswitch through the `lid` IPC target (logind
// ignores the switch, step lid): closing pauses every player, locks and arms
// a lidSuspend timer; opening or unlocking (docked, working on the external
// display) disarms it. A Qt timer is fine here: it freezes across a sleep
// from another cause and its remainder only fires while still locked. The
// awake toggle holds the sleep back, same as it holds the ladder.
Scope {
    id: root

    readonly property int screensaverAfter: Settings.get("idleScreensaver")
    readonly property int lockAfter: Settings.get("idleLock")
    readonly property int suspendAfter: Settings.get("idleSuspend")
    readonly property int lidSuspendAfter: Settings.get("lidSuspend")

    function screensaver(on: bool) {
        Quickshell.execDetached([Util.bin("qs-screensaver"), on ? "start" : "stop"]);
    }

    function suspend() {
        Quickshell.execDetached(["systemctl", "suspend-then-hibernate"]);
    }

    function lidClosed() {
        const paused = Player.pauseAll();
        const lock = Lock.locked ? "already locked" : "locking";
        console.info(`lid: closed, ${paused} player(s) paused, ${lock}`);
        Lock.lock();
        if (root.lidSuspendAfter > 0)
            lidTimer.restart();
    }

    function lidOpened() {
        console.info("lid: opened" + (lidTimer.running ? ", sleep disarmed" : ""));
        lidTimer.stop();
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

    Timer {
        id: lidTimer
        interval: root.lidSuspendAfter * 1000
        onTriggered: {
            if (!Lock.locked || Toggles.has("awake")) {
                console.info("lid: sleep skipped, " + (Lock.locked ? "awake toggle" : "unlocked"));
                return;
            }
            console.info("lid: sleep");
            root.suspend();
        }
    }

    Connections {
        target: Lock

        function onLockedChanged() {
            if (!Lock.locked && lidTimer.running) {
                console.info("lid: unlocked, sleep disarmed");
                lidTimer.stop();
            }
        }
    }
}
