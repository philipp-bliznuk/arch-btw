// Ranked search over launcher rows { id, name, genericName, keywords, comment }.
// Tiers (higher wins): exact > prefix > word-prefix > substring > fuzzy
// (subsequence). Equal tier → frecency (Usage.js score) → shorter name → a-z.
.pragma library

function text(v) {
  return String(v || "").toLowerCase()
}

function keywordText(entry) {
  var k = entry && entry.keywords
  if (!k) return ""
  try {
    return typeof k.join === "function" ? k.join(" ") : String(k)
  } catch (e) {
    return ""
  }
}

function words(s) {
  return text(s).replace(/([a-z0-9])([A-Z])/g, "$1 $2").split(/[^a-z0-9]+/).filter(function (w) { return w })
}

function subsequence(hay, needle) {
  var i = 0
  for (var j = 0; j < hay.length && i < needle.length; j++) if (hay[j] === needle[i]) i++
  return i === needle.length
}

// Score one term against one entry. 0 = no match.
function termScore(entry, term) {
  var name = text(entry.name)
  var id = text(entry.id)
  if (name === term || id === term) return 500
  if (name.indexOf(term) === 0) return 400 - name.length
  var ws = words(entry.name).concat(words(entry.genericName), words(keywordText(entry)))
  for (var i = 0; i < ws.length; i++) if (ws[i].indexOf(term) === 0) return 300 - i
  var hay = [name, text(entry.genericName), text(entry.comment), text(keywordText(entry)), id].join(" ")
  var at = hay.indexOf(term)
  if (at >= 0) return 200 - Math.min(at, 99)
  if (term.length >= 2 && subsequence(name, term)) return 100 - name.length
  return 0
}

function score(entry, query) {
  var terms = text(query).trim().split(/\s+/).filter(function (t) { return t })
  if (!terms.length) return 1
  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var s = termScore(entry, terms[i])
    if (!s) return 0
    total += s
  }
  return total
}

// usage: optional function(id) -> frecency number
function sorted(values, query, usage) {
  var q = String(query || "").trim()
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (!e || !e.name) continue
    var s = score(e, q)
    if (!s) continue
    rows.push({ entry: e, score: s, use: usage ? usage(e.id) : 0, key: text(e.name) })
  }
  rows.sort(function (a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.use !== b.use) return b.use - a.use
    if (q && a.key.length !== b.key.length) return a.key.length - b.key.length
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0
  })
  return rows.map(function (r) { return r.entry })
}
