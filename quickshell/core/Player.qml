pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// Which MPRIS player the shell talks to. Feishin (navidrome client) wins when
// present, then whatever is playing, then the first player. Browser videos
// therefore never hijack the widget while music is merely paused.
//
// Volume goes through the player's PipeWire output streams, not MPRIS:
// browsers report a private multiplier there (Firefox says 1.0 until first
// set) that matches neither the mixer nor the tab. Callers must keep the
// streams bound with a PwObjectTracker while they read `volume`.
Singleton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var player: {
        const ps = players;
        for (const p of ps)
            if (isPreferred(p))
                return p;
        for (const p of ps)
            if (p.isPlaying)
                return p;
        return ps.length ? ps[0] : null;
    }
    readonly property bool playing: player ? player.isPlaying : false
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string album: player ? (player.trackAlbum || "") : ""
    readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
    readonly property string line: [artist, title].filter(x => x).join(" - ")

    readonly property var streams: player ? Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream && owns(n)) : []
    readonly property bool volumeSupported: streams.length > 0 || (player !== null && player.volumeSupported)
    // PipeWire streams accept gain above unity; MPRIS volume is 0..1.
    readonly property real volumeMax: streams.length > 0 ? 1.5 : 1
    readonly property real volume: {
        const s = streams.find(n => n.audio);
        if (s)
            return s.audio.volume;
        return player && player.volumeSupported ? player.volume : 0;
    }

    function isPreferred(p) {
        const id = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
        return id.includes("feishin");
    }

    function owns(node) {
        const p = node.properties || {};
        const tags = [p["application.process.binary"], p["application.name"], node.name].filter(x => x).map(x => String(x).toLowerCase());
        const ids = [player.desktopEntry, player.identity].filter(x => x).map(x => x.toLowerCase());
        return tags.some(t => ids.some(i => t.includes(i) || i.includes(t)));
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
