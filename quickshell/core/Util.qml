pragma Singleton
import QtQuick
import Quickshell

// Helpers lifted from omarchy shell (MIT, DHH), trimmed.
QtObject {
    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function alpha(c, opacity) {
        const col = Qt.color(c);
        return Qt.rgba(col.r, col.g, col.b, opacity);
    }

    function shellQuote(v) {
        return "'" + String(v ?? "").replace(/'/g, "'\\''") + "'";
    }


    function editsFilter(event, text) {
        if (!text)
            return false;
        if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))
            return false;
        if (event.key === Qt.Key_U)
            return event.modifiers === Qt.ControlModifier;
        return event.key === Qt.Key_Backspace;
    }

    function editedFilter(event, text) {
        if (event.key === Qt.Key_U)
            return "";
        if (event.modifiers & Qt.ControlModifier)
            return text.replace(/\s+$/, "").replace(/\S+$/, "");
        return text.slice(0, -1);
    }

    function truncate(s, max) {
        s = String(s ?? "");
        return s.length > max ? s.slice(0, max - 1) + "…" : s;
    }

    function humanBytes(bps) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let i = 0;
        let v = bps;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
    }

    function home() {
        return Quickshell.env("HOME");
    }

    readonly property string stateDir: home() + "/.local/state/qs"

    function bin(name) {
        return home() + "/.local/bin/" + name;
    }

    function timeAgo(ms) {
        const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }
}
