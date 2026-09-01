.pragma library

// Pure helpers shared by Service.qml and Panel.qml. No QML types in here, so
// tests/model.test.js can run the whole thing under plain node.

var POSITIONS = ["top-left", "top-center", "top-right",
                 "middle-left", "center", "middle-right",
                 "bottom-left", "bottom-center", "bottom-right"]
var SIZES = ["small", "medium", "large"]

// The Twitch application this plugin signs in with. A Client ID is a public
// identifier, not a secret, so it ships with the plugin and nobody installing
// it has to register anything. The manifest carries the same value so the
// settings UI pre-fills it; a non-empty setting overrides it.
var TWITCH_CLIENT_ID = "u3epf2jrp7sqavp6k2doutc0e37c9t"

function twitchClientId(override) {
  var value = String(override || "").trim()
  return value === "" ? TWITCH_CLIENT_ID : value
}

// Settings and catalogues reach QML as `var` properties, and a list that came
// through the config parser arrives array-LIKE rather than as a true Array, so
// Array.isArray on it is false. Normalise before touching anything.
function arrayValues(value) {
  if (Array.isArray(value)) return value
  if (!value || typeof value !== "object") return []
  var length = Number(value.length)
  if (!isFinite(length) || length < 0 || length > 100000) return []
  var out = []
  for (var i = 0; i < length; i++) out.push(value[i])
  return out
}

function normalizeIds(value) {
  var seen = {}
  var out = []
  var list = arrayValues(value)
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] || "").trim()
    if (id === "" || seen[id]) continue
    seen[id] = true
    out.push(id)
  }
  return out.sort()
}

function sameArray(left, right) {
  return JSON.stringify(normalizeIds(left)) === JSON.stringify(normalizeIds(right))
}

function toggleSelection(list, id) {
  var next = normalizeIds(list)
  var index = next.indexOf(String(id))
  if (index === -1) next.push(String(id))
  else next.splice(index, 1)
  return normalizeIds(next)
}

// Case- and punctuation-insensitive so "ltt" finds "Linus Tech Tips" and
// "@dhh37" finds the handle without the user matching the leading @.
function matchesQuery(channel, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return true
  var haystack = [channel.name, channel.login, channel.handle, channel.id]
    .join(" ").toLowerCase()
  var words = needle.split(/\s+/)
  for (var i = 0; i < words.length; i++) {
    if (haystack.indexOf(words[i].replace(/^@/, "")) === -1) return false
  }
  return true
}

function channelKey(channel) {
  return String((channel || {}).login || (channel || {}).id || "")
}

function filterChannels(channels, query, selected, selectedOnly) {
  var list = arrayValues(channels)
  var picked = normalizeIds(selected)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var channel = list[i]
    if (selectedOnly && picked.indexOf(channelKey(channel)) === -1) continue
    if (!matchesQuery(channel, query)) continue
    out.push(channel)
  }
  return out
}

// Enabled channels first, so the ones that actually alert stay in view while
// filtering a list that can run to a thousand subscriptions.
function sortForPicker(channels, selected) {
  var picked = normalizeIds(selected)
  return arrayValues(channels).slice().sort((a, b) => {
    var aOn = picked.indexOf(channelKey(a)) !== -1
    var bOn = picked.indexOf(channelKey(b)) !== -1
    if (aOn !== bOn) return aOn ? -1 : 1
    return String(a.name || "").toLowerCase() < String(b.name || "").toLowerCase() ? -1 : 1
  })
}

function clampInterval(value) {
  var seconds = parseInt(String(value === undefined || value === null ? 300 : value), 10)
  if (!isFinite(seconds)) seconds = 300
  return Math.max(60, Math.min(3600, seconds))
}

// `pw-play` expects a stream volume from 0 through 1, while the user-facing
// setting and slider use an unambiguous percentage.
// biome-ignore lint/correctness/noUnusedVariables: Panel.qml and Service.qml call this library export.
function normalizeChimeVolume(value) {
  var percent = Number(value === undefined || value === null || value === "" ? 100 : value)
  if (!isFinite(percent)) percent = 100
  return Math.max(0, Math.min(100, percent)) / 100
}

function normalizePosition(value) {
  return POSITIONS.indexOf(String(value)) === -1 ? "bottom-right" : String(value)
}

