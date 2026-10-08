// Launcher menu tree. Rows share the shape AppSearch.js expects:
//   { id, name, genericName, keywords, glyph | icon, <one action key> }
// Action keys (first match wins in Launcher.activate / core/Commands.qml):
// section -> descend into a sub-list
// confirm -> row payload run after a Yes/Cancel step
// popup   -> open a panel popup by id
// clip    -> clipboard history entry (Enter copies, d deletes)
// toggle  -> flip a core/Toggles flag
// action  -> launcher-internal action name
// argv    -> exec
// term    -> exec inside a terminal window
// task    -> exec inside bin/qs-task (floating terminal, waits for Enter)
// sway    -> swaymsg command
// copy    -> put text on the clipboard
// entry   -> DesktopEntry (apps)
// Presentation: disabled/checked/warn/thumb (warn = yellow dot, e.g. reboot
// pending), tag (muted trailing text), origin/crumb (set by fromSection).

.pragma library

var BIN = "" // set by Launcher: Util.home() + "/.local/bin/"

function setBin(dir) { BIN = dir }

function row(id, name, generic, glyph, extra) {
  var r = { id: id, name: name, genericName: generic || "", keywords: [], glyph: glyph || "" }
  for (var k in extra) r[k] = extra[k]
  return r
}

// Sections whose rows join global search from root. Dynamic content
// (clipboard, notifications, wallpaper files) stays out.
var SEARCH_SECTIONS = ["system", "packages", "capture", "toggle", "setup", "keys-sway", "keys-tmux", "keys-launcher", "keys-popups"]

// Tags rows with their origin section so search results can show a
// breadcrumb and usage stats stay distinct per submenu.
function fromSection(rows, section, title) {
  return rows.filter(function (r) { return r && r.id }).map(function (r) {
    var c = {}
    for (var k in r) c[k] = r[k]
    c.origin = section
    c.crumb = title
    return c
  })
}

// reboot = System.summary ("" when not needed)
function rootRows(I, reboot) {
  return [
    row("apps", "Apps", "Launch an application", I.apps, { section: "apps", keywords: ["launch", "run"] }),
    row("system", "System", "Lock, sleep, reboot, shutdown", I.power, { section: "system", keywords: ["power"] }),
    row("keys", "Keybindings", "Sway, tmux, launcher, popups", I.keyboard, { section: "keys", keywords: ["shortcuts", "hotkeys", "keybinds"] }),
    row("capture", "Capture", "Screenshots", I.camera, { section: "capture", keywords: ["screenshot", "grim"] }),
    row("toggle", "Toggle", "Stay awake, night light, DND, bar", I.toggle, { section: "toggle" }),
    row("setup", "Setup", "Edit configs, wallpaper", I.cog, { section: "setup", keywords: ["config", "settings"] }),
    row("packages", "Packages", reboot ? "reboot required: " + reboot : "Install, remove, update", I.pkg, { section: "packages", keywords: ["install", "remove", "update", "pacman", "aur", "yay"], warn: !!reboot }),
    row("notifications", "Notifications", "History", I.bell, { section: "notifications", keywords: ["history"] }),
    row("clipboard", "Clipboard", "History · Enter copies", I.clipboard, { section: "clipboard", keywords: ["history", "paste"] }),
  ]
}

// Section -> breadcrumb title, built once from the static menu tree.
var TITLES = null

function titles() {
  if (TITLES) return TITLES
  TITLES = {}
  rootRows({}, "").forEach(function (r) { if (r.section) TITLES[r.section] = r.name })
  keyRows({}).forEach(function (r) { TITLES[r.section] = "Keybindings · " + r.name })
  return TITLES
}

// Breadcrumb title for any section, nested keybinding ones included.
function sectionTitle(section) {
  return titles()[section] || section.charAt(0).toUpperCase() + section.slice(1)
}

