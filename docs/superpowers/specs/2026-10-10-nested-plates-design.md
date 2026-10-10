# Nested plate corners, plates in split sections, bigger side marks

Date: 2026-10-10. Status: approved in chat.

## Goal

Label plates (always-on labels, Plate background) read as part of the dock
they sit in: between each other they meet with square corners, and the
plates that touch a panel's edge follow the panel's own rounding, so the two
curves run parallel (nested radii). This works in split sections too, which
today switch plates off. Separately, the window marks in the side column on
plates get bigger, because two small dots without the active bar look lost.

## Behaviour

### Corners: new value `nested`

- `labelShape` gets a fifth value `nested`, labelled "Nested" in the Corners
  row. `dock`, `pill`, `rounded`, `square` stay as they are; `dock` stays the
  default. No config migration.
- Inner corners (plate next to plate, plate next to a divider, plate next to
  the Both sides gap without split) have radius 0.
- Corners on a panel edge get `min(h / 2, max(0, R - gap))`, where `R` is the
  dock's corner radius (`effectiveCardRadius`) and `gap` the plate gap (the
  same as plate-to-edge). Both corners on that side (top and bottom) round.
- Split sections: every section is its own panel, so the outermost plates of
  every section round on their section's edges; with Both sides plus split,
  the two sides of the gap round too.
- "Outermost" means the item actually at the edge: the Omarchy button has its
  own plate (TilePlate) and takes the left rounding; drives have no plate, so
  when a drive stands at the edge, the last plate before it stays square (a
  drive section of its own in split has no plates at all).
- Square dock and Panel layout (R = 0): every corner is square.
- Plate height Icon: the plate does not reach the dock's top and bottom; the
  same formula with the horizontal gap is used.
- Pill backgrounds and hover labels never touch an edge: with `nested` they
  draw as with `dock`.

### Plates in split sections

`Dock.labelPlates` no longer requires `!placement.split`. The plate rules
stay: one gap for plate-plate and plate-section edge, Icon/Dock plate height,
side indicator column. Section panels (`DockCard.segments`) must end exactly
one gap past their outer plates, on the device-pixel grid.

### Side marks

In the vertical column on plates the dots use the full dot size (`DOT`, 8
physical px at scale 1.5) instead of `DOT_DENSE`, and the upright active bar
is as thick as the dots (8 px). The column the plate reserves grows with
them (`DockMarkGeometry.column`).

## Implementation

- `DockLabels.plateEdges(sections, split, spreadSplit)`: pure. `sections` is
  the row's sections in DockCard order (Omarchy button, pinned, groups,
  tiles, running, folders and buttons, drives), each `{ n, plated }` with the
  count of visible items. Returns, per label slot, `{ left, right }` (true when
  the plate stands at its panel's edge). Logical, not geometric, so the
  magnification wave cannot change it. Without split the whole row is one
  panel; with split each section is.
- `DockLabels.plateCorners(shape, h, dockRatio, R, gap, edges)`: pure, returns
  `{ tl, tr, bl, br }`; any shape other than `nested` gives four equal radii
  from `labelRadius` (with the existing `0.32 h` cap the callers apply).
- `DockLabelLogic.plateEdgeAt(root, slot)`; `Dock.qml` gets one property for
  the edge list (Dock.qml has a line cap).
- `DockLabel.qml` plate and `TilePlate.qml` set `topLeftRadius` and friends
  (Qt 6.11).
- Settings: Corners row gets "Nested" and a hint; `SettingsSearch.js` gets the
  term; `LABEL_SHAPES` accepts it (presets too).
- `DockMarkGeometry.js`: `dotSpace` uses `DOT` in a column; bar thickness in a
  column equals the dot; `column()` follows.

## Branches

- `feat/nested-plates` (corners + plates in split) and `feat/side-mark-size`
  (marks), both from `upstream/experimental`, merged into `priard`. Upstream
  PRs only when the user says so.

## Testing

- Unit tests in `tests/unit` for `plateEdges`, `plateCorners`, the mark
  geometry; `bash tests/run-all.sh`, `tests/static/structure-check.py`.
- Live: grim screenshots of rounded dock with plate height Icon and Dock,
  split, split + Both sides, square dock, Panel; PIL measurement of the
  plate-to-section-edge gaps in split.
- The user tests clicks and drags on plates in split by hand.
