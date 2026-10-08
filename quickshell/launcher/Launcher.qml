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
    property var pending: null
    property var usage: ({})
    // .desktop ids qs-apps allows (explicit packages minus apps-hide). Empty = show all.
    property var allowedApps: ({})
    // Row highlighted when the current search began; resetSearch() returns to it.
    property var searchFrom: null
    property string lastQuery: ""

    Component.onCompleted: {
        Model.setBin(Util.home() + "/.local/bin/")
        appsProbe.running = true
    }

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
    // Re-reads the installed app list (pacman hook touches /run/qs-apps-changed
    // automatically; Ctrl+R / r covers flatpak and other sources).
    function refresh() { appsProbe.running = true }
    function openSection(name) {
        reset()
        if (name && name !== "root")
            stack = [{ name: "root", title: "", id: name }, { name: name, title: Model.sectionTitle(name) }]
        if (name === "wallpaper")
            wallpaperList.running = true
        shown = true
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
        case "root": return Model.rootRows(Icons, System.summary)
        case "apps": return appRows()
        case "system": return Model.systemRows(Icons, caps, System.summary)
        case "confirm": return pending ? Model.confirmRows(Icons, pending) : []
        case "keys": return Model.keyRows(Icons)
        case "keys-sway": return Model.swayKeyRows(swayConfig, Icons)
        case "keys-tmux": return Model.tmuxKeyRows(tmuxConfig, Icons)
        case "keys-launcher": return Model.launcherKeyRows(Icons)
        case "keys-popups": return Model.popupKeyRows(Icons)
        case "capture": return Model.captureRows(Icons)
        case "packages": return Model.packageRows(Icons, System.summary)
        case "toggle": return Model.toggleRows(Icons, Toggles.active)
        case "setup": return Model.setupRows(Icons, Util.home())
        case "wallpaper": return Model.wallpaperRows(Icons, wallpapers, wallpaper)
        case "clipboard": return Model.clipboardRows(Icons, clipboard.entries, Util)
        case "notifications": return Model.notificationRows(Icons, notifications.history, Util)
        default: return []
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
    readonly property int rowsHeight: rows.reduce((h, r) => h + Style.rowHeight + (r.crumb ? Style.crumbHeight : 0), 0)

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
            if (r.section === "wallpaper")
                wallpaperList.running = true
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
            runAction(r.action)
            return
        }
        remember(r)
        close()
        Commands.run(r)
    }

    function runAction(name) {
        if (name.startsWith("hide:")) {
            hideApp(name.slice(5))
            return
        }
        switch (name) {
        case "notifications-clear": notifications.clearHistory(); break
        case "notifications-dismiss": close(); break
        case "back": back(); break
        case "clipboard-clear": clipboard.clear(); break
        }
    }

    // Ctrl+- on an app row: confirm, then append its id to apps-hide via
    // qs-apps. Undo is manual (Setup > Edit App blacklist).
    function askHide(r) {
        if (mode !== "normal" || section !== "apps" || !r || !r.entry)
            return
        pending = { name: "Blacklist " + r.name, genericName: "undo: delete its line in ~/.config/quickshell/apps-hide", glyph: Icons.eyeOff, confirm: { action: "hide:" + r.id } }
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

    Process {
        id: appsProbe
        command: [Util.bin("qs-apps"), "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const set = {}
                for (const id of JSON.parse(text || "[]"))
                    set[id] = true
                root.allowedApps = set
                appsProbe.command = [Util.bin("qs-apps"), "list"]
            }
        }
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
                        const a = KeyModel.insert(e, root.query !== "")
                        if (a && root.perform(a))
                            e.accepted = true
                    }
                }

                ListView {
                    id: list
                    width: parent.width
                    visible: !root.grid
                    height: visible ? Math.min(root.rowsHeight, Style.cardMaxHeight - y - Style.cardPadding) : 0
                    clip: true
                    model: root.grid ? [] : root.rows
                    currentIndex: root.cursor
                    highlightMoveDuration: 0
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

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
                        crumb: modelData.crumb || ""
                        trailing: {
                            if (modelData.tag) return modelData.tag
                            if (modelData.popup && Popups.current === modelData.popup) return "current"
                            if (modelData.checked === true || modelData.warn === true) return "●"
                            if (modelData.section) return "→"
                            return ""
                        }
                        trailingColor: {
                            if (modelData.warn === true) return Color.yellow
                            if (modelData.checked === true) return Color.green
                            if (modelData.popup && Popups.current === modelData.popup) return Color.accent
                            return Color.muted
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
                    height: visible ? Math.min(Math.ceil(count / root.gridCols) * cellHeight, Style.cardMaxHeight - y - Style.cardPadding) : 0
                    clip: true
                    model: root.grid ? root.rows : []
                    cellWidth: Math.floor(width / root.gridCols)
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