// caps = { canSuspend: bool, canHibernate: bool } from logind; reboot = System.summary
function systemRows(I, caps, reboot) {
  return [
    row("lock", "Lock", "swaylock", I.lock, { argv: ["swaylock", "-f"] }),
    row("suspend", "Suspend", caps.canSuspend ? "systemctl suspend" : "unavailable (logind CanSuspend)", I.sleep,
      { argv: caps.canSuspend ? ["systemctl", "suspend"] : undefined, disabled: !caps.canSuspend }),
    row("hibernate", "Hibernate", caps.canHibernate ? "systemctl hibernate" : "unavailable (logind CanHibernate)", I.sleep,
      { argv: caps.canHibernate ? ["systemctl", "hibernate"] : undefined, disabled: !caps.canHibernate }),
    row("reboot", "Reboot", reboot ? "required: " + reboot : "systemctl reboot", I.restart, { confirm: { argv: ["systemctl", "reboot"] }, warn: !!reboot }),
    row("shutdown", "Shutdown", "systemctl poweroff", I.power, { confirm: { argv: ["systemctl", "poweroff"] } }),
    row("logout", "Logout", "swaymsg exit", I.logout, { confirm: { sway: "exit" } }),
    row("restart-qs", "Restart Quickshell", "qs-session restart", I.restart, { argv: [BIN + "qs-session", "restart"] }),
  ]
}

// pending = the row that asked for confirmation
function confirmRows(I, pending) {
  var action = {}
  for (var k in pending.confirm) action[k] = pending.confirm[k]
  return [
    row("yes", "Yes, " + pending.name.toLowerCase(), pending.genericName, pending.glyph, action),
    row("no", "Cancel", "", I.close, { action: "back" }),
  ]
}

function captureRows(I) {
  function cap(id, name, generic, glyph) {
    return row(id, name, generic, glyph, { argv: [BIN + "qs-capture", id], keywords: ["screenshot", "grim"] })
  }
  return [
    cap("region", "Screenshot region", "select area → ~/Pictures", I.crop),
    cap("window", "Screenshot window", "focused window → ~/Pictures", I.window),
    cap("screen", "Screenshot screen", "full output → ~/Pictures", I.monitor),
    cap("region-clip", "Screenshot region to clipboard", "select area → wl-copy", I.clipboard),
    cap("color", "Pick color", "click a pixel → hex to clipboard", I.eyedropper),
  ]
}

// state = Toggles.active ({ name: true })
function toggleRows(I, state) {
  function t(id, name, onText, offText, glyph, kw) {
    var on = state[id] === true
    return row(id, name, on ? onText : offText, glyph, { toggle: id, checked: on, keywords: kw || [] })
  }
  return [
    t("awake", "Stay awake", "on - idle lock inhibited", "off", I.eye, ["idle", "caffeine", "inhibit"]),
    t("nightlight", "Night light", "on - 4000K", "off - 6500K", I.moon, ["wlsunset", "gamma", "redshift"]),
    t("dnd", "Do not disturb", "on - only critical notifications shown", "off", I.bellOff, ["notifications", "silence"]),
    t("bar-hidden", "Hide bar", "on", "off", I.monitor, ["panel"]),
  ]
}

// reboot = System.summary ("" when not needed)
function packageRows(I, reboot) {
  function pkg(id, name, generic, glyph, extra) {
    extra.task = [BIN + "qs-pkg", id]
    return row(id, name, generic, glyph, extra)
  }
  return [
    pkg("install", "Install from pacman", "official repositories · fzf, tab to multi-select", I.arch, { keywords: ["official", "repo", "package"] }),
    pkg("aur", "Install from AUR", "yay · falls back to yay-git when AUR is down", I.download, { keywords: ["yay", "package", "community"] }),
    pkg("remove", "Remove", "pacman -Rns · fzf, tab to multi-select", I.trash, { keywords: ["uninstall", "package"] }),
    pkg("update", "Update", reboot ? "yay -Syu · reboot required: " + reboot : "yay -Syu", I.update, { keywords: ["upgrade", "pacman", "yay", "reboot"], warn: !!reboot }),
  ]
}

