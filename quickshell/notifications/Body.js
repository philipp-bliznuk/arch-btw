// Notification body text as the card renders it. The body is StyledText so
// the markup advertised by bodyMarkupSupported works, but StyledText honours
// <img src> and a remote src makes the shell issue an unauthenticated GET
// with no user action. Image tags go before the renderer sees them.
.pragma library

function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return ["chrom", "brave", "vivaldi", "microsoft-edge", "opera"].some(k => source.indexOf(k) >= 0)
}

// Tag name read the way Qt's parser reads it: after `<`, skip everything up
// to the first run of letters and digits. QQuickStyledText skips
// QChar::isSpace(), which is not `\s` (Qt counts U+0085 NEL, `\s` does not),
// so no separator class is matched; over-skipping only ever classifies more
// runs as images, and dropping a run cannot manufacture a tag.
function isImageTag(tag) {
  var name = /^<[^A-Za-z0-9]*([A-Za-z0-9]+)/.exec(tag)
  return !!name && name[1].toLowerCase() === "img"
}

// Whole tags only, never substrings of one. A `<` opens a tag that runs to
// the next `>`, nested `<` and all, and only a tag named `img` is dropped.
// A naive /<img[^>]*>/g is unsafe: removing the inner match from
// `<im<img src=a>g src=b>` closes the halves into a live `<img src=b>` the
// input never contained. Qt lets `>` inside a quoted attribute pass; taking
// the shorter run here only ever splits one Qt tag into several, which can
// expose an `<img` to drop, never hide one. Since every `<` opens a tag, text
// between tags holds none, so one pass is enough.
function stripImageTags(text) {
  var out = ""
  var i = 0
  while (i < text.length) {
    var open = text.indexOf("<", i)
    if (open === -1) {
      out += text.slice(i)
      break
    }
    out += text.slice(i, open)
    var close = text.indexOf(">", open)
    var tag = close === -1 ? text.slice(open) : text.slice(open, close + 1)
    if (!isImageTag(tag)) out += tag
    i = close === -1 ? text.length : close + 1
  }
  return out
}

// Chromium prefixes the body with the page origin (as a link or plain text).
function sanitize(body, app, appIcon) {
  var text = stripImageTags(String(body || ""))
  if (!isChromiumDerived(app, appIcon)) return text
  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

// Last thing to touch the string before Qt parses it. The newline rewrite
// inserts `<br/>` into text stripImageTags chose to keep, and a kept tag may
// hold a `<` of its own (`<x`, newline, `<img src=...>` is one tag named `x`
// until the rewrite splits it), so strip again after.
function styled(body, app, appIcon) {
  return stripImageTags(sanitize(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>"))
}
