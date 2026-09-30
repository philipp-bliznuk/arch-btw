// Frecency for launcher rows, persisted by Launcher.qml via FileView as
// ~/.local/state/qs/launcher-usage.json: { id: { n: count, t: lastMs } }.
// score = n * decay, decay halves every 7 days.
.pragma library

var HALF_LIFE = 7 * 86400000

function parse(json) {
  try {
    var v = JSON.parse(json || "{}")
    return v && typeof v === "object" ? v : {}
  } catch (e) {
    return {}
  }
}

function bump(data, id) {
  var next = {}
  for (var k in data) next[k] = data[k]
  var cur = next[id] || { n: 0, t: 0 }
  next[id] = { n: cur.n + 1, t: Date.now() }
  return prune(next)
}

function prune(data) {
  var ids = Object.keys(data)
  if (ids.length <= 200) return data
  ids.sort(function (a, b) { return score(data, b) - score(data, a) })
  var out = {}
  for (var i = 0; i < 150; i++) out[ids[i]] = data[ids[i]]
  return out
}

function score(data, id) {
  var e = data[id]
  if (!e) return 0
  return e.n * Math.pow(0.5, (Date.now() - e.t) / HALF_LIFE)
}
