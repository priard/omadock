// Pure helpers for how big a dock mark is and how much room it needs
// (components/DockIndicatorRow.qml, components/DockIndicator.qml and
// components/DockLabel.qml). Plain JS with no Qt globals, so the node tests run
// it in a vm context like DockLabels.js: the callers pass Style.space as
// `space` (the same way they pass a measuring function to DockLabels) and the
// output's pixel grid as `dpr`.
//
// One owner, because the same numbers are drawn in three places: the row sizes
// the cell each mark sits in, the indicator draws the dot and the bar, and a
// plate reserves the column's room before the icon or after the name. Spelled
// out in each file, changing one silently disagreed with the others - the same
// family as the row that declared a grid slot it did not draw.

// Style.space units. The dock's classic marks: a 5 px dot (4 px when the marks
// are dense, or stand in a side column), a 12x4 accent bar (9x4 dense) and 3 px
// between marks (2 px dense).
var DOT = 5
var DOT_DENSE = 4
var BAR = 4
var BAR_LENGTH = 12
var BAR_LENGTH_DENSE = 9
var SPACING = 3
var SPACING_DENSE = 2
// The compact overflow pill past five windows: its own padding and height.
var PILL_PAD = 4
var PILL_HEIGHT = 5
// The room a plate keeps for the column of marks: its inset from the plate's
// edge and the gap from there to the art or the name.
var EDGE = 1
var GAP = 5

// The dot's spacing: dense marks and a side column use the smaller one.
function dotSpace(dense, vertical) { return (dense || vertical) ? DOT_DENSE : DOT }

// Whole device pixels, never below one: at a fractional output scale a mark
// lost or gained a row of pixels depending on where it landed.
function snap(v, dpr) { return Math.max(1, Math.round(v * dpr)) / dpr }

// The cell the row gives each mark: as wide across the row (or column) as the
// widest mark, so a dot and the accent bar share one centre line.
function cell(space, dpr, dense, vertical) {
  return Math.max(snap(space(dotSpace(dense, vertical)), dpr), snap(space(BAR), dpr))
}

// A dot's own size, a hairline at the very least so it stays visible.
function dot(space, dpr, dense, vertical) {
  return Math.max(2 / dpr, snap(space(dotSpace(dense, vertical)), dpr))
}

// The accent bar's thickness (the same across the row as a dot) and its length
// along the row - upright in a column, where it is as thick as a dot.
function barThickness(space, dpr) { return Math.max(2 / dpr, snap(space(BAR), dpr)) }
function barLength(space, dpr, dense) { return snap(space(dense ? BAR_LENGTH_DENSE : BAR_LENGTH), dpr) }

// Room between the marks, and the overflow pill's own box.
function rowSpacing(space, dpr, dense) { return snap(space(dense ? SPACING_DENSE : SPACING), dpr) }
function pillWidth(space, textWidth) { return textWidth + space(PILL_PAD) }
function pillHeight(space) { return space(PILL_HEIGHT) }

// The room a plate reserves for its column of marks: the plate's inset for it,
// the column's width - a dot's, one cell wide, so the marks sit centred in it -
// and the gap to the art or the name.
function column(space, dpr) {
  return { edge: space(EDGE), width: snap(space(BAR), dpr), gap: space(GAP) }
}
