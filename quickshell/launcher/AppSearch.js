// Ranked search over launcher rows { id, name, genericName, keywords }.
// Tiers (higher wins): exact > prefix > word-prefix > substring > fuzzy
// (subsequence). Named matches (every term hits the row's own name) rank
// above keyword/description hits, which rank above fuzzy ones; within a
// group frecency (Usage.js score) wins, then tier → shorter name → a-z.
.pragma library

var NAMED = 300 // per-term tier floor for exact/prefix/word-prefix on the name itself
var STRONG = 100 // per-term tier floor for exact/prefix/word/substring

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
  var nw = words(entry.name)
  for (var i = 0; i < nw.length; i++) if (nw[i].indexOf(term) === 0) return 350 - i
  var ws = words(entry.genericName).concat(words(keywordText(entry)))
  for (var j = 0; j < ws.length; j++) if (ws[j].indexOf(term) === 0) return 300 - j
  var hay = [name, text(entry.genericName), text(keywordText(entry)), id].join(" ")
  var at = hay.indexOf(term)
  if (at >= 0) return 200 - Math.min(at, 99)
  if (term.length >= 2 && subsequence(name, term)) return 100 - name.length
  return 0
}

// Returns { score, named, strong }. score 0 = no match; named = every term hit
// the name itself; strong = every term hit a substring-or-better tier.
function match(entry, query) {
  var terms = text(query).trim().split(/\s+/).filter(function (t) { return t })
  if (!terms.length) return { score: 1, named: true, strong: true }
  var total = 0
  var named = true
  var strong = true
  for (var i = 0; i < terms.length; i++) {
    var s = termScore(entry, terms[i])
    if (!s) return { score: 0, named: false, strong: false }
    if (s <= NAMED) named = false
    if (s <= STRONG) strong = false
    total += s
  }
  return { score: total, named: named, strong: strong }
}

function score(entry, query) {
  return match(entry, query).score
}

// usage: optional function(row) -> frecency number
function sorted(values, query, usage) {
  var q = String(query || "").trim()
  var rows = []
  for (var i = 0; i < values.length; i++) {
    var e = values[i]
    if (!e || !e.name) continue
    var m = match(e, q)
    if (!m.score) continue
    rows.push({ entry: e, score: m.score, named: m.named, strong: m.strong, use: usage ? usage(e) : 0, key: text(e.name) })
  }
  rows.sort(function (a, b) {
    if (q && a.named !== b.named) return a.named ? -1 : 1
    if (q && a.strong !== b.strong) return a.strong ? -1 : 1
    if (a.use !== b.use) return b.use - a.use
    if (q && a.score !== b.score) return b.score - a.score
    if (q && a.key.length !== b.key.length) return a.key.length - b.key.length
    return a.key < b.key ? -1 : a.key > b.key ? 1 : 0
  })
  return rows.map(function (r) { return r.entry })
}
