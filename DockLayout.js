// Pure helpers for the dock's layout (Dock or Panel) and its alignment
// (Dock.qml placement, components/DockCard.qml). Plain JS with no Qt
// globals, so the node tests run it in a vm context like DockLabels.js.

// "panel" spans the screen's bottom edge; anything else is the floating dock.
function normalizeLayout(v) {
  return String(v === undefined || v === null ? "" : v).toLowerCase() === "panel" ? "panel" : "dock"
}

// "spread" (Both sides) puts folders and drives at the right edge.
function normalizeAlignment(v) {
  var a = String(v === undefined || v === null ? "" : v).toLowerCase()
  return (a === "left" || a === "right" || a === "spread") ? a : "center"
}

// Both sides needs room to open a gap: the full-width panel, or a dock
// split into panels.
function spreadAvailable(layout, splitSections) {
  return normalizeLayout(layout) === "panel" || splitSections === true
}

// What the dock draws for the stored settings. The panel is one bar, so
// it ignores split sections; Both sides falls back to center where it
// cannot open a gap, and to left when nothing would go right.
function placement(layout, alignment, splitSections, hasRightGroup) {
  var panel = normalizeLayout(layout) === "panel"
  var split = !panel && splitSections === true
  var align = normalizeAlignment(alignment)
  if (align === "spread" && !spreadAvailable(layout, splitSections)) align = "center"
  if (align === "spread" && !hasRightGroup) align = "left"
  return { panel: panel, split: split, align: align }
}

// The card's x and width when it does not hug its icons: the panel spans
// the window; a spread dock spans it less the inset on each side. null:
// the card is as wide as its row.
function stretchedBox(place, windowWidth, inset) {
  if (place.panel) return { x: 0, width: windowWidth }
  if (place.align === "spread") return { x: inset, width: Math.max(0, windowWidth - 2 * inset) }
  return null
}

// Rounds to whole device pixels when a scale is given (label plates keep
// their edges on the grid); whole logical pixels otherwise.
function snap(v, dpr) {
  return dpr > 0 ? Math.round(v * dpr) / dpr : Math.round(v)
}

// Where the row starts inside a stretched card, past the content inset.
// A row wider than the card starts at the left edge.
function rowOffset(align, innerWidth, rowWidth, dpr) {
  var free = Math.max(0, innerWidth - rowWidth)
  if (align === "right") return dpr > 0 ? snap(free, dpr) : free
  if (align === "center") return snap(free / 2, dpr)
  return 0
}

// Width of the gap between the left group and the right one; the gap item
// has the row spacing on both sides.
function spreadGap(innerWidth, leftWidth, rightWidth, spacing, dpr) {
  var w = Math.max(0, innerWidth - leftWidth - rightWidth - 2 * spacing)
  return dpr > 0 ? Math.max(0, Math.floor(w * dpr) / dpr) : w
}

// How far the right group's resting centres sit past where a packed row
// would put them: the card's free width at rest.
function spreadHomeShift(innerWidth, restWidth) {
  return Math.max(0, innerWidth - restWidth)
}
