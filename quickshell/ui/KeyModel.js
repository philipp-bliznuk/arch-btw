// Vim key dispatch shared by the launcher and panel popups. Turns a Qt key
// event into an action name; callers decide what the action means.
//
// insert(event, hasText)  - a text field owns typing; only Ctrl combos and
//                           navigation keys map. "" = let the field have it.
// normal(event)           - plain letters. Handles the `gg` prefix itself.
//
// Actions: up down halfUp halfDown top bottom activate left right back
//          escape close insert copy paste delete deleteWord clear nextChip
//          prevChip jump:N. Popup-specific letters live in each PopupCard
//          keymap instead.
.pragma library

var pendingG = false

function ctrl(e) { return (e.modifiers & Qt.ControlModifier) !== 0 }
function shift(e) { return (e.modifiers & Qt.ShiftModifier) !== 0 }
function plain(e) { return (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0 }

var SHARED = {}
SHARED[Qt.Key_Up] = "up"
SHARED[Qt.Key_Down] = "down"
SHARED[Qt.Key_PageUp] = "halfUp"
SHARED[Qt.Key_PageDown] = "halfDown"
SHARED[Qt.Key_Home] = "top"
SHARED[Qt.Key_End] = "bottom"
SHARED[Qt.Key_Return] = "activate"
SHARED[Qt.Key_Enter] = "activate"
SHARED[Qt.Key_Left] = "left"
SHARED[Qt.Key_Right] = "right"
SHARED[Qt.Key_Escape] = "escape"
SHARED[Qt.Key_Tab] = "nextChip"
SHARED[Qt.Key_Backtab] = "prevChip"
SHARED[Qt.Key_Delete] = "delete"

var CTRL = {}
CTRL[Qt.Key_N] = "down"
CTRL[Qt.Key_J] = "down"
CTRL[Qt.Key_P] = "up"
CTRL[Qt.Key_K] = "up"
CTRL[Qt.Key_D] = "halfDown"
CTRL[Qt.Key_L] = "right"
CTRL[Qt.Key_H] = "back"
CTRL[Qt.Key_Y] = "copy"
CTRL[Qt.Key_W] = "deleteWord"

var NORMAL = {}
NORMAL[Qt.Key_J] = "down"
NORMAL[Qt.Key_K] = "up"
NORMAL[Qt.Key_H] = "left"
NORMAL[Qt.Key_L] = "right"
NORMAL[Qt.Key_Y] = "copy"
NORMAL[Qt.Key_P] = "paste"
NORMAL[Qt.Key_D] = "delete"
NORMAL[Qt.Key_X] = "delete"
NORMAL[Qt.Key_Slash] = "insert"
NORMAL[Qt.Key_I] = "insert"
NORMAL[Qt.Key_Q] = "close"
NORMAL[Qt.Key_Space] = "activate"

var NORMAL_SHIFT = {}
NORMAL_SHIFT[Qt.Key_G] = "bottom"
NORMAL_SHIFT[Qt.Key_Backtab] = "prevChip"

function insert(e, hasText) {
  if (SHARED[e.key] !== undefined && plain(e)) return SHARED[e.key]
  if (e.key === Qt.Key_Backspace && !hasText && plain(e)) return "back"
  if (!ctrl(e)) return ""
  if (e.key === Qt.Key_U) return hasText ? "clear" : "halfUp"
  return CTRL[e.key] || ""
}

function normal(e) {
  if (SHARED[e.key] !== undefined && plain(e)) { pendingG = false; return SHARED[e.key] }
  if (ctrl(e)) { pendingG = false; return CTRL[e.key] || "" }
  if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9 && !shift(e)) { pendingG = false; return "jump:" + (e.key - Qt.Key_0) }
  if (e.key === Qt.Key_G) {
    if (shift(e)) { pendingG = false; return "bottom" }
    if (pendingG) { pendingG = false; return "top" }
    pendingG = true
    return ""
  }
  pendingG = false
  if (shift(e)) return NORMAL_SHIFT[e.key] || ""
  return NORMAL[e.key] || ""
}

// Clamp helpers so every caller moves the cursor the same way.
function move(index, count, delta) {
  if (count <= 0) return 0
  return Math.max(0, Math.min(count - 1, index + delta))
}

function step(action, index, count, pageSize) {
  switch (action) {
  case "up": return move(index, count, -1)
  case "down": return move(index, count, 1)
  case "halfUp": return move(index, count, -pageSize)
  case "halfDown": return move(index, count, pageSize)
  case "top": return 0
  case "bottom": return Math.max(0, count - 1)
  }
  if (action.indexOf("jump:") === 0) return move(0, count, parseInt(action.slice(5)) - 1)
  return -1
}
