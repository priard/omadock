// Tiling-place arithmetic: the dock's geometry reasoning, as pure functions.
//
// Plain JS with no Qt globals, so the unit tests run it in the same vm context as
// DockModel.js, SettingsSearch.js and Buttons.js. What lives here is only what can be
// decided from data: hyprctl's client list in, the exchange plan out. Everything that
// talks to the compositor stays in the dock.
//
// The dock records the rectangle of every window of a workspace before parking one, and
// on restore it has to put each window back into the rectangle it came from. Hyprland
// re-inserts a parked window as a new tiling window, so the assignment comes back
// permuted (measured on 0.56.2: the rectangles are often the same set, with the wrong
// window in each slot) or, when the tree changed shape, the rectangles themselves differ.
// The first case is a sort; the second is not doable with exchanges and is handed back
// as an empty plan.

var RECT_TOLERANCE = 4        // a tiling rectangle is "the same" within a few pixels
var OCCUPY_SHARE = 0.6        // how much of a rectangle a window must cover to own it

// Hyprland addresses come as "0xabc" or "abc" depending on the call site; everything
// keyed by address goes through here so the two spellings can never diverge.
function normalizeAddress(value) {
  var text = String(value == null ? "" : value).trim()
  if (!text) return ""
  if (text.slice(0, 2) === "0x" || text.slice(0, 2) === "0X") text = text.slice(2)
  return "0x" + text.toLowerCase()
}

// hyprctl -j clients, as a map by address. Quickshell's per-toplevel ipc object only
// carries at/size for windows that existed when the shell started, which is why the
// dock asks Hyprland itself.
function parseClientRects(text) {
  var map = {}
  var list = null
  try {
    list = JSON.parse(String(text == null ? "" : text))
  } catch (e) {
    return map
  }
  if (!Array.isArray(list)) return map
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c || !c.address || !c.at || !c.size) continue
    map[normalizeAddress(c.address)] = {
      x: Number(c.at[0]),
      y: Number(c.at[1]),
      w: Number(c.size[0]),
      h: Number(c.size[1]),
      workspace: c.workspace ? String(c.workspace.name || c.workspace.id) : ""
    }
  }
  return map
}

function rectFor(rects, address) {
  if (!address) return null
  var rect = (rects || {})[normalizeAddress(address)]
  return rect ? rect : null
}

function windowCountOnWorkspace(rects, workspace) {
  var count = 0
  var map = rects || {}
  for (var k in map) if (String(map[k].workspace) === String(workspace)) count++
  return count
}

// Windows on a workspace in visual order - left to right, then top to bottom, which is
// the order dwindle tiles them in.
function windowsOnWorkspace(rects, workspace) {
  var out = []
  var map = rects || {}
  for (var k in map) {
    if (String(map[k].workspace) !== String(workspace)) continue
    out.push({ address: k, rect: map[k] })
  }
  out.sort(function(a, b) { return (a.rect.x - b.rect.x) || (a.rect.y - b.rect.y) })
  return out
}

function rectsClose(a, b) {
  if (!a || !b) return false
  return Math.abs(a.x - b.x) <= RECT_TOLERANCE && Math.abs(a.y - b.y) <= RECT_TOLERANCE
    && Math.abs(a.w - b.w) <= RECT_TOLERANCE && Math.abs(a.h - b.h) <= RECT_TOLERANCE
}

function overlapArea(a, b) {
  if (!a || !b) return 0
  var w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
  var h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
  return (w > 0 && h > 0) ? w * h : 0
}

// The recorded window that belongs in this rectangle, "" when none does: that is the
// signal that the tree changed shape and no exchange can fix it.
function ownerOfRect(layout, rect) {
  for (var k in (layout || {})) {
    if (rectsClose(layout[k], rect)) return k
  }
  return ""
}

// The window standing in a recorded rectangle right now. Only a window that really
// stands in it counts: once the tree took another shape, several windows merely graze
// the rectangle and trading places with one of them just cycles.
function occupantOfRect(rows, rect, exceptAddress) {
  if (!rect) return ""
  var area = rect.w * rect.h
  var best = 0
  var found = ""
  for (var i = 0; i < (rows || []).length; i++) {
    if (!rows[i] || rows[i].address === exceptAddress) continue
    var ov = overlapArea(rows[i].rect, rect)
    if (ov > best) {
      best = ov
      found = rows[i].address
    }
  }
  return (area > 0 && best > OCCUPY_SHARE * area) ? found : ""
}

// The state of a workspace as one string, to notice an exchange that undoes a previous
// one instead of getting closer.
function rectSignature(rows) {
  var parts = []
  for (var i = 0; i < (rows || []).length; i++) {
    parts.push(rows[i].address + ":" + rows[i].rect.x + "," + rows[i].rect.y
      + "," + rows[i].rect.w + "," + rows[i].rect.h)
  }
  return parts.join("|")
}

// The first window, in visual order, that is not in the rectangle it was parked in.
function firstWrongRect(rows, layout) {
  var want = layout || {}
  for (var i = 0; i < (rows || []).length; i++) {
    var expected = want[rows[i].address]
    if (expected && !rectsClose(rows[i].rect, expected)) return rows[i].address
  }
  return ""
}

// The exchanges that put every window back into the rectangle it was parked in. The
// plan is sorted with n-1 exchanges of a permutation, computed: no searching, and no
// way to cycle. Empty when some rectangle has no owner, i.e. the tree changed shape.
function slotSwapPlan(rows, layout) {
  rows = rows || []
  var desired = []
  for (var i = 0; i < rows.length; i++) {
    var owner = ownerOfRect(layout, rows[i].rect)
    if (!owner) return []
    desired.push(owner)
  }
  var current = rows.slice()
  var plan = []
  for (var p = 0; p < current.length; p++) {
    if (current[p].address === desired[p]) continue
    var j = -1
    for (var q = p + 1; q < current.length; q++) {
      if (current[q].address === desired[p]) { j = q; break }
    }
    if (j < 0) return []
    plan.push([current[p].address, current[j].address])
    var swap = current[p]
    current[p] = current[j]
    current[j] = swap
  }
  return plan
}

// The effect of a plan, for tests and for reasoning. `swapwindow` trades *places*: the
// rectangles stay where they are and the two windows exchange them, so the simulation
// exchanges the rectangles, not the array positions (getting this wrong is invisible in
// the dock - it only dispatches - but it is exactly what a test has to catch).
function applyPlan(rows, plan) {
  var out = rows.map(function(r) { return { address: r.address, rect: r.rect } })
  for (var i = 0; i < (plan || []).length; i++) {
    var a = -1
    var b = -1
    for (var k = 0; k < out.length; k++) {
      if (out[k].address === plan[i][0]) a = k
      if (out[k].address === plan[i][1]) b = k
    }
    if (a < 0 || b < 0) continue
    var place = out[a].rect
    out[a].rect = out[b].rect
    out[b].rect = place
  }
  return out
}
