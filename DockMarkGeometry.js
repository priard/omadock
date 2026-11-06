// Pure helpers for how big a dock mark is and how much room it needs
// (components/DockIndicatorRow.qml and components/DockIndicator.qml). Plain JS with no Qt globals, so the node tests run
// it in a vm context like DockLabels.js: the callers pass Style.space as
// `space` and the output's pixel grid as `dpr`.
//
// One owner, because the same numbers are drawn in two places: the row sizes
// the cell each mark sits in, and the indicator draws the dot and the bar.
// Spelled out in each file, changing one silently disagreed with the other -
// the same family as the row that declared a grid slot it did not draw.
//
// The room a mark gets is the mark: `cell` is the widest of the marks the row
// draws (the dot and the bar, each already carrying the hairline floor), so a
// theme that makes the spacing scale very compact can shrink a mark and its
// cell together, but never the cell alone. The floor itself has one owner,
// `hairline`, and every mark that is drawn applies it.

// Style.space units. The dock's classic marks: a 5 px dot (4 px when the marks
// are dense), a 12x4 accent bar (9x4 dense) and 3 px between marks (2 px
// dense).
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
// The dot's spacing: dense marks use the smaller one.
function dotSpace(dense) { return dense ? DOT_DENSE : DOT }

// Whole device pixels, never below one: at a fractional output scale a mark
// lost or gained a row of pixels depending on where it landed.
function snap(v, dpr) { return Math.max(1, Math.round(v * dpr)) / dpr }

// The thinnest a mark may be drawn: a hairline of whole device pixels. The one
// owner of the floor rule - `dot` and `barThickness` apply it, `cell` derives
// from those, so a mark can never be bigger than the room its cell reserves.
function hairline(dpr) { return 2 / dpr }

// The cell the row gives each mark: as tall across the row as the widest mark
// the row can draw there, so a dot and the accent bar share one centre line -
// and a compact theme that shrinks the spacing scale shrinks cell and mark
// together.
function cell(space, dpr, dense) {
  return Math.max(dot(space, dpr, dense), barThickness(space, dpr))
}

// A dot's own size, a hairline at the very least so it stays visible.
function dot(space, dpr, dense) {
  return Math.max(hairline(dpr), snap(space(dotSpace(dense)), dpr))
}

// The accent bar's thickness (the same across the row as a dot) and its length
// along the row.
function barThickness(space, dpr) { return Math.max(hairline(dpr), snap(space(BAR), dpr)) }
function barLength(space, dpr, dense) { return snap(space(dense ? BAR_LENGTH_DENSE : BAR_LENGTH), dpr) }

// Room between the marks, and the overflow pill's own box.
function rowSpacing(space, dpr, dense) { return snap(space(dense ? SPACING_DENSE : SPACING), dpr) }
function pillWidth(space, textWidth) { return textWidth + space(PILL_PAD) }
function pillHeight(space) { return space(PILL_HEIGHT) }
