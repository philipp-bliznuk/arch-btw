pragma Singleton
import QtQuick
import Quickshell

// Session lock state. lock/Locker.qml owns the WlSessionLock and writes these;
// everything that takes exclusive keyboard focus (launcher, popups, polkit)
// reads `locked` because sway 1.12 still lets an exclusive layer surface take
// the keyboard away from the lock surface (fixed upstream after 1.12).
Singleton {
    id: root

    // The shell asked the compositor for a lock. True before the lock surfaces
    // exist and until the password or key is accepted.
    property bool locked: false

    signal lockRequested

    function lock() {
        lockRequested();
    }
}
