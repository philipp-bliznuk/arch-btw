pragma Singleton
import QtQuick
import Quickshell

// One panel popup open at a time (dwm-titus selectPanelPopup).
Singleton {
    id: root
    property string current: ""

    function toggle(id) {
        current = current === id ? "" : id;
    }

    function open(id) {
        current = id;
    }

    function close() {
        current = "";
    }

    function isOpen(id) {
        return current === id;
    }
}
