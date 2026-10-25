import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.core

// org.freedesktop.Notifications daemon.
// Policy: DND suppresses low/normal only; critical always shown.
// Popups: max 4 visible, at most 20 queued; history: last 50 persisted to
// ~/.local/state/qs/notifications.json.
Scope {
    id: root

    readonly property int maxVisible: 4
    readonly property int maxQueued: 20
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
    // reuses ids across generations). Strings are cut: D-Bus allows 128 MiB a
    // message, and the file is parsed on every start.
    function snapshot(n, time) {
        return {
            id: n.id,
            appName: Util.truncate(n.appName, 128),
            appIcon: Util.truncate(n.appIcon, 4096),
            image: Util.truncate(n.image, 4096),
            summary: Util.truncate(n.summary, 512),
            body: Util.truncate(n.body, 4096),
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

    // Hint set by qs-notify: qs-glyph, a Nerd glyph shown when there is no icon.
    // One glyph, modifiers included, is a few UTF-16 units; anything longer is
    // not a glyph and would be laid out across the card.
    function glyph(n) {
        const g = n.hints["qs-glyph"];
        return typeof g === "string" && g.length <= 8 ? g : "";
    }

    function activate(n) {
        const a = n.actions.find(x => x.identifier === "default") ?? n.actions[0];
        if (a)
            a.invoke();
        if (!n.resident)
            n.dismiss();
    }

    // The newest card on screen. Cards past maxVisible wait hidden, so the
    // last appended one is not what the user is looking at.
    function latest() {
        const shown = Math.min(popups.count, maxVisible);
        return shown ? popups.get(shown - 1).notification : null;
    }

    // A sender in a loop would queue without bound, one live Notification
    // and one Card each. Past maxQueued the oldest waiting one expires,
    // critical included (a loop of critical ones is the same loop); it is in
    // the history already.
    function trim() {
        if (popups.count > maxQueued)
            popups.get(maxVisible).notification.expire();
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
            root.trim();
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

        function dismissLatest(): void {
            root.dismissLatest();
        }

        function actionLatest(): void {
            root.actionLatest();
        }
    }
}