function setupRows(I, home) {
  var c = home + "/.config/"
  function edit(id, name, path) {
    return row("edit-" + id, "Edit " + name, path.replace(home, "~"), I.pencil, { term: ["nvim", path], keywords: ["config", "edit"] })
  }
  return [
    edit("sway", "Sway config", c + "sway/config"),
    edit("qs", "Quickshell", c + "quickshell/shell.qml"),
    edit("kitty", "Kitty", c + "kitty/kitty.conf"),
    edit("zsh", "Zsh", c + "zsh/.zshrc"),
    edit("tmux", "Tmux", c + "tmux/tmux.conf"),
    edit("nvim", "Neovim", c + "nvim/init.lua"),
    edit("apps-hide", "App blacklist", c + "quickshell/apps-hide"),
    row("wallpaper", "Wallpaper", "pick from ~/.config/wallpapers", I.image, { section: "wallpaper", keywords: ["background"] }),
  ]
}

// files = [path]; current = resolved current wallpaper path
function wallpaperRows(I, files, current) {
  var rows = [row("random", "Random", "", I.image, { argv: [BIN + "qs-wallpaper", "random"] })]
  for (var i = 0; i < files.length; i++) {
    var f = files[i]
    var name = f.split("/").pop()
    rows.push(row("wp-" + i, name, f === current ? "current" : "", I.image, { argv: [BIN + "qs-wallpaper", "set", f], checked: f === current, thumb: f }))
  }
  return rows
}

// entries = clipboard/Clipboard.entries (newest first)
function clipboardRows(I, entries, U) {
  if (!entries.length) return [row("none", "Clipboard history is empty", "", I.clipboard, { action: "back" })]
  var rows = [row("clear", "Clear history", entries.length + " entries · Del removes one", I.trash, { confirm: { action: "clipboard-clear" } })]
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e.kind === "image") {
      rows.push(row("img-" + i, "Image", Math.round(e.size / 1024) + " KiB · " + U.timeAgo(e.time), I.image, { clip: e, thumb: e.file, keywords: ["image", "png"] }))
    } else {
      var oneLine = String(e.text).replace(/\s+/g, " ").trim()
      rows.push(row("txt-" + i, U.truncate(oneLine, 80), U.timeAgo(e.time), I.clipboard, { clip: e, keywords: oneLine.split(/\s+/).slice(0, 8) }))
    }
  }
  return rows
}

// history = notifications/Service.history (newest first)
function notificationRows(I, history, U) {
  var rows = []
  if (!history.length) return [row("none", "No notifications", "", I.bell, { action: "notifications-dismiss" })]
  rows.push(row("clear", "Clear history", history.length + " entries", I.trash, { action: "notifications-clear" }))
  for (var i = 0; i < history.length; i++) {
    var n = history[i]
    var body = String(n.body || "").replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim()
    var sub = [n.appName, body, U.timeAgo(n.time)].filter(function(x) { return x }).join(" · ")
    rows.push(row("n-" + n.id + "-" + n.time, n.summary || "(no summary)", sub, n.urgency === 2 ? I.alert : I.bell,
      { icon: n.appIcon || "", copy: body || n.summary, keywords: [n.appName] }))
  }
  return rows
}

// ---- Keybindings -----------------------------------------------------------
// Rows: name = human label, genericName = key combo, tag = config section.

function keyRows(I) {
  return [
    row("sway", "Sway", "~/.config/sway/config", I.window, { section: "keys-sway", keywords: ["wm", "window", "workspace"] }),
    row("tmux", "Tmux", "~/.config/tmux/tmux.conf", I.terminal, { section: "keys-tmux", keywords: ["pane", "terminal"] }),
    row("launcher", "Launcher", "this menu · insert and normal mode", I.apps, { section: "keys-launcher", keywords: ["menu", "vim"] }),
    row("popups", "Popups", "bar widgets · clock, battery, network, weather, media, audio", I.toggle, { section: "keys-popups", keywords: ["widget", "bar"] }),
  ]
}

