// Developer task and command completion HUD: models and state transitions.
//
// Plain JS with no Qt globals, so unit tests run it in the same vm context as
// DockModel.js, Plan.js, Buttons.js and SettingsSearch.js.
//
// Every id SPELLING is owned by DockModel (`stripDesktop` and `cliAppId`'s one
// table), passed in as `ids` because a root JS module imports nothing: there is
// no second alias table and no second `.desktop` strip in this file.
//
// The one rule that stays here is isSameApp, and it is narrower than the
// model's matcher on purpose. A task must attach to exactly ONE tile, so a task
// filed for `ghostty` may not badge `ghostty-gui`; DockModel.isAppMatch widens
// the comparison with candidate tokens (`ghostty-gui` -> `ghostty`) because a
// notification arrives under partial ids, and measured against the task path
// that widening re-introduced the `foot`/`footclient` class of bleed. Both
// rules agree on every reverse-DNS pair, which is where the two paths meet.

var MAX_TASK_TITLE = 120
var MAX_TASK_STATUS_ENTRIES = 64

function normalizeTaskStatus(ids, appId, status, exitCode, title, duration) {
  var rawId = String(appId || "").trim()
  if (!rawId) return null
  var primary = rawId
  var fallback = ""
  if (rawId.indexOf("|") >= 0) {
    var parts = rawId.split("|")
    primary = ids.cliAppId(parts[0])
    fallback = ids.cliAppId(parts[1])
  } else {
    primary = ids.cliAppId(rawId)
  }
  if (!primary && !fallback) return null
  var id = primary || fallback

  var st = String(status || "").toLowerCase().trim()
  var code = Math.round(Number(exitCode))
  if (!isFinite(code)) code = 0

  var resolved = "success"
  var progress = 0
  if (st === "error" || st === "fail" || st === "failed") {
    resolved = "error"
  } else if (st === "running" || st === "run" || st === "busy") {
    resolved = "running"
  } else if (st === "privacy" || st === "mic" || st === "record" || st === "recording") {
    resolved = "privacy"
  } else if (st === "progress" || st === "download" || st === "downloading" || st.indexOf("progress:") === 0) {
    resolved = "progress"
    var p = code
    if (st.indexOf(":") >= 0) {
      var parsed = Math.round(Number(st.split(":")[1]))
      if (isFinite(parsed) && parsed > 0) p = parsed
    }
    progress = Math.max(0, Math.min(100, Math.round(Number(p) || 0)))
  } else if (st === "done" || st === "completed" || st === "finish" || st === "finished" || st === "success" || st === "ok") {
    resolved = (code === 0) ? "success" : "error"
  } else {
    resolved = (code === 0) ? "success" : "error"
  }

  var ttl = String(title || "").trim().slice(0, MAX_TASK_TITLE)
  var dur = Math.max(0, Math.round(Number(duration) || 0))

  return {
    appId: id,
    fallbackId: fallback,
    status: resolved,
    exitCode: code,
    title: ttl,
    duration: dur,
    progress: progress
  }
}

function withTaskStatus(ids, map, appId, taskObj) {
  var out = {}
  for (var k in (map || {})) out[k] = map[k]
  var id = ids.cliAppId(appId)
  if (!id && taskObj) id = taskObj.appId
  if (!id) return out
  if (!taskObj) {
    delete out[id]
    return out
  }
  out[id] = taskObj
  var keys = Object.keys(out)
  if (keys.length > MAX_TASK_STATUS_ENTRIES) {
    delete out[keys[0]]
  }
  return out
}

// The same id, or a reverse-DNS id and its bare name - and nothing else. See
// the header for why this is not DockModel.isAppMatch.
function isSameApp(ids, idA, idB) {
  if (!idA || !idB) return false
  var a = ids.cliAppId(idA).toLowerCase()
  var b = ids.cliAppId(idB).toLowerCase()
  if (a === b) return true
  return a.length > b.length ? a.endsWith("." + b) : b.endsWith("." + a)
}

function hasDockApp(ids, dockModel, targetId) {
  if (!dockModel || !targetId) return false
  var list = (dockModel.pinned || []).concat(dockModel.running || [])
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (entry && (entry.appId === targetId || entry.id === targetId || isSameApp(ids, entry.appId || entry.id, targetId))) {
      return true
    }
  }
  return false
}

function clearTaskStatusFor(ids, map, appId) {
  var out = {}
  for (var k in (map || {})) out[k] = map[k]
  var id = ids.cliAppId(appId)
  if (!id) return out
  delete out[id]
  for (var key in out) {
    var entry = out[key]
    if (key === id || isSameApp(ids, key, id) || (entry && (isSameApp(ids, entry.appId, id) || isSameApp(ids, entry.fallbackId, id)))) {
      delete out[key]
    }
  }
  return out
}

function taskStatusFor(ids, map, appId, dockModel) {
  if (!map || typeof map !== "object") return null
  var id = ids.cliAppId(appId)
  if (!id) return null

  // Pass 1: exact or alias match on primary appId
  if (map[id]) return map[id]
  for (var key in map) {
    var entry = map[key]
    if (entry && isSameApp(ids, entry.appId || key, id)) return entry
  }

  // Pass 2: match on fallbackId if primary is not present on the dock
  for (var key2 in map) {
    var entry2 = map[key2]
    if (entry2 && entry2.fallbackId && isSameApp(ids, entry2.fallbackId, id)) {
      if (!dockModel || !hasDockApp(ids, dockModel, entry2.appId)) {
        return entry2
      }
    }
  }

  return null
}

