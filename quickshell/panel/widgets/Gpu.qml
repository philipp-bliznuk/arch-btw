import QtQuick
import qs.core
import qs.ui

// Render busy % (see core/Metrics for sources).
Segment {
    icon: Icons.gpu
    iconColor: Color.mauve
    label: Metrics.gpu + "%"
    tooltip: "GPU render " + Metrics.gpu + "%" + (Metrics.gpuSource === "pmu" ? " · video " + Metrics.gpuVideo + "%" : "") + (Metrics.gpuMhz ? " · " + Metrics.gpuMhz + " MHz" : "") + (Metrics.gpuSource === "rc6" ? " · approx (run post-install.sh --redo gpu_helper)" : "")
    onClicked: Commands.run({
        argv: Commands.term(["btop"])
    })
}
