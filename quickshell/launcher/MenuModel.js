// Launcher menu tree. Rows share the shape AppSearch.js expects:
//   { id, name, genericName, keywords, glyph | icon, argv | section | sway | copy | toggle | popup | action | confirm }
// argv    -> exec (core/Commands.qml)
// sway    -> swaymsg command
// section -> descend into a sub-list
// copy    -> put text on the clipboard
// toggle  -> flip a core/Toggles flag
// popup   -> open a panel popup by id
// action  -> launcher-internal action name
// confirm -> row payload run after a Yes/Cancel step
// disabled/checked/thumb -> presentation

.pragma library

var BIN = "" // set by Launcher: Util.home() + "/.local/bin/"

function setBin(dir) { BIN = dir }

// Apps section chips, in display order. .desktop Categories → one bucket.
var CATEGORIES = ["Dev", "Games", "Graphics", "Net", "Office", "Media", "Settings", "System", "Tools", "Other"]
var CATEGORY_MAP = {
  Development: "Dev", IDE: "Dev", Game: "Games", Graphics: "Graphics", Network: "Net", WebBrowser: "Net",
  Office: "Office", AudioVideo: "Media", Audio: "Media", Video: "Media", Settings: "Settings",
  System: "System", Utility: "Tools",
}

function categoryOf(entry) {
  var cats = (entry && entry.categories) || []
  for (var i = 0; i < CATEGORIES.length; i++) {
    for (var j = 0; j < cats.length; j++) if (CATEGORY_MAP[cats[j]] === CATEGORIES[i]) return CATEGORIES[i]
  }
  return "Other"
}

function row(id, name, generic, glyph, extra) {
  var r = { id: id, name: name, genericName: generic || "", keywords: [], glyph: glyph || "" }
  for (var k in extra) r[k] = extra[k]
  return r
}

// Sections whose rows join global search from root. Dynamic content
// (clipboard, notifications, wallpaper files) stays out.
var SEARCH_SECTIONS = ["system", "capture", "toggle", "setup", "learn", "keybinds", "tmux"]

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

// updates = count from checkupdates; reboot = System.summary ("" when not needed)
function rootRows(I, updates, reboot) {
  return [
    row("apps", "Apps", "Launch an application", I.apps, { section: "apps", keywords: ["launch", "run"] }),
    row("system", "System", "Lock, sleep, reboot, shutdown", I.power, { section: "system", keywords: ["power"] }),
    row("keybinds", "Keybindings", "Sway bindings from ~/.config/sway/config", I.keyboard, { section: "keybinds", keywords: ["shortcuts", "sway"] }),
    row("tmux", "Tmux keybindings", "Bindings from tmux.conf", I.terminal, { section: "tmux", keywords: ["shortcuts"] }),
    row("capture", "Capture", "Screenshots", I.camera, { section: "capture", keywords: ["screenshot", "grim"] }),
    row("toggle", "Toggle", "Stay awake, night light, DND, bar", I.toggle, { section: "toggle" }),
    row("setup", "Setup", "Edit configs, Wi-Fi, audio", I.cog, { section: "setup", keywords: ["config", "settings"] }),
    row("update", "Update", [updates > 0 ? updates + " packages available" : "system up to date", reboot ? "reboot required: " + reboot : ""].filter(function (x) { return x }).join(" · "), I.update, { argv: ["ghostty", "-e", "sudo", "pacman", "-Syu"], keywords: ["upgrade", "pacman", "reboot"], checked: updates > 0 || !!reboot }),
    row("learn", "Learn", "Wikis and docs", I.book, { section: "learn", keywords: ["docs", "wiki", "help"] }),
    row("notifications", "Notifications", "History", I.bell, { section: "notifications", keywords: ["history"] }),
    row("clipboard", "Clipboard", "History · Enter copies", I.clipboard, { section: "clipboard", keywords: ["history", "paste"] }),
  ]
}

function rootTitle(section) {
  var rows = rootRows({}, 0)
  for (var i = 0; i < rows.length; i++) if (rows[i].section === section) return rows[i].name
  return section.charAt(0).toUpperCase() + section.slice(1)
}