// Ordered [regex, label] applied to the normalised command. `$1` and
// functions work like String.replace. `<dir>` / `<n>` mark merged h/j/k/l
// and digit groups. Unmatched commands show raw.
var SWAY_LABELS = [
  [/^kitty.* --class qs-float/, "Floating terminal"],
  [/^kitty/, "Terminal"],
  [/^qs-shell launcher toggle/, "Launcher"],
  [/^qs-shell launcher open (\w+)/, "Open $1"],
  [/^kill$/, "Close window"],
  [/^qs-quit/, "Quit application (SIGTERM)"],
  [/^reload$/, "Reload sway config"],
  [/^swaynag .*exit/, "Exit sway"],
  [/^qs-session restart/, "Restart Quickshell"],
  [/^swaylock/, "Lock screen"],
  [/^qs-toggle dnd/, "Toggle do not disturb"],
  [/^qs-toggle nightlight/, "Toggle night light"],
  [/^qs-toggle (\w+)/, "Toggle $1"],
  [/^qs-shell notifications dismissLatest/, "Dismiss latest notification"],
  [/^qs-shell notifications actionLatest/, "Run latest notification action"],
  [/^qs-wallpaper random/, "Random wallpaper"],
  [/^focus <dir>/, "Focus window"],
  [/^move <dir>/, "Move window"],
  [/^workspace number <n>/, "Switch to workspace"],
  [/^move container to workspace number <n>/, "Move window to workspace"],
  [/^workspace back_and_forth/, "Previous workspace"],
  [/^splith/, "Split side by side"],
  [/^splitv/, "Split stacked"],
  [/^layout stacking/, "Stacking layout"],
  [/^layout tabbed/, "Tabbed layout"],
  [/^layout toggle split/, "Toggle split direction"],
  [/^fullscreen/, "Fullscreen"],
  [/^floating toggle/, "Toggle floating"],
  [/^focus mode_toggle/, "Focus floating / tiling"],
  [/^focus parent/, "Focus parent container"],
  [/^move scratchpad/, "Move to scratchpad"],
  [/^scratchpad show/, "Show scratchpad"],
  [/^resize <dir>/, "Resize window"],
  [/^mode "default"/, "Leave mode"],
  [/^mode "(\w+)"/, function (m, name) { return cap(name) + " mode" }],
  [/^qs-shell popups open (\w+)/, function (m, id) { return cap(id) + " popup" }],
  [/^qs-shell popups toggle (\w+)/, function (m, id) { return cap(id) + " popup" }],
  [/^wpctl set-volume \S+ \d+%\+/, "Volume up"],
  [/^wpctl set-volume \S+ \d+%-/, "Volume down"],
  [/^wpctl set-mute @DEFAULT_AUDIO_SINK@/, "Mute"],
  [/^wpctl set-mute @DEFAULT_AUDIO_SOURCE@/, "Mute microphone"],
  [/^playerctl play-pause/, "Play / pause"],
  [/^playerctl next/, "Next track"],
  [/^playerctl previous/, "Previous track"],
  [/^brightnessctl set \d+%\+/, "Brightness up"],
  [/^brightnessctl set \d+%-/, "Brightness down"],
  [/^qs-capture region-clip/, "Screenshot region to clipboard"],
  [/^qs-capture region/, "Screenshot region"],
  [/^qs-capture screen/, "Screenshot screen"],
  [/^qs-capture window/, "Screenshot window"],
  [/^qs-capture color/, "Pick color"],
]

