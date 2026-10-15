import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.core

// org.freedesktop.Notifications daemon.
// Policy: DND suppresses low/normal only; critical always shown.
// Popups: max 4 visible; history: last 50 persisted to ~/.local/state/qs/notifications.json.
Scope {
    id: root

    readonly property int maxVisible: 4
    readonly property int maxHistory: 50
    readonly property bool dnd: Toggles.has("dnd")

    // live Notification objects awaiting display; a model, so the stack adds
    // and removes single cards instead of rebuilding all of them (a rebuild
    // restarted every countdown)
    readonly property ListModel popups: ListModel {}
    // plain records, newest first
    property var history: []

    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 10000;
        if (n.expireTimeout > 0)
            return Math.min(n.expireTimeout, 10000);
        return 5000;
    }

    function all() {
        const out = [];
        for (let i = 0; i < popups.count; i++)
            out.push(popups.get(i).notification);
        return out;
    }

    function remove(n) {
        const i = all().indexOf(n);
        if (i >= 0)
            popups.remove(i);
    }

    function dismissAll() {
        for (const n of all())
            n.dismiss();
        popups.clear();
    }

    function clearHistory() {
        history = [];
        saveLater.stop();
        save();
    }

    // Coalesces the rewrites a progress-style sender causes with replaces_id.
    Timer {
        id: saveLater
        interval: 300
        onTriggered: root.save()
    }

    function record(n, time) {
        if (n.transient)
            return;
        const rec = snapshot(n, time);
        const i = history.findIndex(r => r.id === n.id && r.time === time);
        history = i < 0 ? [rec].concat(history).slice(0, maxHistory) : history.map((r, k) => k === i ? rec : r);
        saveLater.restart();
    }

    // History keeps the content last shown: a replaces_id update rewrites the
    // live object, so the record written at arrival is re-snapshotted. The
    // record's time is the arrival time and doubles as its key (the server
    // reuses ids across generations).
    function snapshot(n, time) {
        return {
            id: n.id,
            appName: n.appName,
            appIcon: n.appIcon,
            image: n.image,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            time
        };
    }

    readonly property var updateSignals: ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "urgencyChanged"]

    function watch(n, time) {
        for (const s of updateSignals)
            n[s].connect(() => root.record(n, time));
    }

    function save() {
        store.setText(JSON.stringify(history));
    }

    // Hints set by qs-notify: qs-glyph (Nerd glyph shown when there is no
    // icon) and qs-exec-argv (JSON argv run on click when the sender has no
    // default action; busctl callers cannot answer ActionInvoked). Any bus
    // client can send hints, so qs-exec-argv counts only with qs-token, the
    // random per-boot secret this process writes 0600 under $XDG_RUNTIME_DIR.
    property string token: ""

    function glyph(n) {
        const g = n.hints["qs-glyph"];
        return typeof g === "string" ? g : "";
    }

    function execArgv(n) {
        if (token === "" || n.hints["qs-token"] !== token)
            return null;
        try {
            const argv = JSON.parse(n.hints["qs-exec-argv"]);
            return Array.isArray(argv) && argv.length && argv.every(a => typeof a === "string") ? argv : null;
        } catch (e) {
            return null;
        }
    }

    Process {
        running: true
        command: ["bash", "-c", "umask 077; f=\"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qs/notify-token\"; mkdir -p \"${f%/*}\"; [ -s \"$f\" ] || od -An -N16 -tx1 /dev/urandom | tr -d ' \\n' >\"$f\"; cat \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: root.token = text.trim()
        }
    }

    function activate(n) {
        const a = n.actions.find(x => x.identifier === "default") ?? n.actions[0];
        const argv = a ? null : execArgv(n);
        if (a)
            a.invoke();
        else if (argv)
            Commands.run({ argv });
        if (!n.resident)
            n.dismiss();
    }

    function toggleDnd() {
        Toggles.flip("dnd");
    }

    function latest() {
        return popups.count ? popups.get(popups.count - 1).notification : null;
    }

    function dismissLatest() {
        const n = latest();
        if (n)
            n.dismiss();
    }

    function actionLatest() {
        const n = latest();
        if (n)
            activate(n);
    }

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            const time = Date.now();
            root.record(n, time);
            if (root.dnd && n.urgency !== NotificationUrgency.Critical)
                return;
            n.tracked = true;
            root.watch(n, time);
            n.closed.connect(() => root.remove(n));
            root.popups.append({ notification: n });
        }
    }

    FileView {
        id: store
        path: Util.stateDir + "/notifications.json"
        atomicWrites: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (Array.isArray(parsed))
                    root.history = parsed;
            } catch (e) {
                console.warn("notifications: bad history file, ignoring");
            }
        }
    }

    Stack {
        service: root
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            root.toggleDnd();
        }

        function clear(): void {
            root.dismissAll();
        }

        function clearHistory(): void {
            root.clearHistory();
        }

        function count(): int {
            return root.popups.count;
        }

        function dismissLatest(): void {
            root.dismissLatest();
        }

        function actionLatest(): void {
            root.actionLatest();
        }
    }
}
