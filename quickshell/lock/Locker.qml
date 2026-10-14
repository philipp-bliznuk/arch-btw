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
//
// A pending pam_u2f child is never killed: the token keeps the assertion
// it was asked for until its own ~29 s touch timeout and answers "busy"
// meanwhile, so an unlock by password leaves the child waiting (a lock
// within that window reuses it, a touch then unlocks at once) and failures
// only slow the retries down, never stop them.
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
    property int u2fAttempts: 0
    property double u2fStartedAt: 0
    // Seconds of idle before the outputs go dark while locked; 0 keeps them on.
    readonly property int blankAfter: Settings.get("lockBlank")
    // The key press that lit the outputs again must not reach the field, nor
    // its auto-repeats: a press in the dark outlasts sway's 200 ms repeat
    // delay and would leave a trail of characters.
    readonly property bool waking: wakeGrace.running
    property int wakeKey: 0

    readonly property string hint: {
        if (authenticating)
            return "Checking";
        if (u2fFastFails >= 6)
            return "YubiKey not accepted, still retrying";
        if (u2fFastFails > 0)
            return "YubiKey busy, retrying";
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
        u2fAttempts = 0;
        wakeKey = 0;
        requested = true;
        guard.restart();
        fidoScan.running = true;
        console.info("lock: engaged");
    }

    function unlock(method: string) {
        abortPassword();
        requested = false;
        authenticating = false;
        fidoPresent = false;
        typed = "";
        pending = "";
        flag.setText("");
        console.info("lock: unlocked by " + method);
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
        abortPassword();
        requested = false;
        flag.setText("");
    }

    // Only the password context is ever aborted: a killed pam_u2f child
    // leaves the token busy with the assertion it was asked for.
    function abortPassword() {
        if (password.active)
            password.abort();
    }

    function outputs(on: bool) {
        Quickshell.execDetached(["swaymsg", "-q", "output * power " + (on ? "on" : "off")]);
    }

    // Dark outputs drop whatever was typed; the key press that lights them
    // again is swallowed by the surfaces while `waking`.
    function blank(off: bool) {
        outputs(!off);
        if (off)
            typed = "";
        else
            wakeGrace.restart();
    }

    // Surfaces ask before handing a key to the field: the wake key is dropped,
    // and so are its auto-repeats until it is released for real (Qt emits a
    // synthetic release before every repeated press).
    function swallows(event: var): bool {
        if (event.isAutoRepeat)
            return event.key === wakeKey;
        if (!waking)
            return false;
        wakeKey = event.key;
        return true;
    }

    function released(event: var) {
        if (!event.isAutoRepeat && event.key === wakeKey)
            wakeKey = 0;
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
        console.info("lock: password rejected");
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
        if (!u2fPam.loaded)
            return;
        u2fStartedAt = Date.now();
        u2fAttempts += 1;
        console.info("lock: u2f attempt " + u2fAttempts);
        if (!u2f.start())
            u2fEnded(PamResult.Error);
    }

    // A fast failure means the token answered without waiting for a touch:
    // busy with an earlier assertion, not yet readable (uaccess ACL), or a
    // token that is not enrolled. Retries slow down to 5 s but never stop.
    function u2fEnded(result: int) {
        const elapsed = Date.now() - u2fStartedAt;
        const fast = elapsed < 2000;
        u2fFastFails = fast ? u2fFastFails + 1 : 0;
        rearm.interval = Math.min(750 * 2 ** u2fFastFails, 5000);
        console.info("lock: u2f " + (fast ? "failed fast" : "ended") + " (" + result + ") after " + elapsed + " ms, retry in " + rearm.interval + " ms");
        rearm.restart();
    }

    function statusJson(): string {
        return JSON.stringify({
            locked: requested,
            secure: sessionLock.secure,
            fallback: swaylock.running,
            pam: passwordPam.loaded,
            u2f: u2fPam.loaded,
            u2fActive: u2f.active,
            u2fAttempts: u2fAttempts,
            u2fFast: u2fFastFails,
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
                root.unlock("password");
                return;
            }
            root.fail(root.failureText(result));
        }
    }

    // pam_u2f blocks until the key is touched or the token's own ~29 s
    // timeout passes, then fails; start it again while a token is plugged in.
    // Failures double the pause between runs (750 ms, capped at 5 s) and never
    // stop them: a token that answers "busy" (still holding an earlier
    // assertion), one the uaccess ACL has not reached yet or a foreign one all
    // fail within a second. The child is kept across a password unlock, so a
    // completion must check that the lock is still wanted. The USB autosuspend
    // rule from post-install keeps the token awake so its timeout runs.
    PamContext {
        id: u2f
        config: "qs-lock-u2f"
        onCompleted: result => {
            if (!root.requested)
                return;
            if (result === PamResult.Success) {
                root.unlock("yubikey");
                return;
            }
            root.u2fEnded(result);
        }
    }

    Timer {
        id: rearm
        interval: 750
        onTriggered: root.armU2f()
    }

    Timer {
        id: wakeGrace
        interval: 100
    }

    // Outputs off `lockBlank` seconds into idle while locked, on again on
    // activity; the awake toggle and playing media do not keep a locked screen
    // lit. Unlock disables the monitor, which reads as not idle: outputs come
    // back on even after a key touch, which is not compositor activity.
    IdleMonitor {
        enabled: root.blankAfter > 0 && (sessionLock.secure || swaylock.running)
        respectInhibitors: false
        timeout: root.blankAfter
        onIsIdleChanged: root.blank(isIdle)
    }

    // A VT switch destroys every output; the blank monitor's `power off` is
    // stored by sway and applied to the outputs recreated on the way back, so
    // they come back dark. Sway emits `input added` for each device when
    // libinput resumes there; one relight covers the whole burst.
    Connections {
        target: SwayState
        function onInputAdded() {
            if (root.requested || swaylock.running)
                relight.restart();
        }
    }

    Timer {
        id: relight
        interval: 300
        onTriggered: root.outputs(true)
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