var TMUX_LABELS = [
  [/^send-prefix/, "Send prefix to nested tmux"],
  [/^send-keys -X begin-selection/, "Begin selection"],
  [/^send-keys -X rectangle-toggle/, "Toggle rectangle selection"],
  [/^send-keys -X copy-pipe-and-cancel/, "Copy selection to clipboard"],
  [/^send-keys -X cancel/, "Leave copy mode"],
  [/^send-keys -X start-of-line/, "Start of line"],
  [/^send-keys -X end-of-line/, "End of line"],
  [/^paste-buffer/, "Paste buffer"],
  [/^select-pane <dir>/, "Focus pane"],
  [/^resize-pane <dir>/, "Resize pane"],
  [/^new-window/, "New window"],
  [/^split-window -h/, "Split side by side"],
  [/^split-window/, "Split stacked"],
  [/^swap-window -t -1/, "Move window left"],
  [/^swap-window -t \+1/, "Move window right"],
  [/^kill-pane/, "Close pane"],
  [/^last-window/, "Previous window"],
  [/^display-popup .*lazygit/, "Lazygit popup"],
  [/^display-popup/, "Shell popup"],
  [/^source-file/, "Reload config"],
]

function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }

function label(table, cmd) {
  for (var i = 0; i < table.length; i++) {
    var m = cmd.match(table[i][0])
    if (!m) continue
    var l = table[i][1]
    return typeof l === "function" ? l.apply(null, m) : l.replace(/\$(\d)/g, function (_, d) { return m[d] })
  }
  return cmd
}

// Section header -> tag: "Popups ($mod+o prefix, ...)" -> "Popups"
function tagOf(header) { return header.split(" (")[0].split(":")[0].trim() }

// Merge binds that differ only in their last key: h/j/k/l with a direction
// word in the command, digits with a number, or identical commands. Each
// bind: { combo, cmd, run, scope, line }. `scope` keeps groups within one
// config section / mode. Merged binds lose `run`.
function splitCombo(combo) {
  var i = combo.lastIndexOf(" ")
  return { base: combo.slice(0, i + 1), last: combo.slice(i + 1) }
}

function merge(binds, groupKey, combine) {
  var groups = {}
  var order = []
  for (var i = 0; i < binds.length; i++) {
    var k = groupKey(binds[i])
    if (k === null) k = "\u0000" + i
    if (!groups[k]) { groups[k] = []; order.push(k) }
    groups[k].push(binds[i])
  }
  return order.map(function (k) { return groups[k].length > 1 ? combine(groups[k]) : groups[k][0] })
}

function groupBinds(binds, dirNorm) {
  function norm(b, re, token) {
    var c = b.cmd.replace(re, token)
    return c === b.cmd ? null : c
  }
  function merged(group, keys, cmd) {
    var f = group[0]
    return { combo: splitCombo(f.combo).base + keys, cmd: cmd, run: null, scope: f.scope, line: f.line }
  }
  var out = merge(binds, function (b) {
    var s = splitCombo(b.combo)
    var c = /^[hjkl]$/i.test(s.last) ? norm(b, dirNorm, "<dir>") : null
    return c === null ? null : b.scope + "|" + s.base + "|" + c
  }, function (g) {
    return merged(g, g.map(function (b) { return splitCombo(b.combo).last }).join("/"), g[0].cmd.replace(dirNorm, "<dir>"))
  })
  out = merge(out, function (b) {
    var s = splitCombo(b.combo)
    var c = /^\d$/.test(s.last) ? norm(b, /\b\d+\b/, "<n>") : null
    return c === null ? null : b.scope + "|" + s.base + "|" + c
  }, function (g) {
    var keys = g.map(function (b) { return splitCombo(b.combo).last })
    return merged(g, keys.length > 2 ? keys[0] + "-" + keys[keys.length - 1] : keys.join("/"), g[0].cmd.replace(/\b\d+\b/, "<n>"))
  })
  return merge(out, function (b) { return b.scope + "|" + b.cmd }, function (g) {
    var f = g[0]
    var parts = g.map(function (b) { return splitCombo(b.combo) })
    var sameBase = parts[0].base !== "" && parts.every(function (p) { return p.base === parts[0].base })
    var combo = sameBase
      ? parts[0].base + parts.map(function (p) { return p.last }).join(" / ")
      : g.map(function (b) { return b.combo }).join(" / ")
    return { combo: combo, cmd: f.cmd, run: f.run, scope: f.scope, line: f.line }
  })
}

