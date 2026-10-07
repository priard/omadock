# Panel layout and both-sides alignment — design

Date: 2026-10-07. Branch: `feat/panel-layout` from `upstream/experimental`,
PR with `--base experimental` (only once the user gives the go-ahead),
then merged into `priard`.

## Goal

A second dock layout, **Panel**, in the spirit of a Windows taskbar: the
background spans the full screen width and sits flush on the bottom edge,
and Alignment only moves the icons inside it. The current behaviour stays
as the **Dock** layout. A new alignment, **Both sides**, puts the Omarchy
button, pinned apps, minimized tiles and running apps on the left and
folders and drives on the right, in both layouts.

## Decisions

- Layout names: Dock / Panel (`layout: "dock" | "panel"`).
- Both sides is a fourth Alignment value, not a separate setting.
- The split point is fixed: the right side starts at the folder section
  (`folderSeparator`). Not configurable (can be added later without a
  config format change).
- Panel ignores Split sections: always one continuous bar, sections
  separated by the ordinary divider lines.
- Panel corners are always square; Corner radius is hidden in Panel.
- Approach A: the existing card stretches and a flexible gap opens before
  the folders. No second card, no separate background item.

## Config

- New key `layout`: `"dock"` (default) or `"panel"`; anything else reads
  as `"dock"`.
- `alignment` accepts `"spread"` (UI label "Both sides") besides
  `left | center | right`; unknown values still fall back to `"center"`.
  No migration needed.
- `effectiveAlignment` (Dock.qml) is what the layout reads:
  - Dock without Split sections: `"spread"` behaves as `"center"`. The
    stored value stays, so toggling split back on restores it.
  - Spread with an empty right group (no folders, no drives) behaves as
    `"left"`.
- Presets do not store `layout` or `alignment` (they already skip
  alignment). A preset with `splitSections: true` applied in Panel keeps
  the value; it shows once the layout is Dock again.

## Settings UI

Placement page (`components/settings/SettingsPlacement.qml`), Position:

- **Layout** — ChoiceRow Dock / Panel. Hint: "Panel spans the screen's
  full width along the bottom edge."
- **Alignment** — Left / Center / Right / Both sides. In Dock without
  Split sections, Both sides is disabled with the hint "Needs Split
  sections (Appearance)."; when it is the stored value, the hint says it
  acts as Center for now.

Appearance page in Panel: Split sections, Section spacing and Corner
radius are hidden. Their values stay in the config.

`SettingsSearch.js`: new `layout` entry (terms: panel, taskbar, dock,
full width) on the placement page; `alignment` gains "both sides",
"spread".

## Geometry

All pure layout math lives in a new `DockLayout.js` (like `DockLabels.js`)
so it can be unit-tested offline: effective alignment, card x and width,
row offset, spread gap, home centres of the right group.

Card placement (`components/DockCard.qml`, `cardWrapper`):

| Layout + alignment | Card x | Card width | Bottom margin | Radius |
|---|---|---|---|---|
| Dock, left/center/right | as today | row width + insets | `gapsOut` (+ shadowRoom) | as today |
| Dock + split, both sides | `gapsOut` | window width − 2·`gapsOut` | as today | as today |
| Panel, any | 0 | window width | 0 | 0 |

Panel surface: rim only on the top edge (sides and bottom lie on the
screen edge), shadow only upwards, fill / gradient / opacity / grain /
blur / divider lines / presets unchanged.

Icons inside a fixed-width card. Today the card grows with the `Row`
under magnification; in a fixed card a `rowOffset` takes that role:

- left: content starts at the left inset;
- right: content ends at the right inset and grows leftwards (as the
  right-aligned dock does today);
- center: content centred on its live width (as the centred dock does
  today);
- both sides: a `spreadGap` before `folderSeparator`, width = card width
  − live width of everything else. The left group is anchored left, the
  right group right; growth under magnification eats the gap instead of
  pushing icons off screen. Right-group home centres are measured from the
  right edge, so they stay independent of magnification and the wave
  cannot chase itself.

`segments` (DockCard.qml): Panel always yields one segment. Dock + spread
cuts at `folderSeparator`, whose width is then the spread gap.

Labels (PR #47): label plates work in Panel unchanged (side labels give a
classic taskbar). Mirroring stays for right alignment; in spread the right
group is mirrored.

## Layer window (`Dock.qml`, `dockWindow`)

- Exclusive zone in Panel: `dockCard.height` (no `gapsOut * 2`).
- Headroom for magnification, bounce and the Unpin bubble: unchanged.
- Hitbox / mask: in Panel the hitbox is the card itself, no 24 px side
  extension and no strip below the card. In Dock + spread the hitbox spans
  the whole stretched card including the gap: the gap is transparent but
  takes the pointer so the magnification wave does not break between the
  groups; clicks in it do nothing. Known trade-off: windows under the gap
  lose clicks in that band; if that bites, narrow the mask to the
  segments.
- Reveal strip (autohide): full screen width in Panel and in spread.
- Autohide: unchanged; the panel slides down by its height.
- Multi-monitor: each instance computes from its own window.
- Blur layer rule: unchanged, the mask covers the background.

Popups, menus and tooltips anchor to items and need no change; verify
that a tooltip for an icon at the very left or right screen edge is
pushed inwards.

## Testing

- Offline (`tests/unit`): `DockLayout.js` for every combination of
  layout × alignment × split × empty right group; config parsing of
  `layout` and `spread` including unknown values.
- Static: qmllint via `bash tests/run-all.sh`.
- Live: `tests/smoke-test.sh`; screenshots of Panel × left / center /
  right / both sides, Dock + split + both sides, Panel with label plates
  (config backup, Python edit, `sleep 1.5`, `grim`, restore).
- The user tests clicking, dragging between the groups, magnification
  across the gap, and autohide.

## Out of scope

- Configurable split point or per-section side.
- Panel on other screen edges (top / left / right).
- Animated transition between layouts.
- Split plates inside the panel.
