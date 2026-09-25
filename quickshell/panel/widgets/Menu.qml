import QtQuick
import Quickshell
import qs.core
import qs.ui

// Leftmost pill: opens the launcher (dwm-titus logo → control center).
Pill {
    icon: Icons.arch
    iconColor: Color.accent
    onClicked: Quickshell.execDetached([Util.bin("qs-shell"), "-q", "launcher", "toggle"])
}
