// The dock's fit to its screen (docs/superpowers/specs/2026-10-11-dock-fit-design.md):
// when the row would be wider than its room, it gives width back in a fixed
// order - tighter spacing, smaller icons - and only then moves items from the
// end of the row into "»". Plain JS with no Qt globals, so the node tests run
// it in a vm context like DockLayout.js.
//
// Nothing in the input depends on the plan (counts are the dock's own lists),
// so the dock cannot chase its own result.

// Wave magnification: the hovered slot grows by 0.4 and its neighbours by
// the cosine weights over +-2.2 slots, about 2.18 slots' worth in all.
var WAVE_GROWTH = 0.4 * 2.18

function _slot(input, iconSize) { return Math.round(iconSize + input.slotPad) }
function _gap(input, t) { return input.gapMin + t * (input.gapMax - input.gapMin) }

// The items kept in the row for a cut: separators that no longer stand
// between two kept items go too.
function _kept(items, cut) {
  var n = cut < 0 ? items.length : cut
  var out = []
  for (var i = 0; i < n; i++) out.push(items[i])
  while (out.length > 0 && out[out.length - 1].kind === "separator") out.pop()
  var clean = []
  for (var j = 0; j < out.length; j++) {
    if (out[j].kind === "separator" && (clean.length === 0 || clean[clean.length - 1].kind === "separator")) continue
    clean.push(out[j])
  }
  return clean
}

// exact: the packed row as drawn at rest, without the Wave reserve and the
// Both sides gap item (DockCard.spreadShift measures the right group's shift
// with it).
function rowWidth(input, cand, exact) {
  var slot = _slot(input, cand.iconSize)
  var gap = _gap(input, cand.t)
  var sep = input.sepMin + cand.t * (input.sepMax - input.sepMin)
  var kept = _kept(input.items || [], cand.overflowFrom)
  var w = 0
  var count = kept.length
  for (var i = 0; i < kept.length; i++) {
    var it = kept[i]
    if (it.kind === "separator") w += sep
    else if (it.kind === "tile") w += Math.round(slot * input.tileFactor)
    else w += slot
  }
  if (cand.overflowFrom >= 0) { w += slot; count++ }
  // Items the row always holds whatever the cut (Both sides' gap item: one
  // more spacing, and its one-pixel floor).
  if (!exact) {
    w += (input.fixedWidth || 0)
    count += (input.fixedGaps || 0)
  }
  w += Math.max(0, count - 1) * gap
  if (input.wave && count > 0 && !exact) w += Math.ceil(slot * WAVE_GROWTH)
  return w
}

function _fits(input, cand, room) { return rowWidth(input, cand) <= room }

// Largest integer in [lo, hi] for which ok(v) holds, given ok is monotone
// (true up to some value). lo - 1 when none.
function _maxInt(lo, hi, ok) {
  if (!ok(lo)) return lo - 1
  while (lo < hi) {
    var mid = Math.ceil((lo + hi) / 2)
    if (ok(mid)) lo = mid
    else hi = mid - 1
  }
  return lo
}

function _solve(input, room) {
  var c = { t: 1, iconSize: input.iconSize, overflowFrom: -1 }
  if (_fits(input, c, room)) return _done(input, c, 0)
  // 1. spacing: bisect t.
  if (_fits(input, { t: 0, iconSize: input.iconSize, overflowFrom: -1 }, room)) {
    var lo = 0, hi = 1
    for (var k = 0; k < 24; k++) {
      var mid = (lo + hi) / 2
      if (_fits(input, { t: mid, iconSize: input.iconSize, overflowFrom: -1 }, room)) lo = mid
      else hi = mid
    }
    return _done(input, { t: lo, iconSize: input.iconSize, overflowFrom: -1 }, 1 - lo)
  }
  // 2. icons down to the floor.
  var size = _maxInt(input.floor, input.iconSize, function(s) {
    return _fits(input, { t: 0, iconSize: s, overflowFrom: -1 }, room)
  })
  if (size >= input.floor) {
    var range = Math.max(1, input.iconSize - input.floor)
    return _done(input, { t: 0, iconSize: size, overflowFrom: -1 }, 1 + (input.iconSize - size) / range)
  }
  // 3. overflow from the end: the most items kept that still fit.
  var n = (input.items || []).length
  var cut = _maxInt(0, n - 1, function(k) {
    return _fits(input, { t: 0, iconSize: input.floor, overflowFrom: k }, room)
  })
  if (cut < 0) cut = 0
  // A cut right after a separator draws the same row; keep the separator
  // with the hidden part so the cut always follows a real item.
  var all = input.items || []
  while (cut > 0 && all[cut - 1].kind === "separator") cut--
  return _done(input, { t: 0, iconSize: input.floor, overflowFrom: cut }, 2 + (n - cut) / Math.max(1, n))
}

function _done(input, c, level) {
  return { level: level, t: c.t, gap: _gap(input, c.t),
    iconSize: c.iconSize, overflowFrom: c.overflowFrom, width: rowWidth(input, c), rest: rowWidth(input, c, true) }
}

// The plan for this input. prev: the plan in force; a gentler plan than it
// is taken only when it also fits with input.margin to spare, so a window
// coming and going right at the edge does not flip the dock back and forth.
function plan(input, prev) {
  var room = Math.max(0, Number(input.available) || 0)
  var next = _solve(input, room)
  if (prev && next.level < prev.level) {
    var held = _solve(input, Math.max(0, room - (input.margin || 0)))
    if (held.level > next.level) return held.level >= prev.level ? Object.assign({}, prev, _done(input, prev, prev.level)) : held
  }
  return next
}
