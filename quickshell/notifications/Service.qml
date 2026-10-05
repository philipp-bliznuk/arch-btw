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

    // live Notification objects awaiting display
    property var popups: []
    // plain records, newest first
    property var history: []
    readonly property var visible: popups.slice(0, maxVisible)

    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical)
            return 10000;
        if (n.expireTimeout > 0)
            return Math.min(n.expireTimeout, 10000);
        return 5000;
    }

    function remove(n) {
        popups = popups.filter(p => p !== n);
    }

    function dismissAll() {
        for (const n of popups.slice())
            n.dismiss();
        popups = [];
    }

    function clearHistory() {
        history = [];
        save();
    }

    function record(n) {
        if (n.transient)
            return;
        const rec = {
            id: n.id,
            appName: n.appName,
            appIcon: n.appIcon,
            image: n.image,
            summary: n.summary,
            body: n.body,
            urgency: n.urgency,
            time: Date.now()
        };
        history = [rec].concat(history).slice(0, maxHistory);
        save();
    }

    function save() {
        store.setText(JSON.stringify(history));
    }

    function toggleDnd() {
        Toggles.flip("dnd");
    }

    function latest() {
        return popups.length ? popups[popups.length - 1] : null;
    }

    function dismissLatest() {
        const n = latest();
        if (n)
            n.dismiss();
    }

    function actionLatest() {
        const n = latest();
        if (!n)
            return;
        const a = n.actions.find(x => x.identifier === "default") ?? n.actions[0];
        if (a)
            a.invoke();
        if (!n.resident)
            n.dismiss();
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
            root.record(n);
            if (root.dnd && n.urgency !== NotificationUrgency.Critical)
                return;
            n.tracked = true;
            n.closed.connect(() => root.remove(n));
            root.popups = root.popups.concat([n]);
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
            return root.popups.length;
        }

        function dismissLatest(): void {
            root.dismissLatest();
        }

        function actionLatest(): void {
            root.actionLatest();
        }
    }
}
