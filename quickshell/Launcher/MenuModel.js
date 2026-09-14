// Launcher menu tree. Rows share the shape AppSearch.js expects:
//   { id, name, genericName, keywords, glyph | icon, run | section | sway | copy }
// run    -> shell command via bash -lc (detached)
// sway   -> swaymsg command
// section-> descend into a sub-list (rows array or provider name)
// copy   -> put text on the clipboard (wl-copy)

.pragma library

var TERM = "ghostty -e "

function row(id, name, generic, glyph, extra) {
  var r = { id: id, name: name, genericName: generic || "", keywords: [], glyph: glyph || "" }
  for (var k in extra) r[k] = extra[k]
  return r
}

function rootRows(I) {
  return [
    row("apps", "Apps", "Launch an application", I.apps, { section: "apps", keywords: ["launch", "run"] }),
    row("system", "System", "Lock, sleep, reboot, shutdown", I.power, { section: "system", keywords: ["power"] }),
    row("keybinds", "Keybindings", "Sway bindings from ~/.config/sway/config", I.keyboard, { section: "keybinds", keywords: ["shortcuts", "sway"] }),
    row("tmux", "Tmux keybindings", "Bindings from tmux.conf", I.terminal, { section: "tmux", keywords: ["shortcuts"] }),
    row("capture", "Capture", "Screenshots", I.camera, { section: "capture", keywords: ["screenshot", "grim"] }),
    row("toggle", "Toggle", "Stay awake, DND", I.toggle, { section: "toggle" }),
    row("setup", "Setup", "Edit configs, Wi-Fi, Bluetooth", I.cog, { section: "setup", keywords: ["config", "settings"] }),
    row("update", "Update", "pacman -Syu", I.update, { run: TERM + "sudo pacman -Syu", keywords: ["upgrade", "pacman"] }),
    row("learn", "Learn", "Wikis and docs", I.book, { section: "learn", keywords: ["docs", "wiki", "help"] }),
  ]
}

function systemRows(I) {
  return [
    row("lock", "Lock", "swaylock", I.lock, { run: "swaylock -f" }),
    row("suspend", "Suspend", "systemctl suspend", I.sleep, { run: "systemctl suspend" }),
    row("hibernate", "Hibernate", "systemctl hibernate", I.sleep, { run: "systemctl hibernate" }),
    row("reboot", "Reboot", "systemctl reboot", I.restart, { run: "systemctl reboot" }),
    row("shutdown", "Shutdown", "systemctl poweroff", I.power, { run: "systemctl poweroff" }),
    row("logout", "Logout", "swaymsg exit", I.logout, { sway: "exit" }),
  ]
}

function captureRows(I, home) {
  var dir = home + "/Pictures"
  var stamp = "$(date +%Y%m%d-%H%M%S)"
  return [
    row("shot-region", "Screenshot region", "grim + slurp", I.crop, { run: 'grim -g "$(slurp)" ' + dir + "/shot-" + stamp + ".png" }),
    row("shot-full", "Screenshot screen", "grim", I.monitor, { run: "grim " + dir + "/shot-" + stamp + ".png" }),
    row("shot-clip", "Screenshot region to clipboard", "grim + slurp + wl-copy", I.crop, { run: 'grim -g "$(slurp)" - | wl-copy' }),
  ]
}

function toggleRows(I, state) {
  return [
    row("awake", "Stay awake", state.awake ? "on — idle lock inhibited" : "off", I.eye, { toggle: "awake", checked: !!state.awake }),
  ]
}

function setupRows(I, home) {
  var c = home + "/.config/"
  function edit(id, name, path) {
    return row("edit-" + id, "Edit " + name, path.replace(home, "~"), I.pencil, { run: TERM + "nvim " + path, keywords: ["config", "edit"] })
  }
  return [
    edit("sway", "Sway config", c + "sway/config"),
    edit("qs", "Quickshell", c + "quickshell/shell.qml"),
    edit("ghostty", "Ghostty", c + "ghostty/config"),
    edit("zsh", "Zsh", c + "zsh/.zshrc"),
    edit("tmux", "Tmux", c + "tmux/tmux.conf"),
    edit("nvim", "Neovim", c + "nvim/init.lua"),
    row("wifi", "Wi-Fi", "nmtui", I.wifi4, { run: TERM + "nmtui" }),
    row("bt", "Bluetooth", "bluetoothctl", I.bluetooth, { run: TERM + "bluetoothctl" }),
  ]
}

function learnRows(I) {
  function web(id, name, url) {
    return row(id, name, url, I.web, { run: "librewolf " + url })
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
