pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.ui
import "AppSearch.js" as Search
import "MenuModel.js" as Model
import "Usage.js" as Usage
import "../ui/KeyModel.js" as KeyModel

// Command menu. Rows are data (MenuModel.js); activate()
// dispatches them. Two key modes: insert (field focused, typing filters)
// and normal (vim keys). Index is only built while shown.
Scope {
    id: root

    property bool shown: false
    property string mode: "insert"
    property string query: ""
    property int cursor: 0
    property var stack: [{ name: "root", title: "" }]
    readonly property string section: stack[stack.length - 1].name
    readonly property bool calcMode: query.startsWith("=")
    property string calcResult: ""
    property int chip: 0

    required property var notifications
    required property var clipboard

    property string swayConfig: ""
    property string tmuxConfig: ""
    property var caps: ({ canSuspend: true, canHibernate: true })
    property var wallpapers: []
    property string wallpaper: ""
    property int updates: 0
    property var pending: null
    property var select: null
    property var usage: ({})

    Component.onCompleted: Model.setBin(Util.home() + "/.local/bin/")

    // ---- open / close -----------------------------------------------------

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
            stack = [{ name: "root", title: "" }, { name: name, title: Model.rootTitle(name) }]
        if (name === "wallpaper")
            wallpaperList.running = true
        shown = true
    }
    function reset() {
        query = ""
        cursor = 0
        chip = 0
        mode = "insert"
        calcResult = ""
        pending = null
        select = null
        stack = [{ name: "root", title: "" }]
    }
    onShownChanged: {
        if (shown) {
            pointer = Qt.point(-1, -1)
            field.input.forceActiveFocus()
            return
        }
        if (select)
            Quickshell.execDetached(["bash", "-c", '[ -s "$1" ] || : > "$1"', "bash", select.outfile])
    }

    // ---- rows -------------------------------------------------------------

    function appRows() {
        const out = []
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay)
                continue
            out.push({ id: e.id, name: e.name, genericName: e.genericName || e.comment || "", keywords: e.keywords || [], icon: e.icon, entry: e, category: Model.categoryOf(e) })
        }
        return out
    }

    readonly property var chips: {
        if (!shown || section !== "apps")
            return []
        const present = {}
        for (const r of appRows())
            present[r.category] = true
        return ["All"].concat(Model.CATEGORIES.filter(c => present[c]))
    }

    function sectionRows(name) {
        switch (name) {
        case "root": return Model.rootRows(Icons, updates, System.summary)
        case "apps": {
            const all = appRows()
            const c = chips[chip]
            return c && c !== "All" ? all.filter(r => r.category === c) : all
        }
        case "system": return Model.systemRows(Icons, caps, System.summary)
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

    function frecency(id) { return Usage.score(usage, id) }

    readonly property var rows: {
        if (!shown)
            return []
        if (calcMode)
            return calcResult ? [{ id: "calc", name: calcResult, genericName: "Enter copies to clipboard", glyph: Icons.calc, copy: calcResult }] : []
        const q = query.trim()
        if (!q && section !== "apps")
            return sectionRows(section)
        let base = Search.sorted(sectionRows(section), q, section === "root" || section === "apps" ? frecency : null)
        if (section === "root" && q)
            base = base.concat(Search.sorted(appRows(), q, frecency))
        return base
    }
    readonly property bool grid: section === "wallpaper" && !query
    readonly property var current: rows[cursor]

    onRowsChanged: cursor = Math.min(cursor, Math.max(0, rows.length - 1))
    onQueryChanged: {
        cursor = 0
        if (calcMode)
            calcTimer.restart()
    }
    onChipChanged: cursor = 0

    // ---- actions ----------------------------------------------------------

    function push(name, title) {
        stack = stack.concat([{ name: name, title: title }])
        query = ""
        cursor = 0
        chip = 0
        mode = "insert"
        field.input.forceActiveFocus()
    }

    function back() {
        if (select || stack.length <= 1) {
            close()
            return
        }
        stack = stack.slice(0, -1)
        query = ""
        cursor = 0
        chip = 0
    }

    function remember(r) {
        if (r && r.id && (section === "root" || section === "apps"))
            usage = Usage.bump(usage, r.id)
    }

    function activate(r) {
        if (!r || r.disabled)
            return
        if (r.section) {
            if (r.section === "wallpaper")
                wallpaperList.running = true
            remember(r)
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
        remember(r)
        close()
        Commands.run(r)
    }

    function runAction(name) {
        switch (name) {
        case "notifications-clear": notifications.clearHistory(); break
        case "notifications-dismiss": close(); break
        case "back": back(); break
        case "clipboard-clear": clipboard.clear(); break
        }
    }

    function copyRow(r) {
        if (!r)
            return
        if (r.clip) {
            close()
            clipboard.copy(r.clip)
            return
        }
        Commands.copy(r.copy !== undefined ? r.copy : (r.sway || r.name))
        close()
    }

    function deleteRow(r) {
        if (r && r.clip)
            clipboard.remove(r.clip)
    }

    function descend(r) {
        if (r && r.section)
            activate(r)
    }

    function setMode(m) {
        mode = m
        if (m === "insert")
            field.input.forceActiveFocus()
        else
            keys.forceActiveFocus()
    }

    function cycleChip(delta) {
        if (chips.length)
            chip = (chip + delta + chips.length) % chips.length
    }

    // Cursor follows the pointer only when it actually moves. A static pointer
    // must not steal the cursor when the list scrolls under it (keyboard nav)
    // or when the card appears beneath it.
    property point pointer: Qt.point(-1, -1)
    function follow(view, p) {
        const moved = pointer.x >= 0 && (p.x !== pointer.x || p.y !== pointer.y)
        pointer = p
        if (!moved)
            return
        const i = view.indexAt(p.x + view.contentX, p.y + view.contentY)
        if (i >= 0)
            cursor = i
    }

    // Both modes funnel here. Returns true when handled.
    function perform(a) {
        if (!a)
            return false
        const pageSize = 6
        let next = -1
        if (grid && (a === "up" || a === "down"))
            next = KeyModel.move(cursor, rows.length, a === "up" ? -3 : 3)
        else if (grid && (a === "left" || a === "right"))
            next = KeyModel.move(cursor, rows.length, a === "left" ? -1 : 1)
        else
            next = KeyModel.step(a, cursor, rows.length, pageSize)
        if (next >= 0) {
            cursor = next
            return true
        }
        switch (a) {
        case "activate": activate(current); return true
        case "right": mode === "normal" ? activate(current) : descend(current); return true
        case "left": case "back": if (mode === "normal" || query === "") back(); else setMode("normal"); return true
        case "escape": if (mode === "insert") setMode("normal"); else close(); return true
        case "close": close(); return true
        case "insert": setMode("insert"); return true
        case "copy": copyRow(current); return true
        case "paste": if (current && current.clip) copyRow(current); else activate(current); return true
        case "delete": deleteRow(current); return true
        case "deleteWord": query = query.replace(/\s*\S+\s*$/, ""); return true
        case "clear": query = ""; return true
        case "nextChip": if (chips.length) cycleChip(1); else descend(current); return true
        case "prevChip": cycleChip(-1); return true
        }
        return false
    }

    // ---- data sources -----------------------------------------------------

    FileView { id: swayFile; path: Util.home() + "/.config/sway/config"; onLoaded: root.swayConfig = text() }
    FileView { id: tmuxFile; path: Util.home() + "/.config/tmux/tmux.conf"; onLoaded: root.tmuxConfig = text() }
    FileView {
        id: usageFile
        path: Util.stateDir + "/launcher-usage.json"
        atomicWrites: true
        printErrors: false
        onLoaded: root.usage = Usage.parse(text())
    }
    onUsageChanged: usageFile.setText(JSON.stringify(usage))

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
        screen: SwayState.focusedScreen
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
            height: Math.min(Style.cardMaxHeight, column.implicitHeight + Style.cardPadding * 2)
            radius: Style.cardRadius
            color: Color.cardBg
            border.width: 1
            border.color: Color.cardBorder

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                anchors.fill: parent
                anchors.margins: Style.cardPadding
                spacing: Style.spaceMd

                Header {
                    glyph: root.calcMode ? Icons.calc : (root.stack.length > 1 ? Icons.chevronRight : Icons.apps)
                    crumbs: root.select ? [root.select.prompt] : root.stack.slice(1).map(s => s.title)
                    mode: root.mode
                    status: root.calcMode ? "= " + (root.calcResult || "…") : (root.rows.length ? (root.cursor + 1) + "/" + root.rows.length : "")
                }

                Field {
                    id: field
                    width: parent.width
                    text: root.query
                    onTextChanged: root.query = text
                    placeholder: root.select ? root.select.prompt : (root.stack.length > 1 ? "Type to filter…  Esc for normal mode" : "Search apps, =expr to calculate…  Esc for normal mode")
                    onAccepted: root.activate(root.current)
                    onEscaped: root.perform("escape")
                    onKeyPressed: e => {
                        const a = KeyModel.insert(e, root.query !== "")
                        if (a && root.perform(a))
                            e.accepted = true
                    }
                }

                Chips {
                    visible: root.chips.length > 0
                    names: root.chips
                    current: root.chip
                    onPicked: i => root.chip = i
                }

                ListView {
                    id: list
                    width: parent.width
                    visible: !root.grid
                    height: visible ? Math.min(rows.count * Style.rowHeight, Style.cardMaxHeight - y - Style.cardPadding) : 0
                    clip: true
                    model: root.grid ? [] : root.rows
                    currentIndex: root.cursor
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    readonly property var rows: root.grid ? { count: 0 } : { count: root.rows.length }

                    delegate: ListRow {
                        id: entry
                        required property var modelData
                        required property int index
                        width: list.width
                        iconSource: modelData.thumb ? modelData.thumb : (modelData.icon ? Quickshell.iconPath(modelData.icon, true) : "")
                        glyph: modelData.glyph || Icons.apps
                        glyphColor: Color.accent
                        title: modelData.name
                        subtext: modelData.genericName || ""
                        trailing: {
                            if (modelData.popup && Popups.current === modelData.popup) return "current"
                            if (modelData.checked === true) return "●"
                            if (modelData.section) return "→"
                            return ""
                        }
                        trailingColor: modelData.checked === true ? Color.green : (modelData.popup && Popups.current === modelData.popup ? Color.accent : Color.muted)
                        selected: index === root.cursor
                        dim: modelData.disabled === true
                        onClicked: root.activate(modelData)
                    }

                    HoverHandler { onPointChanged: root.follow(list, point.position) }
                }

                GridView {
                    id: gridView
                    width: parent.width
                    visible: root.grid
                    height: visible ? Math.min(Math.ceil(count / 3) * cellHeight, Style.cardMaxHeight - y - Style.cardPadding) : 0
                    clip: true
                    model: root.grid ? root.rows : []
                    cellWidth: Math.floor(width / 3)
                    cellHeight: Math.round(cellWidth * 9 / 16) + Style.spaceXl * 2
                    currentIndex: root.cursor
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: gridView.cellWidth
                        height: gridView.cellHeight

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Style.spaceXs
                            radius: Style.radius
                            color: cell.index === root.cursor ? Color.rowSelected : "transparent"
                            border.width: cell.modelData.checked ? 2 : 0
                            border.color: Color.accent

                            Image {
                                anchors.fill: parent
                                anchors.margins: Style.spaceSm
                                anchors.bottomMargin: Style.spaceXl + Style.spaceSm
                                source: cell.modelData.thumb ? "file://" + cell.modelData.thumb : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 320
                                visible: cell.modelData.thumb !== undefined
                            }
                            Glyph {
                                anchors.centerIn: parent
                                visible: cell.modelData.thumb === undefined
                                text: cell.modelData.glyph
                                glyphColor: Color.accent
                                size: Style.fontTitle + 8
                            }
                            Label {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Style.spaceXs
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - Style.spaceMd * 2
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.name
                                font.pixelSize: Style.fontCaption
                                color: cell.modelData.checked ? Color.accent : Color.subtext0
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.activate(cell.modelData) }
                        }
                    }

                    HoverHandler { onPointChanged: root.follow(gridView, point.position) }
                }
            }
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: root.mode === "normal"
            Keys.onPressed: event => {
                event.accepted = root.perform(KeyModel.normal(event))
            }
        }
    }
}