// The one owner of a task's look: the badge on the tile (resolveBadgeView) and
// the hover chip's dot (DockItem.qml) both read these, so the two surfaces
// cannot disagree about what a status looks like.
var TASK_GLYPH = {
  running: "●",
  success: "✓",
  error: "!",
  progress: "↓",
  media: "󰎆",
  privacy: "󰍬"
}
var TASK_COLOR = {
  running: "#89b4fa",
  success: "#a6e3a1",
  error: "#f38ba8",
  progress: "#89b4fa",
  media: "#cba6f7",
  privacy: "#fab387"
}

function statusGlyph(status) { return TASK_GLYPH[status] || "" }

// An unknown status has no colour of its own: "transparent" is what the badge
// already treats as "nothing to draw", so the chip's dot and the badge's fill
// agree even on a status neither of them knows.
function statusColor(status) { return TASK_COLOR[status] || "transparent" }

// What the hover chip says: what ran, how long it took, why it failed, and what
// media or privacy services are active.
function chipLabel(taskInfo, mediaInfo, privacyInfo) {
  var parts = []
  if (taskInfo) {
    var title = taskInfo.title ? taskInfo.title : (taskInfo.status === "error" ? "Task failed" : (taskInfo.status === "privacy" ? "Microphone active" : "Task completed"))
    if (taskInfo.status === "progress" && taskInfo.progress > 0) {
      parts.push(title + " (" + taskInfo.progress + "%)")
    } else {
      var dur = taskInfo.duration > 0 ? " (" + taskInfo.duration + "s)" : ""
      var code = (taskInfo.status === "error" && taskInfo.exitCode !== 0) ? " [Exit " + taskInfo.exitCode + "]" : ""
      parts.push(title + dur + code)
    }
  }
  if (privacyInfo && privacyInfo.active) {
    parts.push(privacyInfo.label ? privacyInfo.label : "Microphone active")
  }
  if (mediaInfo && mediaInfo.isPlaying) {
    var track = (mediaInfo.trackTitle || mediaInfo.title || "").trim()
    var artist = (mediaInfo.trackArtist || mediaInfo.artist || "").trim()
    if (track && artist) {
      parts.push("🎵 " + track + " — " + artist)
    } else if (track) {
      parts.push("🎵 " + track)
    } else {
      parts.push("🎵 Now playing")
    }
  }
  return parts.join(" · ")
}

function resolveBadgeStack(notificationCount, taskInfo, activeMatch, mediaInfo, privacyInfo) {
  var notif = Math.max(0, Math.round(Number(notificationCount) || 0))
  var candidates = []

  // 1. Task error: highest priority
  if (taskInfo && taskInfo.status === "error") {
    candidates.push({
      priority: 10,
      glyph: statusGlyph("error"),
      color: statusColor("error"),
      count: 0,
      mode: "status",
      status: "error"
    })
  }

  // 2. Microphone / privacy active
  if ((privacyInfo && privacyInfo.active) || (taskInfo && taskInfo.status === "privacy")) {
    candidates.push({
      priority: 9,
      glyph: statusGlyph("privacy"),
      color: statusColor("privacy"),
      count: 0,
      mode: "status",
      status: "privacy"
    })
  }

  // 3. Unread notification count
  if (notif > 0) {
    candidates.push({
      priority: 8,
      glyph: "",
      color: "transparent",
      count: notif,
      mode: "count",
      status: ""
    })
  }

  // 4. Running task or task progress
  if (taskInfo && (taskInfo.status === "running" || taskInfo.status === "progress")) {
    var st = taskInfo.status
    var gl = (st === "progress" && taskInfo.progress > 0) ? (taskInfo.progress + "%") : statusGlyph(st)
    candidates.push({
      priority: 7,
      glyph: gl,
      color: statusColor(st),
      count: 0,
      mode: "status",
      status: st
    })
  }

  // 5. Media playing
  if (mediaInfo && mediaInfo.isPlaying) {
    candidates.push({
      priority: 6,
      glyph: statusGlyph("media"),
      color: statusColor("media"),
      count: 0,
      mode: "status",
      status: "media"
    })
  }

  // 6. Task success (transient done indicator)
  if (taskInfo && taskInfo.status === "success") {
    candidates.push({
      priority: 5,
      glyph: statusGlyph("success"),
      color: statusColor("success"),
      count: 0,
      mode: "status",
      status: "success"
    })
  }

  candidates.sort(function(a, b) { return b.priority - a.priority })

  var primary = candidates.length > 0 ? candidates[0] : { glyph: "", color: "transparent", count: 0, mode: "none", status: "" }
  var secondary = candidates.length > 1 ? candidates[1] : null

  return {
    primary: primary,
    secondary: secondary
  }
}

function resolveBadgeView(notificationCount, taskInfo, activeMatch, mediaInfo, privacyInfo) {
  return resolveBadgeStack(notificationCount, taskInfo, activeMatch, mediaInfo, privacyInfo).primary
}