// ~/.config/sway/config: `set $var value`, `### Section`, `mode "x" { ... }`,
// `bindsym [--flags] combo command`
function swayKeyRows(text, I) {
  var vars = {}
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].trim().match(/^set\s+(\$\S+)\s+(.+)$/)
    if (m) vars[m[1]] = m[2]
  }
  function subst(s) {
    return s.replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, function (v) { return vars[v] !== undefined ? vars[v] : v })
  }
  function combo(s) {
    return subst(s).replace(/\bMod4\b/g, "Super").replace(/\bMod1\b/g, "Alt").replace(/^XF86/, "").replace(/\+/g, " + ")
  }
  var binds = []
  var enter = {}
  var tag = ""
  var mode = ""
  for (var j = 0; j < lines.length; j++) {
    var l = lines[j].trim()
    var h = l.match(/^###\s*(.+)$/)
    if (h) { tag = tagOf(h[1]); continue }
    var mo = l.match(/^mode\s+"([^"]+)"\s*\{/)
    if (mo) { mode = mo[1]; continue }
    if (l === "}") { mode = ""; continue }
    var b = l.match(/^bind(?:sym|code)\s+(?:--\S+\s+)*(\S+)\s+(.+)$/)
    if (!b) continue
    var cmd = subst(b[2])
    var me = cmd.match(/^mode\s+"([^"]+)"$/)
    if (me && !mode) enter[me[1]] = combo(b[1])
    binds.push({ combo: combo(b[1]), cmd: cmd, run: cmd, scope: mode + "|" + tag, tag: tag, mode: mode, line: j })
  }
  for (var k = 0; k < binds.length; k++) {
    var x = binds[k]
    if (x.mode) x.combo = (enter[x.mode] || x.mode) + " › " + x.combo
  }
  var dir = /\b(left|down|up|right)\b|\b(shrink|grow) (width|height)\b/
  return groupBinds(binds, dir).map(function (x) {
    var shown = x.cmd.replace(/^exec\s+/, "").replace(/qs-shell -q /g, "qs-shell ").replace(/,\s*mode "default"$/, "")
    var extra = { tag: x.scope.split("|")[1], keywords: x.cmd.split(/\s+/).concat([x.scope.split("|")[1]]) }
    if (x.run && !/^mode "default"$/.test(x.run)) extra.sway = x.run
    return row("sway-" + x.line, label(SWAY_LABELS, shown), x.combo, I.keyboard, extra)
  })
}

// tmux.conf: `# Section`, `set -g prefix key`, `bind [-n] [-r] [-T table] key command...`
function tmuxKeyRows(text, I) {
  var lines = text.split("\n")
  var prefix = "C-b"
  var binds = []
  var tag = ""
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i].trim()
    var p = l.match(/^set(?:-option)?\s+-g\s+prefix\s+(\S+)/)
    if (p) { prefix = p[1]; continue }
    var h = l.match(/^#\s*(.+)$/)
    if (h) { tag = tagOf(h[1]); continue }
    var m = l.match(/^(?:bind|bind-key)\s+(.*)$/)
    if (!m) continue
    var parts = m[1].split(/\s+/)
    var table = "prefix"
    var key = null
    while (parts.length) {
      var a = parts.shift()
      if (a === "-n") table = "root"
      else if (a === "-T") table = parts.shift()
      else if (a.charAt(0) === "-") continue
      else { key = a.replace(/^'(.*)'$/, "$1"); break }
    }
    if (!key) continue
    var cmd = parts.join(" ").replace(/^\{\s*|\s*\}$/g, "")
    var combo = table === "prefix" ? prefix + " › " + key : key
    binds.push({ combo: combo, cmd: cmd, run: cmd, scope: table + "|" + tag, tag: tag, line: i })
  }
  return groupBinds(binds, /-[LDUR]\b/).map(function (x) {
    var extra = { tag: x.scope.split("|")[1], keywords: x.cmd.split(/\s+/).concat([x.scope.split("|")[1]]) }
    if (x.run) extra.copy = x.run
    return row("tmux-" + x.line, label(TMUX_LABELS, x.cmd), x.combo, I.terminal, extra)
  })
}