// caps = { canSuspend: bool, canHibernate: bool } from logind; reboot = System.summary
function systemRows(I, caps, reboot) {
  return [
    row("lock", "Lock", "swaylock", I.lock, { argv: ["swaylock", "-f"] }),
    row("suspend", "Suspend", caps.canSuspend ? "systemctl suspend" : "unavailable (logind CanSuspend)", I.sleep,
      { argv: caps.canSuspend ? ["systemctl", "suspend"] : undefined, disabled: !caps.canSuspend }),
    row("hibernate", "Hibernate", caps.canHibernate ? "systemctl hibernate" : "unavailable (logind CanHibernate)", I.sleep,
      { argv: caps.canHibernate ? ["systemctl", "hibernate"] : undefined, disabled: !caps.canHibernate }),
    row("reboot", "Reboot", reboot ? "required: " + reboot : "systemctl reboot", I.restart, { confirm: { argv: ["systemctl", "reboot"] }, checked: !!reboot }),
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

function setupRows(I, home) {
  var c = home + "/.config/"
  function edit(id, name, path) {
    return row("edit-" + id, "Edit " + name, path.replace(home, "~"), I.pencil, { argv: ["ghostty", "-e", "nvim", path], keywords: ["config", "edit"] })
  }
  return [
    edit("sway", "Sway config", c + "sway/config"),
    edit("qs", "Quickshell", c + "quickshell/shell.qml"),
    edit("ghostty", "Ghostty", c + "ghostty/config"),
    edit("zsh", "Zsh", c + "zsh/.zshrc"),
    edit("tmux", "Tmux", c + "tmux/tmux.conf"),
    edit("nvim", "Neovim", c + "nvim/init.lua"),
    row("wallpaper", "Wallpaper", "pick from ~/.config/wallpapers", I.image, { section: "wallpaper", keywords: ["background"] }),
    row("wifi", "Wi-Fi", "network popup", I.wifi4, { popup: "network", keywords: ["network", "nmtui"] }),
    row("audio", "Audio", "outputs, mic, per-app volume", I.volumeHigh, { popup: "audio", keywords: ["volume", "sound"] }),
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

function learnRows(I) {
  function web(id, name, url) {
    return row(id, name, url, I.web, { argv: ["librewolf", url] })
  }
  return [
    web("arch", "Arch Wiki", "https://wiki.archlinux.org"),
    web("sway", "Sway Wiki", "https://github.com/swaywm/sway/wiki"),
    web("qs", "Quickshell docs", "https://quickshell.org/docs"),
    web("cat", "Catppuccin", "https://catppuccin.com/palette"),
  ]
}

// ~/.config/sway/config: `set $var value` + `bindsym [--flags] combo command`
function parseSwayBinds(text, I) {
  var vars = {}
  var rows = []
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i].trim()
    var m = l.match(/^set\s+(\$\S+)\s+(.+)$/)
    if (m) vars[m[1]] = m[2]
  }
  function subst(s) {
    return s.replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, function(v) { return vars[v] !== undefined ? vars[v] : v })
  }
  for (var j = 0; j < lines.length; j++) {
    var b = lines[j].trim().match(/^bind(?:sym|code)\s+((?:--\S+\s+)*)(\S+)\s+(.+)$/)
    if (!b) continue
    var combo = subst(b[2]).replace(/\bMod4\b/g, "Super").replace(/\bMod1\b/g, "Alt").replace(/\+/g, " + ")
    var cmd = subst(b[3])
    rows.push(row("sway-" + j, combo, cmd, I.keyboard, { sway: cmd, keywords: cmd.split(/\s+/) }))
  }
  return rows
}

// tmux.conf: `bind [-n] [-r] [-T table] key command...` (display only)
function parseTmuxBinds(text, I) {
  var rows = []
  var lines = text.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i].trim()
    var m = l.match(/^(?:bind|bind-key)\s+(.*)$/)
    if (!m) continue
    var parts = m[1].split(/\s+/)
    var table = "prefix"
    var key = null
    while (parts.length) {
      var p = parts.shift()
      if (p === "-n") table = "root"
      else if (p === "-r") continue
      else if (p === "-T") table = parts.shift()
      else if (p.charAt(0) === "-") continue
      else { key = p; break }
    }
    if (!key) continue
    var cmd = parts.join(" ")
    var label = (table === "prefix" ? "C-s " : table === "root" ? "" : table + " ") + key
    rows.push(row("tmux-" + i, label, cmd, I.terminal, { copy: cmd, keywords: cmd.split(/\s+/) }))
  }
  return rows
}
