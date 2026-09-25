import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.core
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

    // notifications/Service instance, for the history section
    required property var notifications
    required property var clipboard

    property string swayConfig: ""
    property string tmuxConfig: ""
    property var caps: ({ canSuspend: true, canHibernate: true })
    property var wallpapers: []
    property string wallpaper: ""
    property int updates: 0
    property var pending: null
    // select mode: external picker (bin/qs-select). { prompt, rows, outfile }
    property var select: null

    Component.onCompleted: Model.setBin(Util.home() + "/.local/bin/")

    function toggle() { shown ? close() : open() }
    function close() { shown = false }
    function open() {
        reset()
        swayFile.reload()
        tmuxFile.reload()
        capsProbe.running = true
        shown = true
    }
    function openSelect(prompt, tsv, outfile) {
        reset()
        const rows = []
        const lines = tsv.split("\n").filter(l => l.trim())
        for (let i = 0; i < lines.length; i++) {
            const f = lines[i].split("\t")
            rows.push({ id: "sel-" + i, name: f[0], genericName: f[1] || "", keywords: [], glyph: f[2] || Icons.chevronRight, selectValue: f[0] })
        }
        select = { prompt: prompt, rows: rows, outfile: outfile }
        stack = [{ name: "select", title: prompt }]
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
        pending = null
        select = null
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
        case "root": return Model.rootRows(Icons, updates)
        case "apps": return appRows()
        case "system": return Model.systemRows(Icons, caps)
        case "confirm": return pending ? Model.confirmRows(Icons, pending) : []
        case "keybinds": return Model.parseSwayBinds(swayConfig, Icons)
        case "tmux": return Model.parseTmuxBinds(tmuxConfig, Icons)
        case "capture": return Model.captureRows(Icons)
        case "toggle": return Model.toggleRows(Icons, Toggles.active)
        case "setup": return Model.setupRows(Icons, Util.home())
        case "wallpaper": return Model.wallpaperRows(Icons, wallpapers, wallpaper)
        case "select": return select ? select.rows : []
        case "clipboard": return Model.clipboardRows(Icons, clipboard.entries, Util)
        case "learn": return Model.learnRows(Icons)
        case "notifications": return Model.notificationRows(Icons, notifications.history, Util)
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

    function push(name, title) {
        stack = stack.concat([{ name: name, title: title }])
        query = ""
        selected = 0
    }

    function activate(r) {
        if (!r || r.disabled)
            return
        if (r.section) {
            if (r.section === "wallpaper")
                wallpaperList.running = true
            push(r.section, r.name)
            return
        }
        if (r.confirm) {
            pending = r
            push("confirm", r.name + "?")
            return
        }
        if (r.selectValue !== undefined) {
            const out = select.outfile
            close()
            Quickshell.execDetached(["bash", "-c", 'printf %s "$1" > "$2"', "bash", r.selectValue, out])
            return
        }
        if (r.popup) {
            close()
            Popups.open(r.popup)
            return
        }
        if (r.clip) {
            close()
            clipboard.copy(r.clip)
            return
        }
        if (r.toggle) {
            Toggles.flip(r.toggle)
            return
        }
        if (r.action) {
            runAction(r.action)
            return
        }
        close()
        Commands.run(r)
    }

    function runAction(name) {
        switch (name) {
        case "notifications-clear":
            notifications.clearHistory()
            break
        case "notifications-dismiss":
            close()
            break
        case "back":
            back()
            break
        case "clipboard-clear":
            clipboard.clear()
            break
        }
    }

    function back() {
        if (select) {
            close()
            return
        }
        if (stack.length > 1) {
            stack = stack.slice(0, -1)
            selected = 0
        } else {
            close()
        }
    }

    onShownChanged: {
        if (!shown && select)
            Quickshell.execDetached(["bash", "-c", '[ -s "$1" ] || : > "$1"', "bash", select.outfile])
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
        id: capsProbe
        command: ["bash", "-c", 'printf "%s %s" "$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanSuspend 2>/dev/null)" "$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>/dev/null)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/)
                root.caps = { canSuspend: f.length < 2 || f[1] === '"yes"', canHibernate: f.length < 4 || f[3] === '"yes"' }
            }
        }
    }

    Process {
        id: wallpaperList
        command: ["bash", "-c", Util.bin("qs-wallpaper") + " list; printf '\\n---\\n'; " + Util.bin("qs-wallpaper") + " current"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n---\n")
                root.wallpapers = parts[0].split("\n").filter(l => l)
                root.wallpaper = (parts[1] || "").trim()
            }
        }
    }

    // checkupdates (pacman-contrib): every 6h + on load
    Process {
        id: updatesProbe
        command: ["bash", "-c", "checkupdates 2>/dev/null | wc -l"]
        stdout: StdioCollector { onStreamFinished: root.updates = parseInt(text.trim()) || 0 }
    }
    Timer {
        interval: 6 * 3600 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: updatesProbe.running = true
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
                        text: root.query === "" ? (root.select ? root.select.prompt : (root.stack.length > 1 ? "Type to filter…" : "Search apps, or =expr to calculate…")) : root.query
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

                    // qmllint disable unqualified
                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        required property int index
                        width: list.width
                        height: Style.rowHeight
                        radius: Style.radius
                        color: index === root.selected ? Color.rowSelected : (hover.containsMouse ? Util.alpha(Color.surface1, 0.5) : "transparent")
                        opacity: modelData.disabled ? 0.45 : 1

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Item {
                                width: 20
                                height: parent.height
                                readonly property string iconPath: entry.modelData.thumb ? entry.modelData.thumb : (entry.modelData.icon ? Quickshell.iconPath(entry.modelData.icon, true) : "")

                                IconImage {
                                    anchors.centerIn: parent
                                    width: entry.modelData.thumb ? 28 : 18
                                    height: 18
                                    visible: parent.iconPath !== ""
                                    source: parent.iconPath
                                    asynchronous: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: parent.iconPath === ""
                                    text: entry.modelData.glyph || Icons.apps
                                    color: Color.accent
                                    font.family: Style.fontFamily
                                    font.pixelSize: Style.fontIcon
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData.name
                                color: Color.text
                                font.family: Style.fontFamily
                                font.pixelSize: Style.fontBody
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width * 0.55)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.modelData.genericName || ""
                                color: Color.muted
                                font.family: Style.fontFamily
                                font.pixelSize: Style.fontSmall
                                elide: Text.ElideRight
                                width: parent.width - x - (check.visible ? check.width + 10 : 0)
                            }

                            Text {
                                id: check
                                anchors.verticalCenter: parent.verticalCenter
                                visible: entry.modelData.checked === true
                                text: "●"
                                color: Color.green
                                font.pixelSize: Style.fontSmall
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.activate(entry.modelData)
                            onPositionChanged: root.selected = entry.index
                        }
                    }
                    // qmllint enable unqualified
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
                case Qt.Key_Delete:
                    if (root.rows[root.selected] && root.rows[root.selected].clip) root.clipboard.remove(root.rows[root.selected].clip)
                    return
                case Qt.Key_Home:
                    root.selected = 0; return
                case Qt.Key_End:
                    root.selected = Math.max(0, root.rows.length - 1); return
                case Qt.Key_P:
                    if (event.modifiers & Qt.ControlModifier) { root.selected = Math.max(0, root.selected - 1); return }
                    break
                case Qt.Key_N:
                    if (event.modifiers & Qt.ControlModifier) { root.selected = Math.min(root.rows.length - 1, root.selected + 1); return }
                    break
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
