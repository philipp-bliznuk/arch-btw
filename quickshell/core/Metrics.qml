pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// System metrics sampled every 5 s, shared by panel/widgets/{Cpu,Gpu,Ram,Disk,NetRate}.
// GPU, best source first: /usr/local/bin/qs-gpu-busy (i915 PMU render busy,
// what btop shows; post-install.sh step gpu_helper) → AMD gpu_busy_percent →
// i915 rc6 residency (counts video decode too, so it reads high).
Singleton {
    id: root

    property int cpu: 0
    property int mem: 0
    property string memUsed: ""
    property string disk: "…"
    property int gpu: 0
    property int gpuVideo: 0
    property int gpuMhz: 0
    property string gpuSource: "rc6"
    property real prevRc6: -1
    property real prevRc6Time: 0
    property string up: "0 B/s"
    property string down: "0 B/s"

    property real prevIdle: -1
    property real prevTotal: -1
    property real prevRx: -1
    property real prevTx: -1
    property real prevTime: 0

    FileView {
        id: stat
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = line[3] + line[4];
            const total = line.reduce((a, b) => a + b, 0);
            if (root.prevTotal >= 0) {
                const dt = total - root.prevTotal;
                if (dt > 0)
                    root.cpu = Math.round((dt - (idle - root.prevIdle)) * 100 / dt);
            }
            root.prevIdle = idle;
            root.prevTotal = total;
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const t = text();
            const total = parseInt((t.match(/MemTotal:\s+(\d+)/) || [0, 0])[1]);
            const avail = parseInt((t.match(/MemAvailable:\s+(\d+)/) || [0, 0])[1]);
            if (total > 0) {
                root.mem = Math.round((total - avail) * 100 / total);
                root.memUsed = ((total - avail) / 1048576).toFixed(1) + " / " + (total / 1048576).toFixed(1) + " GiB";
            }
        }
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        onLoaded: {
            let rx = 0, tx = 0;
            for (const line of text().split("\n").slice(2)) {
                const m = line.trim().match(/^(\S+):\s*(.*)$/);
                if (!m || m[1] === "lo")
                    continue;
                const f = m[2].trim().split(/\s+/).map(Number);
                rx += f[0];
                tx += f[8];
            }
            const now = Date.now() / 1000;
            if (root.prevRx >= 0 && now > root.prevTime) {
                const dt = now - root.prevTime;
                root.down = Util.humanBytes((rx - root.prevRx) / dt);
                root.up = Util.humanBytes((tx - root.prevTx) / dt);
            }
            root.prevRx = rx;
            root.prevTx = tx;
            root.prevTime = now;
        }
    }

    Process {
        id: gpuPmu
        command: ["/usr/local/bin/qs-gpu-busy", "5"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const f = line.trim().split(/\s+/);
                root.gpuSource = "pmu";
                root.gpu = parseInt(f[0]) || 0;
                root.gpuVideo = parseInt(f[1]) || 0;
            }
        }
    }

    Process {
        id: gpuProbe
        command: ["sh", "-c", 'for d in /sys/class/drm/card[0-9]; do if [ -r "$d/device/gpu_busy_percent" ]; then echo "busy $(cat "$d/device/gpu_busy_percent")"; exit 0; fi; done; for d in /sys/class/drm/card[0-9]; do if [ -r "$d/gt/gt0/rc6_residency_ms" ]; then echo "rc6 $(cat "$d/gt/gt0/rc6_residency_ms") $(cat "$d/gt_act_freq_mhz")"; exit 0; fi; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/);
                if (f[0] === "busy") {
                    root.gpuSource = "amd";
                    root.gpu = parseInt(f[1]) || 0;
                    return;
                }
                if (f[0] !== "rc6")
                    return;
                const rc6 = parseFloat(f[1]);
                const now = Date.now();
                root.gpuMhz = parseInt(f[2]) || 0;
                if (root.gpuSource !== "pmu" && root.prevRc6 >= 0 && now > root.prevRc6Time) {
                    const sleeping = (rc6 - root.prevRc6) / (now - root.prevRc6Time);
                    root.gpu = Math.round(Util.clamp(1 - sleeping, 0, 1) * 100);
                }
                root.prevRc6 = rc6;
                root.prevRc6Time = now;
            }
        }
    }

    Process {
        id: df
        command: ["sh", "-c", "df -h --output=avail / | tail -1 | tr -d ' '"]
        stdout: StdioCollector {
            onStreamFinished: root.disk = text.trim()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
            gpuProbe.running = true;
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }
}