function normalizeSize(value) {
  return SIZES.indexOf(String(value)) === -1 ? "medium" : String(value)
}

function isPip(clickAction) {
  return String(clickAction || "").toLowerCase().indexOf("picture") === 0
}

// biome-ignore lint/correctness/noUnusedVariables: Panel.qml calls this library export.
function relativeTime(value, nowMs) {
  var then = new Date(String(value || "")).getTime()
  if (!isFinite(then)) return ""
  var seconds = Math.max(0, Math.floor(((nowMs || Date.now()) - then) / 1000))
  if (seconds < 60) return "just now"
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`
  if (seconds < 7 * 86400) return `${Math.floor(seconds / 86400)}d ago`
  return `${Math.floor(seconds / (7 * 86400))}w ago`
}

// biome-ignore lint/correctness/noUnusedVariables: Panel.qml calls this library export.
function liveFor(value, nowMs) {
  var then = new Date(String(value || "")).getTime()
  if (!isFinite(then)) return ""
  var minutes = Math.max(0, Math.floor(((nowMs || Date.now()) - then) / 60000))
  if (minutes < 60) return `${minutes}m`
  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`
}

function compactCount(value) {
  var count = parseInt(String(value || 0), 10) || 0
  if (count < 1000) return String(count)
  if (count < 1000000) return `${(count / 1000).toFixed(count < 10000 ? 1 : 0)}K`
  return `${(count / 1000000).toFixed(1)}M`
}

// One chime per batch per source: ten uploads landing together should not
// queue ten overlapping sounds.
// biome-ignore lint/correctness/noUnusedVariables: Service.qml calls this library export.
function soundsForBatch(fresh) {
  var i
  var kinds = {}
  var list = arrayValues(fresh)
  for (i = 0; i < list.length; i++) kinds[String(list[i].kind || "")] = true
  var out = []
  if (kinds["youtube"]) out.push("youtube")
  if (kinds["twitch"]) out.push("twitch")
  return out
}

function notificationTitle(item) {
  var name = String((item || {}).channelName || "Channel")
  return (item || {}).kind === "twitch" ? `${name} is live` : name
}

function notificationBody(item) {
  var entry = item || {}
  var title = String(entry.title || "")
  if (entry.kind !== "twitch") return title
  var parts = []
  if (title) parts.push(title)
  var meta = []
  if (entry.game) meta.push(String(entry.game))
  if (entry.viewers) meta.push(`${compactCount(entry.viewers)} watching`)
  if (meta.length) parts.push(meta.join(" · "))
  return parts.join("\n")
}

// biome-ignore lint/correctness/noUnusedVariables: Service.qml calls this library export.
function notifyCommand(helper, item, options) {
  var settings = options || {}
  var command = [helper,
    "--title", notificationTitle(item),
    "--body", notificationBody(item),
    "--url", String((item || {}).url || ""),
    "--default", isPip(settings.clickAction) ? "pip" : "browser",
    "--timeout", String(Math.max(0, parseInt(String(settings.timeoutSec || 12), 10) || 0) * 1000),
    "--pip-position", normalizePosition(settings.pipPosition),
    "--pip-size", normalizeSize(settings.pipSize)]
  if ((item || {}).avatar) command.push("--icon", String(item.avatar))
  if ((item || {}).kind === "twitch") command.push("--urgency", "critical")
  return command
}

// Merge a check result into the feed without letting it grow without bound, and
// without losing an item that has scrolled out of the source's current window.
// biome-ignore lint/correctness/noUnusedVariables: Service.qml calls this library export.
function mergeFeed(existing, incoming, limit) {
  var seen = {}
  var out = []
  var lists = [arrayValues(incoming), arrayValues(existing)]
  var listIndex
  var list
  var itemIndex
  var item
  var key
  for (listIndex = 0; listIndex < lists.length; listIndex++) {
    list = lists[listIndex]
    for (itemIndex = 0; itemIndex < list.length; itemIndex++) {
      item = list[itemIndex]
      key = `${String(item.kind || "")}:${String(item.id || "")}`
      if (seen[key]) {
        continue
      }
      seen[key] = true
      out.push(item)
    }
  }
  out.sort((a, b) => String(b.publishedAt || "").localeCompare(String(a.publishedAt || "")))
  return out.slice(0, limit || 80)
}
