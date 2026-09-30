pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Which MPRIS player the shell talks to. Feishin (navidrome client) wins when
// present, then whatever is playing, then the first player. Browser videos
// therefore never hijack the widget while music is merely paused.
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

    function isPreferred(p) {
        const id = ((p.identity || "") + " " + (p.desktopEntry || "")).toLowerCase();
        return id.includes("feishin");
    }

    function fmt(seconds) {
        if (!seconds || seconds < 0 || !isFinite(seconds))
            return "0:00";
        const s = Math.floor(seconds);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const r = s % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(r).padStart(2, "0");
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

    function seek(delta) {
        if (player && player.canSeek)
            player.seek(delta);
    }

    function nudgeVolume(delta) {
        if (player && player.volumeSupported)
            player.volume = Math.max(0, Math.min(1, player.volume + delta));
    }

    function cycleLoop() {
        if (!player || !player.loopSupported)
            return;
        const order = [MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track];
        player.loopState = order[(order.indexOf(player.loopState) + 1) % order.length];
    }

    function toggleShuffle() {
        if (player && player.shuffleSupported)
            player.shuffle = !player.shuffle;
    }
}
