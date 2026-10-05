pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function clamp(value, min, max) {
        return Math.max(min, Math.min(max, value));
    }

    function truncate(s, max) {
        s = String(s ?? "");
        return s.length > max ? s.slice(0, max - 1) + "…" : s;
    }

    // Rates floor at KiB/s: idle reads "0.0 KiB/s", the number stays 2-3
    // characters and the unit keeps one width, so bar labels do not shift.
    function humanBytes(bps) {
        const units = ["KiB/s", "MiB/s", "GiB/s"];
        let i = 0;
        let v = (bps || 0) / 1024;
        while (v >= 1024 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + units[i];
    }

    function humanSize(bytes, units = ["B", "KiB", "MiB", "GiB"]) {
        let i = 0;
        let v = bytes || 0;
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
