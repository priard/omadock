// Pure helpers for names the dock shows: an app's readable name, a pinned
// folder's name, a tooltip's workspace, a folder stack's counts. Plain JS
// with no Qt globals, so the node tests run it in a vm context like
// DockModel.js.

function _chars(s) { return Array.from(String(s == null ? "" : s)) }

// A name for an app without a desktop entry: the last part of its class id,
// words split on - and _, capitalised. "org.omarchy.terminal" -> "Terminal".
function prettyAppId(appId) {
  var s = String(appId == null ? "" : appId).trim()
  if (s === "") return ""
  if (/\.desktop$/i.test(s)) s = s.slice(0, -8)
  var parts = s.split(".")
  var last = parts[parts.length - 1] || s
  var words = last.split(/[-_\s]+/).filter(function(w) { return w !== "" })
  if (words.length === 0) return s
  return words.map(function(w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
}

// A pinned folder's own name; blank goes back to the directory's name.
// Bounded like DockModel.boundPinnedFolders (120 characters).
var MAX_FOLDER_LABEL = 120
function folderBaseName(path) {
  var p = String(path == null ? "" : path).replace(/\/+$/, "")
  if (p === "" || p === "~") return "Home"
  var parts = p.split("/")
  return parts[parts.length - 1] || "Folder"
}

function withFolderName(folders, path, name) {
  var list = folders || []
  var at = -1
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].path === path) { at = i; break }
  if (at < 0) return list
  var v = _chars(String(name == null ? "" : name).replace(/\s+/g, " ").trim()).slice(0, MAX_FOLDER_LABEL).join("")
  var next = list.slice()
  var entry = {}
  for (var k in list[at]) entry[k] = list[at][k]
  entry.name = v !== "" ? v : folderBaseName(path)
  next[at] = entry
  return next
}

// Rounds v to whole device pixels at output scale dpr.
function gridRound(v, dpr) { var d = dpr > 0 ? dpr : 1; return Math.round(v * d) / d }

// Compact workspace label for a tooltip: numbered workspaces only. Special
// workspaces have no number worth showing, so they get nothing.
function workspaceShort(wsId, wsName) {
  var name = String(wsName == null ? "" : wsName).trim()
  if (!name || name.indexOf("special:") === 0 || name === "special") return ""
  var num = Number(wsId)
  if (isNaN(num) || num < 0) {
    if (name.length <= 2 && !isNaN(Number(name)) && Number(name) >= 0) return name
    return ""
  }
  if (name.length <= 2) return name
  return String(wsId)
}

// Folder stack header count: "" for none, "N+" when the scan stopped at its
// budget (list-folder.py MAX_SCAN) and the folder holds more.
function stackCountLabel(count, truncated) {
  var n = Math.max(0, Math.floor(Number(count) || 0))
  if (n === 0) return ""
  return truncated ? n + "+" : String(n)
}

// Folder stack footer for entries not shown: "" when all are shown.
function stackMoreLabel(count, shown, truncated) {
  var rest = Math.max(0, Math.floor(Number(count) || 0) - Math.floor(Number(shown) || 0))
  if (rest === 0) return ""
  return "+ " + rest + (truncated ? "+" : "") + " more"
}
