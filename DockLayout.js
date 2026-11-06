// Pure helpers for the dock's alignment (Dock.qml placement,
// components/DockCard.qml). Plain JS with no Qt
// globals, so the node tests run it in a vm context like DockLabels.js.

// "spread" (Both sides) puts folders and drives at the right edge.
function normalizeAlignment(v) {
  var a = String(v === undefined || v === null ? "" : v).toLowerCase()
  return (a === "left" || a === "right" || a === "spread") ? a : "center"
}

// Both sides needs room to open a gap: a dock split into panels.
function spreadAvailable(splitSections) {
  return splitSections === true
}

// What the dock draws for the stored settings. Both sides falls back to
// center where it cannot open a gap, and to left when nothing would go right.
function placement(alignment, splitSections, hasRightGroup) {
  var split = splitSections === true
  var align = normalizeAlignment(alignment)
  if (align === "spread" && !spreadAvailable(splitSections)) align = "center"
  if (align === "spread" && !hasRightGroup) align = "left"
  return { split: split, align: align }
}

// The card's x and width when it does not hug its icons: a spread dock
// spans the window less the inset on each side. null: the card is as wide
// as its row.
function stretchedBox(place, windowWidth, inset) {
  if (place.align === "spread") return { x: inset, width: Math.max(0, windowWidth - 2 * inset) }
  return null
}

// Rounds to whole device pixels when a scale is given; whole logical pixels
// otherwise.
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

// Width of the gap between the left group and the right one, so the right
// group ends on the inner edge. gapX is where the gap item starts (the row
// spacing after the left group is already in it); one more spacing stands
// between the gap and the right group.
// The gap never reaches 0: a Row skips a zero-width child together with the
// spacing after it, so when magnification used up a small gap the right
// group would jump left by one spacing. It bottoms out at one device pixel
// (one logical pixel without a scale) instead.
function spreadGap(innerWidth, gapX, rightWidth, spacing, dpr) {
  var w = innerWidth - gapX - rightWidth - spacing
  return dpr > 0 ? Math.max(1 / dpr, Math.floor(w * dpr) / dpr) : Math.max(1, w)
}

// How far the right group's resting centres sit past where a packed row
// would put them: the card's free width at rest.
function spreadHomeShift(innerWidth, restWidth) {
  return Math.max(0, innerWidth - restWidth)
}
