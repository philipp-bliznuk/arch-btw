// Notification body text as the card renders it. The body is StyledText so
// the markup advertised by bodyMarkupSupported works, but StyledText honours
// <img src> and a remote src makes the shell issue an unauthenticated GET
// with no user action. Only tags on an allowlist reach the renderer; every
// other `<` is escaped before Qt sees it.
.pragma library

function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return ["chrom", "brave", "vivaldi", "microsoft-edge", "opera"].some(k => source.indexOf(k) >= 0)
}

// Chromium prefixes the body with the page origin (as a link or plain text).
// The bare form must carry a scheme or `www.`, or a leading `name.ext` word
// ("Node.js is ready") would go with it.
function sanitize(body, app, appIcon) {
  var text = String(body || "")
  if (!isChromiumDerived(app, appIcon)) return text
  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

// Tags that pass through verbatim, spelled the one way Qt recognises them.
// Each is a fixed string or an href whose value holds no quote, whitespace or
// angle bracket, so Qt reads exactly the characters matched here.
var allowed = [
  /^<\/?(?:b|i|u|s|em|strong|del|p)>$/,
  /^<br\s*\/?>$/,
  /^<a href=(["'])https?:\/\/[^"'<>\s]+\1>$/,
  /^<\/a>$/
]

// Re-serialise rather than mirror Qt's grammar. QQuickStyledText gives up on
// a tag before its `>` (an `=` with no name, an empty or mismatched quote)
// and resumes reading text one character later, so `<a ="x<img src=u>` is an
// image to Qt and one harmless tag to any scanner that runs to the `>`. Here
// a `<` either opens a tag on the allowlist, taken up to the next `>`, or
// becomes `&lt;` and the scan goes on from the next character, so a `<`
// nested in a rejected tag is judged on its own. Qt turns `&lt;` into text
// and never parses that text again.
function escapeTags(text) {
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
    var tag = close === -1 ? "" : text.slice(open, close + 1)
    if (allowed.some(re => re.test(tag))) {
      out += tag
      i = close + 1
    } else {
      out += "&lt;"
      i = open + 1
    }
  }
  return out
}

// Last thing to touch the string before Qt parses it. Allowed tags hold no
// `<`, so the `<br/>` the newline rewrite inserts cannot combine with
// anything into a tag the input never had.
function styled(body, app, appIcon) {
  return escapeTags(sanitize(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>"))
}
