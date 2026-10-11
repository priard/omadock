# Dock fit: a cascade for a dock wider than its screen

Date: 2026-10-11. Status: design approved in chat, spec for review.

## Problem

Nothing limits the dock's width today. A floating dock's card is as wide as
its row and grows past the screen edges. Panel and Both sides stretch the
card to the screen, and a row wider than the card runs past its right edge
(`DockLayout.rowOffset` stops at 0). Enough pinned apps, running apps,
minimized-window tiles, folders and drives push items off screen, where
they cannot be reached.

## Goal

The dock always fits its screen. When room runs out it gives room back in
a fixed order, least painful first. Only when nothing else is left do
items move into a "»" overflow popup. There is no setting: a dock
running off screen is a bug, not a preference.

## The cascade (user decisions)

The dock steps down in this order and stops at the first step where the
row fits:

1. **Shorter labels.** The effective label max width goes from the
   configured value down to `LABEL_MAX_WIDTH_MIN` (80). Labels shorten
   with the existing rules (`DockLabels.shortenName`).
2. **Folded labels.** Names fold to their icon, using the mechanism of
   "Pinned apps: When running" (#63). The order is closed pinned apps,
   then every app, then everything (groups, folders).
3. **Spacing.** Item spacing and section spacing go down to their
   minimum.
4. **Icon size.** Icons shrink smoothly down to a floor of
   `max(24, iconSize / 2)`, where iconSize is the configured (or auto)
   size.
5. **Overflow "»".** Items leave the row from its very end: drives, then
   folders and buttons, then running apps, tiles, pinned apps and
   groups. A group counts as one item. The "»" tile sits at the end of
   the dock (with Both sides, at the end of the right group).

Steps 1 and 2 are skipped when labels are off or in hover mode (hover
labels take no room).

## Planner: `DockFit.js`

A pure JS module (no Qt globals), tested in node like `DockLayout.js`.
`plan(input)` returns the cascade's state in one pass. None of the
inputs depends on the plan, so the dock cannot oscillate on its own.

Input:

- `available`: the row's room.
  - Dock: window width less the card's outer gap on both sides
    (`anchoredX` uses `gapsOut * 2`) and the card's content insets.
  - Panel: window width less the content insets.
  - Both sides: `stretchedBox` width less the content insets.
- `items`: the row in order. Each item is `{ kind, pinned, running,
  labelFull, overflowable }`.
  - `kind` is one of: button, app, group, tile, folder, drive, separator.
  - `labelFull` is the full, unshortened name width in the label's own
    font, or 0 when the item has no label.
- `sizes`:
  - `iconSize` and `floor`;
  - item spacing and section spacing, each with its minimum;
  - separator width;
  - tile width factor (1.5);
  - label overhead (pad, gap and trail, as `DockLabel` adds them);
  - plates on/off and the plate grid.
- `labelMax`: the configured label max width.
- `labels`: whether labels are on and take room (`always`).
- `waveReserve`: the extra width the Wave hover can add (about
  `0.4 * iconSlot * 2.18`, the sum of the cosine weights over ±2.2
  slots). It is 0 for the other hover effects, which scale the art and
  not the slot.

Output:

```
{ labelMax, fold: "none"|"closedPinned"|"apps"|"all",
  spacing, sectionSpacing, iconSize, overflowFrom: index|-1 }
```

Width model:

- A label at limit `L` adds `min(labelFull, L) + overhead`. Real
  shortening cuts whole words, so the drawn label is never wider than
  predicted.
- Slots, separators and tiles follow `Dock.baseRowWidth`: slots times
  `iconSlot`, tiles times `round(iconSlot * 1.5)`, separators times
  `separatorWidth`, and gaps between all shown elements.
- With overflow, the "»" tile's own slot and gap count too.

Continuous steps (1, 3, 4) are solved directly: the largest value that
fits, clamped to the step's range. Icon size stays a whole pixel, on the
plate grid when plates are on. Discrete steps (2, 5) are tried in order.

Hysteresis: the plan relaxes to a gentler step only when the row would
fit with a margin of `Style.space(8)`. A window appearing and
disappearing right at the edge does not flip labels back and forth.

## Applying the plan

`components/logic/DockFitLogic.qml` gathers the inputs, holds the plan
and recomputes it deferred through a child `Timer` (interval 0, not
`Qt.callLater`; see the #61 lesson about invalidated contexts). A burst of
changes therefore gives one new plan. `Dock.qml` is near its CI line cap,
so it only gets a few effective properties.

- `labelMax`: `DockLabelLogic.style()` returns
  `maxWidth = min(labelMaxWidth, plan.labelMax)`. Labels reshorten on the
  style change, as they already do.
- `fold`: `DockLabel.folded` becomes the OR of `labelPinned` folding and
  the plan's fold for that item. The resting plate, the tooltip with the
  name and the background-media column all come from #63.
- `spacing`: `gapWidth` and `sectionGap` read the effective values.
- `iconSize`: `Dock.iconSize` becomes `min(configured or auto,
  plan.iconSize)`. `iconSlot` and `baseIconArt` follow it, and so do
  about seven direct consumers. Settings keep showing
  `configuredIconSize`, and the config does not change.
- `overflowFrom`: items at or past the index get `shown: false` (RowSlot
  drops them together with their spacing), and the "»" tile appears.
- `DockLabel` reports its full name width (a `TextMetrics` on the full
  text) to a registry next to `labelExtras`.

Motion follows the Animations level (`Dock.motion`):

- Full: widths, icon size and spacing ease through the existing `layout`
  behaviours, names fold as in #63, and items leaving for "»" exit like
  other row items (narrow, scale 0.6, fade).
- Reduced: fades only; sizes snap.
- Off: everything is instant.

## The "»" tile and popup

The tile is a `DockIconButton`-like tile at the end of the row. It
carries:

- a plate (`TilePlate`) in a plate row;
- a tooltip "N more";
- a small mark when any hidden app has windows;
- the summed urgent state and notification badges of the hidden items,
  so they are not lost.

`components/OverflowPopup.qml` lives in a `DockPopupWindow` with its own
`PopupLife`. Its rivals are the stack, group and menu lives, and they
list it in turn, so a hand-over never dismisses the new popup (the
group-menu fix). It looks like an opened group (the popup grid from #55):
icon, name and window marks per cell, in dock order.

Interactions (variant 1, no drag):

- Click acts as on the dock:
  - an app launches or cycles its windows, and the popup stays open as
    in a group;
  - a group opens its popup and a folder opens its stack, each replacing
    the overflow popup;
  - a drive opens;
  - a minimized-window tile restores its window.
- Right click opens the item's own menu, anchored over the cell, as the
  right click in an opened group does.
- The popup closes on a click outside, on Esc, when the dock hides, and
  when "»" goes away because the row fits again.

## Edge cases

- **Both sides and split:** both groups count. The spread gap has a
  floor and never takes room from items.
- **Several monitors:** each dock plans for its own screen.
- **Dragging on the dock:** the plan is frozen while a drag is active,
  so drop zones do not move. It recomputes after the drop.
- **Open popups:** a plan change does not move the anchor of an open
  stack or group unless that anchor's item leaves for "»", in which case
  the popup closes.
- **One item wider than the screen:** the plan bottoms out with
  everything but "»" overflowed. The planner never returns a negative
  size.
- **Empty dock:** an empty plan, the configured values.

## Code layout

- `DockFit.js`: the planner.
- `components/logic/DockFitLogic.qml`: inputs, plan, deferred recompute.
- `components/OverflowPopup.qml`, plus the "»" tile at the row's end
  (`DockRightGroup`, or `DockCard` when there is no right group).
- `Dock.qml`: the effective properties only (CI caps: `Dock.qml` 2412,
  `DockModel.js` 1326).
- `DockLabel.qml`: the full-width report, and `folded` ORed with the
  plan.

## Testing

- Node unit tests for `DockFit.js`:
  - each step on its own: label shortening, the fold order, spacing,
    icons down to the floor, overflow from the end;
  - hysteresis;
  - the Wave reserve;
  - Both sides;
  - an empty dock;
  - one item wider than the screen;
  - plate-grid rounding.
- `structure-check.py` on the branch.
- Live checks:
  - a temporary debug property overrides the available width through IPC;
  - screenshots of each step, and of the open "»" popup through a
    temporary debug IPC call;
  - all debug code removed afterwards and grepped for.
- By hand (user): clicking in "»", menus, animations.

## Branch

`feat/dock-fit` from `upstream/experimental`. If #59 and #63 are still
open it is cut from `feat/pinned-labels`, since the cascade uses its name
folding, and rebased once those merge. No PR before the user has tested
it.
