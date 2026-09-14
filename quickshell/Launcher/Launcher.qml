import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import "AppSearch.js" as Search
import "MenuModel.js" as Model

Scope {
    id: root

    property bool shown: false
    property string query: ""
    property int selected: 0
    // navigation stack: [{ name, title }]
    property var stack: [{ name: "root", title: "" }]
    readonly property string section: stack[stack.length - 1].name
    readonly property bool calcMode: query.startsWith("=")
    property string calcResult: ""
    property bool awake: false

    property string swayConfig: ""
    property string tmuxConfig: ""

    function toggle() { shown ? close() : open() }
    function close() { shown = false }
    function open() {
        reset()
        swayFile.reload()
        tmuxFile.reload()
        shown = true
    }
    function openSection(name) {
        reset()
        if (name && name !== "root")
            stack = [{ name: "root", title: "" }, { name: name, title: name }]
        shown = true
    }
    function reset() {
        query = ""
        selected = 0
        calcResult = ""
        stack = [{ name: "root", title: "" }]
    }

    // ---- rows -------------------------------------------------------------

    function appRows() {
        const out = []
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue
            out.push({ id: e.id, name: e.name, genericName: e.genericName || e.comment || "", keywords: e.keywords || [], icon: e.icon, entry: e })
        }
        return out
    }

    function sectionRows(name) {
        switch (name) {
        case "root": return Model.rootRows(Icons)
        case "apps": return appRows()
        case "system": return Model.systemRows(Icons)
        case "keybinds": return Model.parseSwayBinds(swayConfig, Icons)
        case "tmux": return Model.parseTmuxBinds(tmuxConfig, Icons)
        case "capture": return Model.captureRows(Icons, Util.home())
        case "toggle": return Model.toggleRows(Icons, { awake: awake })
        case "setup": return Model.setupRows(Icons, Util.home())
        case "learn": return Model.learnRows(Icons)
        default: return []
        }
    }

    readonly property var rows: {
        if (calcMode)
            return calcResult ? [{ id: "calc", name: calcResult, genericName: "Enter copies to clipboard", glyph: Icons.calc, copy: calcResult }] : []
        const q = query.trim()
        let base = Search.sortedEntries(sectionRows(section), q).map(r => r.entry)
        if (section === "root" && q)
            base = base.concat(Search.sortedEntries(appRows(), q).map(r => r.entry))
        return base
    }

    onRowsChanged: selected = Math.min(selected, Math.max(0, rows.length - 1))
    onQueryChanged: {
        selected = 0
        if (calcMode)
            calcTimer.restart()
    }

    // ---- actions ----------------------------------------------------------

    function activate(r) {
        if (!r)
            return
        if (r.section) {
            stack = stack.concat([{ name: r.section, title: r.name }])
            query = ""
            selected = 0
            return
        }
        if (r.toggle === "awake") {
            awake = !awake
            return
        }
        close()
        if (r.entry)
            r.entry.execute()
        else if (r.run)
            Util.execDetached(r.run)
        else if (r.sway)
            Util.execArgv(["swaymsg", r.sway])
        else if (r.copy)
            Util.execDetached("printf '%s' " + Util.shellQuote(r.copy) + " | wl-copy")
    }

    function back() {
        if (stack.length > 1) {
            stack = stack.slice(0, -1)
            selected = 0
        } else {
            close()
        }
    }

    // ---- data sources -----------------------------------------------------

    FileView { id: swayFile; path: Util.home() + "/.config/sway/config"; onLoaded: root.swayConfig = text() }
    FileView { id: tmuxFile; path: Util.home() + "/.config/tmux/tmux.conf"; onLoaded: root.tmuxConfig = text() }

    Timer {
        id: calcTimer
        interval: 150
        onTriggered: {
            const expr = root.query.slice(1).trim()
            if (!expr) { root.calcResult = ""; return }
            calc.command = ["qalc", "-t", expr]
            calc.running = true
        }
    }
    Process {
        id: calc
        stdout: StdioCollector { onStreamFinished: root.calcResult = text.trim() }
    }

    Process {
        id: inhibit
        command: ["systemd-inhibit", "--what=idle", "--who=quickshell", "--why=Stay awake", "sleep", "infinity"]
        running: root.awake
    }

    // ---- window -----------------------------------------------------------

    PanelWindow {
        id: win
        visible: root.shown
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Color.scrim
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.18)
            width: Style.cardWidth
            height: Math.min(Style.cardMaxHeight, header.height + list.contentHeight + Style.cardPadding * 2 + 8)
            radius: Style.cardRadius
            color: Color.cardBg
            border.width: 1
            border.color: Color.cardBorder

            MouseArea { anchors.fill: parent }

            Column {
                anchors.fill: parent
                anchors.margins: Style.cardPadding
                spacing: 8

                Row {
                    id: header
                    width: parent.width
                    height: Style.rowHeight
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.calcMode ? Icons.calc : (root.stack.length > 1 ? Icons.chevronRight : Icons.apps)
                        color: Color.accent
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontTitle
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.stack.length > 1
                        text: root.stack[root.stack.length - 1].title
                        color: Color.muted
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontBody
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.query === "" ? (root.stack.length > 1 ? "Type to filter…" : "Search apps, or =expr to calculate…") : root.query
                        color: root.query === "" ? Color.overlay0 : Color.text
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontTitle
                        elide: Text.ElideLeft
                        width: parent.width - x
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Color.surface1 }

                ListView {
                    id: list
                    width: parent.width
                    height: parent.height - header.height - 9 - parent.spacing * 2
                    clip: true
                    model: root.rows
                    currentIndex: root.selected
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: list.width
                        height: Style.rowHeight
                        radius: Style.radius
                        color: index === root.selected ? Color.rowSelected : (hover.containsMouse ? Util.alpha(Color.surface1, 0.5) : "transparent")

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Item {
                                width: 20
                                height: parent.height
                                readonly property string iconPath: parent.parent.modelData.icon ? Quickshell.iconPath(parent.parent.modelData.icon, true) : ""

                                IconImage {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    visible: parent.iconPath !== ""
                                    source: parent.iconPath
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.iconPath === ""
                                    text: parent.parent.parent.modelData.glyph || Icons.apps
                                    color: Color.accent
                                    font.family: Style.fontFamily
                                    font.pixelSize: Style.fontIcon
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.name
                                color: Color.text
                                font.family: Style.fontFamily
                                font.pixelSize: Style.fontBody
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width * 0.55)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.genericName || ""
                                color: Color.muted
                                font.family: Style.fontFamily
                                font.pixelSize: Style.fontSmall
                                elide: Text.ElideRight
                                width: parent.width - x - (check.visible ? check.width + 10 : 0)
                            }

                            Text {
                                id: check
                                anchors.verticalCenter: parent.verticalCenter
                                visible: parent.parent.modelData.checked === true
                                text: "●"
                                color: Color.green
                                font.pixelSize: Style.fontSmall
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.activate(parent.modelData)
                            onPositionChanged: root.selected = parent.index
                        }
                    }
                }
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                event.accepted = true
                switch (event.key) {
                case Qt.Key_Escape:
                    if (root.query !== "") root.query = ""
                    else root.close()
                    return
                case Qt.Key_Up:
                    root.selected = Math.max(0, root.selected - 1); return
                case Qt.Key_Down:
                    root.selected = Math.min(root.rows.length - 1, root.selected + 1); return
                case Qt.Key_PageUp:
                    root.selected = Math.max(0, root.selected - 6); return
                case Qt.Key_PageDown:
                    root.selected = Math.min(root.rows.length - 1, root.selected + 6); return
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.activate(root.rows[root.selected]); return
                case Qt.Key_Right:
                    if (root.rows[root.selected] && root.rows[root.selected].section) root.activate(root.rows[root.selected])
                    return
                case Qt.Key_Left:
                    if (root.query === "") root.back()
                    return
                case Qt.Key_Backspace:
                    if (root.query === "") { root.back(); return }
                    break
                }
                if (Util.editsFilter(event, root.query)) {
                    root.query = Util.editedFilter(event, root.query)
                    return
                }
                if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
                    root.query += event.text
                else
                    event.accepted = false
            }
        }
    }
}
