pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Which MPRIS player the shell talks to. Feishin (navidrome client) wins when
// present, then a playing player that owns a live PipeWire stream, then any
// playing player, then one with track metadata, then the first. playerctld's
// proxy is skipped: it mirrors another player and would show up twice. Browser
// videos therefore never hijack the widget while music is merely paused.
//
// Volume goes through the player's PipeWire output streams, not MPRIS:
// browsers report a private multiplier there (Firefox says 1.0 until first
// set) that matches neither the mixer nor the tab. Every output stream stays
// bound here: PwNode.properties (application name, process binary) is empty
// until the node is bound, and the player-to-stream match reads them.
Singleton {
    id: root

    readonly property var players: Mpris.players.values.filter(p => !isProxy(p))
    readonly property var outStreams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
    readonly property var player: {
        const ps = players;
        return ps.find(isPreferred)
            ?? ps.find(p => p.isPlaying && streamsOf(p).length > 0)
            ?? ps.find(p => p.isPlaying)
            ?? ps.find(hasTrack)
            ?? (ps.length ? ps[0] : null);
    }
    readonly property bool playing: player ? player.isPlaying : false
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string album: player ? (player.trackAlbum || "") : ""
    readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
    readonly property string line: [artist, title].filter(x => x).join(" - ")
    // Changes when a transport command took effect; the OSD waits for it.
    readonly property string signature: [playing, title, artist, album].join("\u001f")

    readonly property var streams: player ? streamsOf(player) : []
    readonly property bool volumeSupported: streams.length > 0 || (player !== null && player.volumeSupported)
    // PipeWire streams accept gain above unity; MPRIS volume is 0..1.
    readonly property real volumeMax: streams.length > 0 ? 1.5 : 1
    readonly property real volume: {
        const s = streams.find(n => n.audio);
        if (s)
            return s.audio.volume;
        return player && player.volumeSupported ? player.volume : 0;
    }

    PwObjectTracker {
        objects: root.outStreams
    }

    function isPreferred(p) {
        const id = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
        return id.includes("feishin");
    }

    function isProxy(p) {
        return (p.dbusName || "").includes("playerctld") || p.desktopEntry === "playerctld";
    }

    function hasTrack(p) {
        return !!(p.trackTitle || p.trackArtist || p.trackAlbum || p.trackArtUrl);
    }

    function key(s) {
        return String(s).toLowerCase().replace(/^pipewire alsa \[/, "").replace(/^alsa playback \[/, "").replace(/\]$/, "").replace(/[^a-z0-9]+/g, "");
    }

    // Identity and desktop entry against the stream's binary, both sides
    // reduced to alphanumerics; app name and node name only when the stream
    // carries no binary (Electron apps all report "Chromium" as their name,
    // so a Chromium player would otherwise claim every Electron stream).
    // Not the D-Bus name: LibreWolf registers as "firefox" and would claim
    // Firefox's streams.
    function owns(node, p) {
        const props = node.properties || {};
        const binary = props["application.process.binary"];
        const raw = binary ? [binary] : [props["application.name"], node.name];
        const tags = raw.filter(x => x).map(key).filter(x => x);
        const ids = [p.desktopEntry, p.identity].filter(x => x).map(key).filter(x => x);
        return tags.some(t => ids.some(i => t.includes(i) || i.includes(t)));
    }

    function streamsOf(p) {
        return outStreams.filter(n => owns(n, p));
    }

    function toggle() {
        if (player && player.canTogglePlaying)
            player.togglePlaying();
    }

    function next() {
        if (player && player.canGoNext)
            player.next();
    }

    function previous() {
        if (player && player.canGoPrevious)
            player.previous();
    }

    function setVolume(v) {
        const vol = Util.clamp(v, 0, volumeMax);
        const bound = streams.filter(n => n.audio);
        if (bound.length) {
            for (const n of bound)
                n.audio.volume = vol;
            return;
        }
        if (player && player.volumeSupported)
            player.volume = vol;
    }

    function nudgeVolume(delta) {
        setVolume(volume + delta);
    }
}
