// Keyed rows for the dock's Repeaters (KeyedListModel), with a leaving
// state: a key that is no longer wanted stays in the model, marked leaving,
// until its exit animation ends (DockMotion base), so its delegate can
// narrow and fade instead of vanishing in one frame. Plain JS with no Qt
// globals, so the node tests run it in a vm context like DockLabels.js.
//
// A row is { key, leaving, fresh, slot, leaveAt }. fresh: the key was not in
// the model before (and this is not the first sync), so its delegate grows
// in. slot: its position among the live (not leaving) rows, which is what
// label slots and home centres use.

function _slots(rows) {
  var live = 0
  for (var i = 0; i < rows.length; i++) {
    rows[i].slot = live
    if (!rows[i].leaving) live++
  }
  return rows
}

// The rows after a change: the wanted keys in order, and every row no longer
// wanted kept (leaving) right after the row that preceded it before. With
// exitMs <= 0 nothing lingers.
function target(rows, want, initial, now, exitMs) {
  var prev = rows || []
  var wantList = want || []
  var wanted = {}
  for (var w = 0; w < wantList.length; w++) wanted[wantList[w]] = true
  var had = {}
  for (var p = 0; p < prev.length; p++) had[prev[p].key] = true
  // A key wanted twice is one row (two identical buttons are one button).
  var out = []
  var taken = {}
  for (var i = 0; i < wantList.length; i++) {
    var k = wantList[i]
    if (taken[k]) continue
    taken[k] = true
    out.push({ key: k, leaving: false, fresh: !had[k] && !initial, slot: 0, leaveAt: 0 })
  }
  if (exitMs > 0) {
    for (var j = 0; j < prev.length; j++) {
      var r = prev[j]
      if (wanted[r.key]) continue
      var at = 0
      for (var b = j - 1; b >= 0 && at === 0; b--) {
        for (var o = 0; o < out.length; o++) {
          if (out[o].key === prev[b].key) { at = o + 1; break }
        }
      }
      out.splice(at, 0, { key: r.key, leaving: true, fresh: false, slot: 0,
        leaveAt: r.leaving ? r.leaveAt : now + exitMs })
    }
  }
  return _slots(out)
}

// The rows without the leaving ones whose exit has ended by now.
function expire(rows, now) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) {
    var r = rows[i]
    if (r.leaving && r.leaveAt <= now) continue
    out.push({ key: r.key, leaving: r.leaving, fresh: r.fresh, slot: 0, leaveAt: r.leaveAt })
  }
  return _slots(out)
}

// When the next leaving row's exit ends, or -1 for none.
function nextExpiry(rows) {
  var best = -1
  for (var i = 0; i < (rows || []).length; i++) {
    if (rows[i].leaving && (best < 0 || rows[i].leaveAt < best)) best = rows[i].leaveAt
  }
  return best
}

// Row keys for the sections that are lists of objects.
function tileKey(t) { return t && t.type === "group" ? "app:" + t.appId : "win:" + (t && t.win ? t.win.address : "") }
function folderKey(f) { return f && f.command ? "cmd:" + (f.name || "") + ":" + f.command : "path:" + (f ? f.path : "") }
function driveKey(d) { return "dev:" + (d ? d.dev : "") }
