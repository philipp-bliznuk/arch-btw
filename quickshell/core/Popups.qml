pragma Singleton
import QtQuick
import Quickshell

// One panel popup open at a time, on one screen.
// Every panel is instanced per output, so the screen decides which instance
// of a popup actually shows; null means "the focused output". PopupHost
// registers a slot Item per screen that PopupCards reparent into.
Singleton {
    id: root
    property string current: ""
    property var screen: null
    property var hosts: ({})

    function toggle(id, screen) {
        if (current === id)
            close();
        else
            open(id, screen);
    }

    function open(id, screen) {
        root.screen = screen ?? SwayState.focusedScreen;
        current = id;
    }

    function close() {
        current = "";
    }

    // Compare screens by name: ShellScreen objects are recreated on reload.
    function sameScreen(a, b) {
        return !!a && !!b && a.name === b.name;
    }

    function isOpenOn(id, screen) {
        return current === id && (root.screen === null || sameScreen(root.screen, screen));
    }

    function registerHost(screen, slot) {
        const next = Object.assign({}, hosts);
        next[screen.name] = slot;
        hosts = next;
    }

    // Only drop the slot if it is still ours: on replug the new host registers
    // before the old one is destroyed.
    function unregisterHost(screen, slot) {
        if (hosts[screen.name] !== slot)
            return;
        const next = Object.assign({}, hosts);
        delete next[screen.name];
        hosts = next;
    }

    function hostFor(screen) {
        return screen && hosts[screen.name] ? hosts[screen.name] : null;
    }
}