// Mirrors ui/KeyModel.js + launcher/Launcher.qml perform().
function launcherKeyRows(I) {
  function k(id, name, keys, tag) {
    return row("launcher-" + id, name, keys, I.apps, { tag: tag, keywords: [tag.toLowerCase()] })
  }
  return [
    k("insert", "Insert mode (type to search)", "i", "Normal"),
    k("normal", "Normal mode", "Esc", "Insert"),
    k("close", "Close", "Esc / q", "Normal"),
    k("down", "Down", "j / C-j / C-n / Down", "Both"),
    k("up", "Up", "k / C-k / C-p / Up", "Both"),
    k("half", "Half page down / up", "C-d / C-u / PgDn / PgUp", "Both"),
    k("ends", "Top / bottom", "gg / G / Home / End", "Normal"),
    k("jump", "Jump to row", "1-9", "Normal"),
    k("activate", "Activate", "Enter / Space", "Both"),
    k("descend", "Enter submenu", "l / C-l", "Both"),
    k("back", "Back · clear search", "h / C-h · Backspace on empty", "Both"),
    k("reset", "Clear search, keep mode", "C-o", "Both"),
    k("copy", "Copy row text", "y / C-y", "Both"),
    k("paste", "Paste clipboard row", "p", "Normal"),
    k("delete", "Delete row (clipboard, notifications)", "d / x / Del", "Both"),
    k("word", "Delete word", "C-w", "Insert"),
    k("refresh", "Refresh app list", "r / C-r", "Both"),
    k("hide", "Blacklist app", "C--", "Normal"),
  ]
}

// Mirrors the keymap blocks in panel/*.qml and ui/PopupCard.qml.
function popupKeyRows(I) {
  function k(popup, id, name, keys, glyph) {
    return row(popup + "-" + id, name, keys, glyph, { popup: popup, tag: cap(popup), keywords: [popup] })
  }
  return [
    row("popups-close", "Close popup", "Esc / q", I.close, { tag: "All", keywords: ["popup"] }),
    k("clock", "month", "Previous / next month", "h / l", I.calendar),
    k("clock", "year", "Previous / next year", "j / k", I.calendar),
    k("clock", "today", "Back to today", "t / Enter", I.calendar),
    k("battery", "profile", "Select power profile", "j / k", I.batteryFull),
    k("battery", "set", "Apply profile", "Enter", I.batteryFull),
    k("battery", "limit", "Toggle charge limit", "c", I.batteryFull),
    k("battery", "percent", "Toggle percent in bar", "p", I.batteryFull),
    k("network", "row", "Select network", "j / k", I.wifi4),
    k("network", "connect", "Connect / disconnect", "Enter", I.wifi4),
    k("network", "wifi", "Toggle Wi-Fi", "w", I.wifi4),
    k("network", "refresh", "Rescan", "r", I.wifi4),
    k("weather", "city", "Edit location", "e / Enter", I.thermometer),
    k("weather", "refresh", "Refresh", "r", I.thermometer),
    k("weather", "unit", "Toggle °C / °F", "u", I.thermometer),
    k("weather", "clear", "Clear location (auto-detect)", "d", I.thermometer),
    k("media", "toggle", "Play / pause", "p", I.music),
    k("media", "track", "Previous / next track", "h / l · [ / ]", I.music),
    k("media", "volume", "Volume down / up", "j / k", I.music),
    k("audio", "row", "Select device or stream", "j / k", I.volumeHigh),
    k("audio", "level", "Volume -5% / +5%", "h / l", I.volumeHigh),
    k("audio", "mute", "Mute", "m", I.volumeHigh),
    k("audio", "pick", "Set default device", "Enter", I.volumeHigh),
    row("tray-open", "Tray menu: open item", "l / Enter", I.toggle, { tag: "Tray", keywords: ["tray"] }),
    row("tray-back", "Tray menu: back", "h", I.toggle, { tag: "Tray", keywords: ["tray"] }),
  ]
}
