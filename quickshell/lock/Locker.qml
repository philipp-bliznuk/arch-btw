pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.core

// Session lock: ext-session-lock surfaces on every output (Surface.qml),
// password through PAM service qs-lock-password, YubiKey touch through
// qs-lock-u2f while a FIDO token is plugged in (both written by
// post-install.sh step lock_pam; without the password file swaylock runs).
//
// $XDG_RUNTIME_DIR/qs/locked is written before the lock is requested and
// emptied after unlock, so a relaunched shell (crash, reload) locks again
// and takes over the lock sway keeps on its own when the client dies.
// Never bind on sessionLock.locked: unlock() does not emit its change signal.
Scope {
    id: root

    property string wallpaper: ""

    readonly property string flagPath: Quickshell.env("XDG_RUNTIME_DIR") + "/qs/locked"
    property bool requested: false
    readonly property bool secure: sessionLock.secure
    property bool flagSaved: false
    property bool fidoPresent: false
    property bool authenticating: false
    property int failures: 0
    property string typed: ""
    property string pending: ""
    property string status: ""
    property bool statusIsError: false
    property int u2fFastFails: 0
    property double u2fStartedAt: 0

    readonly property string hint: {
        if (authenticating)
            return "Checking";
        if (u2fFastFails >= 3)
            return "YubiKey not accepted, enter password";
        return fidoPresent ? "Touch YubiKey or enter password" : "Enter password";
    }

    function lock(): string {
        if (requested)
            return "already";
        if (!pamReady())
            return fallback();
        // FileView skips a write whose text equals the last one, so the flag
        // carries a fresh value each time; any non-empty content means locked.
        // No flag, no crash recovery: swaylock then.
        flagSaved = false;
        flag.setText(String(Date.now()));
        if (!flagSaved)
            return fallback();
        engage();
        return "ok";
    }

    // FileView preloads in the background even with blockLoading, so `loaded`
    // is stale until a job is awaited; text() forces the synchronous read.
    function pamReady(): bool {
        passwordPam.reload();
        passwordPam.waitForJob();
        u2fPam.reload();
        u2fPam.waitForJob();
        return passwordPam.loaded;
    }

    // swaylock as a child so Lock.locked covers it too (the polkit prompt
    // must not take the keyboard from it either). Reloading the shell while
    // it runs kills it; sway keeps the session locked, $mod+Escape re-locks.
    function fallback(): string {
        flag.setText("");
        swaylock.running = true;
        return "fallback";
    }

    function engage() {
        typed = "";
        pending = "";
        status = "";
        statusIsError = false;
        failures = 0;
        u2fFastFails = 0;
        requested = true;
        guard.restart();
        fidoScan.running = true;
    }

    function unlock() {
        abortAll();
        requested = false;
        authenticating = false;
        fidoPresent = false;
        typed = "";
        pending = "";
        flag.setText("");
    }

    // The compositor never confirmed the lock. After `finished` (another
    // client holds the session lock) the request is void and gets dropped;
    // while the compositor is merely silent, unlocking would be a protocol
    // error (unlock before locked), so keep waiting.
    function giveUp() {
        if (!requested || sessionLock.secure)
            return;
        if (sessionLock.locked) {
            console.warn("lock: compositor has not answered the lock request yet");
            guard.restart();
            return;
        }
        console.warn("lock: another client holds the session lock");
        abortAll();
        requested = false;
        flag.setText("");
    }

    function abortAll() {
        if (password.active)
            password.abort();
        if (u2f.active)
            u2f.abort();
    }

    function outputs(on: bool) {
        Quickshell.execDetached(["swaymsg", "-q", "output * power " + (on ? "on" : "off")]);
    }

    function submit() {
        if (!requested || authenticating || typed.length === 0)
            return;
        pending = typed;
        typed = "";
        authenticating = true;
        status = "";
        statusIsError = false;
        if (!password.start())
            fail("Could not start authentication");
    }

    function fail(text: string) {
        authenticating = false;
        pending = "";
        failures += 1;
        status = text;
        statusIsError = true;
    }

    function failureText(result: int): string {
        if (result === PamResult.MaxTries)
            return "Too many attempts";
        if (result === PamResult.Error)
            return "Authentication error";
        return "Wrong password";
    }

    function armU2f() {
        if (!requested || !sessionLock.secure || !fidoPresent || u2f.active)
            return;
        if (u2fFastFails >= 3 || !u2fPam.loaded)
            return;
        u2fStartedAt = Date.now();
        if (!u2f.start())
            u2fEnded();
    }

    function u2fEnded() {
        u2fFastFails = Date.now() - u2fStartedAt < 2000 ? u2fFastFails + 1 : 0;
        rearm.restart();
    }

    function statusJson(): string {
        return JSON.stringify({
            locked: requested,
            secure: sessionLock.secure,
            fallback: swaylock.running,
            pam: passwordPam.loaded,
            u2f: u2fPam.loaded,
            fido: fidoPresent,
            authenticating: authenticating,
            failures: failures
        });
    }

    onFidoPresentChanged: {
        u2fFastFails = 0;
        armU2f();
    }

    // A flag left by a shell that died while locked: lock again (sway kept
    // the session locked meanwhile), swaylock if the PAM file went missing.
    // Also the path taken on every config reload while locked.
    Component.onCompleted: {
        mkdir.running = true;
        if (flag.text().trim() === "")
            return;
        if (pamReady())
            engage();
        else
            fallback();
    }

    Binding {
        target: Lock
        property: "locked"
        value: root.requested || swaylock.running
    }

    Binding {
        target: Lock
        property: "secure"
        value: sessionLock.secure
    }

    Connections {
        target: Lock

        function onLockRequested() {
            root.lock();
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: root.requested
        onSecureStateChanged: {
            if (!secure)
                return;
            guard.stop();
            root.armU2f();
        }
        // `finished` from the compositor ends up here with locked false.
        onLockStateChanged: {
            if (!locked && root.requested && !secure)
                root.giveUp();
        }

        Surface {
            service: root
        }
    }

    Timer {
        id: guard
        interval: 3000
        onTriggered: root.giveUp()
    }

    // A PAM error emits completed(Error) as well, so one handler each.
    PamContext {
        id: password
        config: "qs-lock-password"
        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            respond(root.pending);
            root.pending = "";
        }
        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }
            root.fail(root.failureText(result));
        }
    }

    // pam_u2f blocks until the key is touched or the token's own timeout
    // passes, then fails; start it again while a token is plugged in. 750 ms
    // between runs keeps a key that fails at once (ACL not yet applied,
    // foreign token) from forking PAM in a loop; three fast failures in a row
    // stop the retries until the token is replugged.
    PamContext {
        id: u2f
        config: "qs-lock-u2f"
        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlock();
                return;
            }
            root.u2fEnded();
        }
    }

    Timer {
        id: rearm
        interval: 750
        onTriggered: root.armU2f()
    }

    // Outputs off 5 s into idle while locked, on again on activity; the awake
    // toggle and playing media do not keep a locked screen lit. Unlock
    // disables the monitor, which reads as not idle: outputs come back on
    // even after a key touch, which is not compositor activity.
    IdleMonitor {
        enabled: sessionLock.secure || swaylock.running
        respectInhibitors: false
        timeout: 5
        onIsIdleChanged: root.outputs(!isIdle)
    }

    Process {
        id: swaylock
        command: ["swaylock"]
    }

    Process {
        id: fidoScan
        command: ["bash", "-c", "for d in /sys/class/hidraw/*; do udevadm info -q property -p \"$d\" 2>/dev/null; done | grep -qx ID_FIDO_TOKEN=1"]
        onExited: code => root.fidoPresent = root.requested && code === 0
    }

    // udev emits after rules ran (uaccess ACL included), so a token seen
    // here is readable. Only runs while locked; stopping it flushes a stray
    // line (SplitParser skips back-to-back newlines), hence the guards.
    Process {
        id: fidoWatch
        running: root.requested
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=hidraw"]
        stdout: SplitParser {
            onRead: fidoRescan.restart()
        }
    }

    Timer {
        id: fidoRescan
        interval: 300
        onTriggered: {
            if (root.requested)
                fidoScan.running = true;
        }
    }

    FileView {
        id: flag
        path: root.flagPath
        blockLoading: true
        blockWrites: true
        printErrors: false
        onSaved: root.flagSaved = true
        onSaveFailed: err => {
            root.flagSaved = false;
            console.warn("lock: could not write " + root.flagPath + ": " + err);
        }
    }

    FileView {
        id: passwordPam
        path: "/etc/pam.d/qs-lock-password"
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: u2fPam
        path: "/etc/pam.d/qs-lock-u2f"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", Quickshell.env("XDG_RUNTIME_DIR") + "/qs"]
    }
}
