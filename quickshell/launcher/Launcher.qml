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

    required property var notifications
    required property var clipboard

    property string swayConfig: ""
    property string tmuxConfig: ""
    property var caps: ({ canSuspend: true, canHibernate: true })
    property var wallpapers: []
    property string wallpaper: ""
    property var drives: []
    property var defaults: []
    property var pending: null
    property var usage: ({})
    // .desktop ids qs-apps allows (explicit packages minus apps-hide). Empty = show all.
    property var allowedApps: ({})
    // Row highlighted when the current search began; resetSearch() returns to it.
    property var searchFrom: null
    property string lastQuery: ""

    Component.onCompleted: {
        Model.setBin(Util.bin(""))
        appsProbe.running = true
    }

    // ---- open / close -----------------------------------------------------

    function toggle() { shown ? close() : open() }
    function close() { shown = false }
    function open() {
        if (Lock.locked)
            return
        reset()
        swayFile.reload()
        tmuxFile.reload()
        capsProbe.running = true
        shown = true
    }
    // Re-reads the installed app list (pacman hook touches /run/qs-apps-changed
    // automatically; Ctrl+R / r covers flatpak and other sources).
    function refresh() { appsProbe.running = true }
    function openSection(name) {
        if (Lock.locked)
            return
        reset()
        if (name && name !== "root")
            stack = [{ name: "root", title: "", id: name }, { name: name, title: Model.sectionTitle(name) }]
        load(name)
        shown = true
    }
    // Sections listed by a helper script (re)run it on entry.
    function load(name) {
        switch (name) {
        case "wallpaper": wallpaperList.running = true; break
        case "usb": usbList.running = true; break
        case "defaults": defaultsList.running = true; break
        }
    }
    function reset() {
        query = ""
        cursor = 0
        mode = "insert"
        calcResult = ""
        pending = null
        searchFrom = null
        stack = [{ name: "root", title: "" }]
    }
    onShownChanged: {
        if (shown) {
            pointer = Qt.point(-1, -1)
            field.input.forceActiveFocus()
        }
    }

    // ---- rows -------------------------------------------------------------

    function appRows() {
        const out = []
        const filter = Object.keys(allowedApps).length > 0
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || (filter && !allowedApps[e.id]))
                continue
            out.push({ id: e.id, name: e.name, genericName: e.genericName || e.comment || "", keywords: e.keywords || [], icon: e.icon, entry: e })
        }
        return out
    }

    function sectionRows(name) {
        switch (name) {
        case "root": return Model.rootRows(Icons, System.summary, System.pacnew)
        case "apps": return appRows()
        case "system": return Model.systemRows(Icons, caps, System.summary)
        case "confirm": return pending ? Model.confirmRows(Icons, pending) : []
        case "keys": return Model.keyRows(Icons)
        case "keys-sway": return Model.swayKeyRows(swayConfig, Icons)
        case "keys-tmux": return Model.tmuxKeyRows(tmuxConfig, Icons)
        case "keys-launcher": return Model.launcherKeyRows(Icons)
        case "keys-popups": return Model.popupKeyRows(Icons)
        case "capture": return Model.captureRows(Icons)
        case "packages": return Model.packageRows(Icons, System.summary, System.pacnew)
        case "toggle": return Model.toggleRows(Icons, Toggles.active)
        case "setup": return Model.setupRows(Icons, Util.home())
        case "wallpaper": return Model.wallpaperRows(Icons, wallpapers, wallpaper)
        case "defaults": return Model.defaultsRows(Icons, defaults)
        case "utils": return Model.utilsRows(Icons)
        case "usb": return Model.usbRows(Icons, drives)
        case "clipboard": return Model.clipboardRows(Icons, clipboard.entries, Util)
        case "notifications": return Model.notificationRows(Icons, notifications.history, Util)
        default: return name.startsWith("defaults-") ? Model.defaultAppRows(Icons, defaults, name.slice(9)) : []
        }
    }

    function frecency(r) { return Usage.score(usage, usageKey(r)) }

    // Rows reached via a submenu are keyed by origin so the same id in two
    // menus (e.g. "update" under Packages vs a future Setup row) keeps
    // separate stats. Browsing a section and finding its row from root
    // search share a key.
    function usageKey(r) {
        const o = r.origin || (section === "root" || section === "apps" ? "" : section)
        return o ? o + ":" + r.id : r.id
    }

    // Flattened tree for global search from root. Rebuilds only when a
    // source changes, not per keystroke.
    readonly property var searchIndex: {
        if (!shown)
            return []
        let out = sectionRows("root").concat(appRows())
        for (const s of Model.SEARCH_SECTIONS)
            out = out.concat(Model.fromSection(sectionRows(s), s, Model.sectionTitle(s)))
        return out
    }

    readonly property var rows: {
        if (!shown)
            return []
        if (calcMode)
            return calcResult ? [{ id: "calc", name: calcResult, genericName: "Enter copies to clipboard", glyph: Icons.calc, copy: calcResult }] : []
        const q = query.trim()
        if (!q && section !== "apps")
            return sectionRows(section)
        if (section === "root")
            return Search.sorted(searchIndex, q, frecency)
        return Search.sorted(sectionRows(section), q, frecency)
    }
    readonly property bool grid: section === "wallpaper" && !query
    readonly property int gridCols: 3
    readonly property var current: rows[cursor]
    // Crumb rows (search hits from a submenu) are taller.
    readonly property var rowHeights: rows.map(r => Style.rowHeight + (r.crumb ? Style.crumbHeight : 0))
    readonly property int rowPeek: Math.round(Style.rowHeight * 0.55)

    // When every row fits the list takes its full height. When they do not,
    // the list ends mid-row: a clipped row is what tells the eye there is
    // more below the fold, so it never comes out even on a row boundary.
    function foldedHeight(heights, available, peek) {
        available = Math.max(0, available)
        let total = 0
        const totals = heights.map(h => total += h)
        if (total <= available)
            return total
        let full = totals.filter(t => t <= available).length
        while (full > 1 && totals[full - 1] + peek > available)
            full--
        return full > 0 ? Math.min(available, totals[full - 1] + peek) : available
    }

    // Contain alone parks the cursor row flush with the viewport edge and
    // hides its neighbour, losing the fold cue. Keep the next row peeking
    // past the cursor on both sides when there is one. A model swap fires
    // currentIndexChanged before the folded height binding has caught up, so
    // the view calls this again from onHeightChanged / onCountChanged.
    function reveal(view, mode, peek) {
        if (view.height <= 0 || view.currentIndex < 0)
            return
        view.positionViewAtIndex(view.currentIndex, mode)
        const item = view.itemAtIndex(view.currentIndex)
        if (!item)
            return
        const maxY = Math.max(view.originY, view.originY + view.contentHeight - view.height)
        const over = item.y + item.height + peek - (view.contentY + view.height)
        if (view.currentIndex < view.count - 1 && over > 0)
            view.contentY = Math.min(view.contentY + over, maxY)
        const under = view.contentY - (item.y - peek)
        if (view.currentIndex > 0 && under > 0)
            view.contentY = Math.max(view.contentY - under, view.originY)
    }

    onRowsChanged: cursor = Math.min(cursor, Math.max(0, rows.length - 1))
    onQueryChanged: {
        if (lastQuery === "" && query !== "")
            searchFrom = { cursor: cursor, id: current ? current.id : undefined }
        lastQuery = query
        cursor = 0
        if (calcMode)
            calcTimer.restart()
    }

    // ---- actions ----------------------------------------------------------

    // Navigation never changes mode; only `i` does. The leaving frame
    // remembers its filter and highlighted row so back() restores them.
    function push(name, title) {
        const top = Object.assign({}, stack[stack.length - 1], { query: query, cursor: cursor, id: current ? current.id : undefined, searchFrom: searchFrom })
        stack = stack.slice(0, -1).concat([top, { name: name, title: title }])
        query = ""
        cursor = 0
        searchFrom = null
        focusMode()
    }

    // Pops one frame. Returns false at root.
    function back() {
        if (stack.length <= 1)
            return false
        const top = stack[stack.length - 2]
        stack = stack.slice(0, -1)
        query = top.query || ""
        searchFrom = top.searchFrom || null
        restoreCursor(top)
        focusMode()
        return true
    }

    // Clears the query and returns to the row highlighted before searching.
    function resetSearch() {
        const from = searchFrom
        query = ""
        if (from)
            restoreCursor(from)
        searchFrom = null
    }

    function restoreCursor(saved) {
        const i = rows.findIndex(r => r.id !== undefined && r.id === saved.id)
        cursor = i >= 0 ? i : (saved.cursor || 0)
    }

    function focusMode() {
        if (mode === "insert")
            field.input.forceActiveFocus()
        else
            keys.forceActiveFocus()
    }

    function remember(r) {
        if (r && r.id && section !== "confirm")
            usage = Usage.bump(usage, usageKey(r))
    }

    function activate(r) {
        if (!r || r.disabled)
            return
        if (r.section) {
            load(r.section)
            remember(r)
            push(r.section, r.name)
            return
        }
        if (r.confirm) {
            remember(r)
            pending = r
            push("confirm", r.name + "?")
            return
        }
        if (r.popup) {
            remember(r)
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
            remember(r)
            Toggles.flip(r.toggle)
            return
        }
        if (r.action) {
            runAction(r)
            return
        }
        remember(r)
        close()
        Commands.run(r)
    }

    // action = name, args = list handed to a helper script that ends by
    // printing its list again, so the section redraws in place (Mount
    // becomes Unmount). A probe mid-flight keeps its command: Enter again
    // once the rows have redrawn.
    function runAction(r) {
        switch (r.action) {
        case "hide": hideApp(r.args[0]); break
        case "usb": rerun(usbList, "qs-usb", r.args); break
        case "default": rerun(defaultsList, "qs-defaults", ["set"].concat(r.args)); break
        case "notifications-clear": notifications.clearHistory(); break
        case "notifications-dismiss": close(); break
        case "back": back(); break
        case "clipboard-clear": clipboard.clear(); break
        }
    }

    function rerun(probe, script, args) {
        if (probe.running)
            return
        probe.command = [Util.bin(script)].concat(args)
        probe.running = true
    }

    // Probe output: re-arm `list` before parsing, so a bad payload can never
    // leave a device action on the trigger; the old rows stay on a parse error.
    function listed(probe, script, text, previous) {
        probe.command = [Util.bin(script), "list"]
        try {
            return JSON.parse(text || "[]")
        } catch (e) {
            console.warn(script + ": " + e.message)
            return previous
        }
    }

    // Ctrl+- on an app row: confirm, then append its id to apps-hide via
    // qs-apps. Undo is manual (Setup > Edit App blacklist).
    function askHide(r) {
        if (mode !== "normal" || section !== "apps" || !r || !r.entry)
            return
        pending = { name: "Blacklist " + r.name, genericName: "undo: delete its line in ~/.config/quickshell/apps-hide", glyph: Icons.eyeOff, confirm: { action: "hide", args: [r.id] } }
        push("confirm", "Do you really want to blacklist " + r.name + "?")
    }

    function hideApp(id) {
        appsProbe.command = [Util.bin("qs-apps"), "hide", id]
        appsProbe.running = true
        back()
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
        focusMode()
    }

    // Cursor follows the pointer only when it actually moves. A static pointer
    // must not steal the cursor when the list scrolls under it (keyboard nav)
    // or when the card appears beneath it; sub-pixel touchpad jitter does not
    // count as movement either.
    property point pointer: Qt.point(-1, -1)
    function follow(view, p) {
        const moved = pointer.x >= 0 && (Math.abs(p.x - pointer.x) > 1 || Math.abs(p.y - pointer.y) > 1)
        if (pointer.x < 0 || moved)
            pointer = p
        if (!moved)
            return
        const i = view.indexAt(p.x + view.contentX, p.y + view.contentY)
        if (i >= 0)
            cursor = i
    }

    // Grid h/l stay inside the row; h at column 0 falls through to back().
    function gridStep(a) {
        const col = cursor % gridCols
        if (a === "left")
            return col === 0 ? -1 : cursor - 1
        return col === gridCols - 1 ? cursor : KeyModel.move(cursor, rows.length, 1)
    }

    // 70% of the visible rows, so Ctrl-D/U keep some context on screen.
    function pageSize() {
        const visible = grid ? Math.floor(gridView.height / gridView.cellHeight) * gridCols : Math.floor(list.height / Style.rowHeight)
        return Math.max(1, Math.round(visible * 0.7))
    }

    // Both modes funnel here. Returns true when handled.
    function perform(a) {
        if (!a)
            return false
        let next = -1
        if (grid && (a === "up" || a === "down"))
            next = KeyModel.move(cursor, rows.length, a === "up" ? -gridCols : gridCols)
        else if (grid && (a === "left" || a === "right"))
            next = gridStep(a)
        else
            next = KeyModel.step(a, cursor, rows.length, pageSize())
        if (next >= 0) {
            cursor = next
            return true
        }
        switch (a) {
        case "activate": activate(current); return true
        case "right": descend(current); return true
        case "left": if (query !== "") resetSearch(); else back(); return true
        case "back": if (!back()) close(); return true
        case "escape": if (mode === "insert") setMode("normal"); else close(); return true
        case "close": close(); return true
        case "insert": setMode("insert"); return true
        case "copy": copyRow(current); return true
        case "paste": if (current && current.clip) copyRow(current); return true
        case "delete": deleteRow(current); return true
        case "deleteWord": query = query.replace(/\s*\S+\s*$/, ""); return true
        case "reset": resetSearch(); return true
        case "refresh": refresh(); return true
        case "hide": askHide(current); return true
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

    // An empty allowedApps shows every entry, so a failed or empty list must
    // not replace a good one: the last list stays, the failure is logged.
    Process {
        id: appsProbe
        command: [Util.bin("qs-apps"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = root.listed(appsProbe, "qs-apps", text, [])
                if (!Array.isArray(ids) || ids.length === 0)
                    return
                const set = {}
                for (const id of ids)
                    set[id] = true
                root.allowedApps = set
            }
        }
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("qs-apps: exit " + code)
        }
    }
    Process {
        id: usbList
        command: [Util.bin("qs-usb"), "list"]
        stdout: StdioCollector { onStreamFinished: root.drives = root.listed(usbList, "qs-usb", text, root.drives) }
    }
    Process {
        id: defaultsList
        command: [Util.bin("qs-defaults"), "list"]
        stdout: StdioCollector { onStreamFinished: root.defaults = root.listed(defaultsList, "qs-defaults", text, root.defaults) }
    }
    // Both files only trigger a probe; apps-hide content is read by qs-apps.
    FileView {
        path: "/run/qs-apps-changed"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }
    FileView {
        path: Util.home() + "/.config/quickshell/apps-hide"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }

    // ---- window -----------------------------------------------------------

    PanelWindow {
        visible: root.shown
        screen: SwayState.focusedScreen
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown && !Lock.locked ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height * 0.18)
            width: Style.cardWidth
            height: Math.min(Style.cardMaxHeight, column.implicitHeight + Style.cardPadding * 2)
            radius: Style.cardRadius
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.cardBorder

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                anchors.fill: parent
                anchors.margins: Style.cardPadding
                spacing: Style.spaceMd

                Header {
                    glyph: root.calcMode ? Icons.calc : (root.stack.length > 1 ? Icons.chevronRight : Icons.apps)
                    crumbs: root.stack.slice(1).map(s => s.title)
                    mode: root.mode
                    status: root.calcMode ? "= " + (root.calcResult || "…") : (root.rows.length ? (root.cursor + 1) + "/" + root.rows.length : "")
                }

                Field {
                    id: field
                    width: parent.width
                    text: root.query
                    onTextChanged: root.query = text
                    placeholder: root.stack.length > 1 ? "Type to filter…  Esc for normal mode" : "Search apps, =expr to calculate…  Esc for normal mode"
                    onAccepted: root.activate(root.current)
                    onEscaped: root.perform("escape")
                    onKeyPressed: e => {
                        const a = KeyModel.insert(e)
                        if (a && root.perform(a))
                            e.accepted = true
                    }
                }

                ListView {
                    id: list
                    width: parent.width
                    visible: !root.grid
                    height: visible ? root.foldedHeight(root.rowHeights, Style.cardMaxHeight - y - Style.cardPadding, root.rowPeek) : 0
                    clip: true
                    model: root.grid ? [] : root.rows
                    currentIndex: root.cursor
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: root.reveal(list, ListView.Contain, root.rowPeek)
                    onHeightChanged: root.reveal(list, ListView.Contain, root.rowPeek)
                    onCountChanged: root.reveal(list, ListView.Contain, root.rowPeek)

                    delegate: ListRow {
                        id: entry
                        required property var modelData
                        required property int index
                        width: list.width
                        iconSource: modelData.thumb ? Util.fileUrl(modelData.thumb) : (modelData.icon ? Quickshell.iconPath(modelData.icon, true) : "")
                        glyph: modelData.glyph || Icons.apps
                        glyphColor: Theme.accent
                        title: modelData.name
                        subtext: modelData.genericName || ""
                        crumb: modelData.crumb || ""
                        trailing: {
                            if (modelData.tag) return modelData.tag
                            if (modelData.popup && Popups.current === modelData.popup) return "current"
                            if (modelData.checked === true || modelData.warn === true) return "●"
                            if (modelData.section) return "→"
                            return ""
                        }
                        trailingColor: {
                            if (modelData.warn === true) return Theme.yellow
                            if (modelData.checked === true) return Theme.green
                            if (modelData.popup && Popups.current === modelData.popup) return Theme.accent
                            return Theme.muted
                        }
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
                    readonly property int peek: Math.round(cellHeight * 0.55)
                    height: visible ? root.foldedHeight(Array(Math.ceil(count / root.gridCols)).fill(cellHeight), Style.cardMaxHeight - y - Style.cardPadding, peek) : 0
                    clip: true
                    model: root.grid ? root.rows : []
                    cellWidth: Math.floor(width / root.gridCols)
                    cellHeight: Math.round(cellWidth * 9 / 16) + Style.spaceXl * 2
                    currentIndex: root.cursor
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: root.reveal(gridView, GridView.Contain, peek)
                    onHeightChanged: root.reveal(gridView, GridView.Contain, peek)
                    onCountChanged: root.reveal(gridView, GridView.Contain, peek)

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
                            color: cell.index === root.cursor ? Theme.rowSelected : "transparent"
                            border.width: cell.modelData.checked ? 2 : 0
                            border.color: Theme.accent

                            Image {
                                anchors.fill: parent
                                anchors.margins: Style.spaceSm
                                anchors.bottomMargin: Style.spaceXl + Style.spaceSm
                                source: Util.fileUrl(cell.modelData.thumb)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 320
                                visible: cell.modelData.thumb !== undefined
                            }
                            Glyph {
                                anchors.centerIn: parent
                                visible: cell.modelData.thumb === undefined
                                text: cell.modelData.glyph
                                glyphColor: Theme.accent
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
                                color: cell.modelData.checked ? Theme.accent : Theme.subtext0
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
